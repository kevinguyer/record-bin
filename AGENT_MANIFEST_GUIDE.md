# Agent Guide — Publishing New Art to the Gallery

**Audience:** the Album Gallery agent (and whoever maintains it).
**Supersedes:** Sections 4.2, 6 (Step 6 row), and 10 of the original PRD wherever they conflict. The web app now reads **`manifest.json`** with the schema below. Where the PRD and this document disagree, **this document wins.**

---

## 1. What changed vs. the PRD

The kiosk web app (`index.html`) is already built and deployed. It reads a single file — **`docs/manifest.json`** — to discover what to display. Your job each run ends with **adding one entry to that file** (and committing the image alongside it).

**Where the website lives:** GitHub Pages serves the **`docs/`** folder, not the repo root. So every site file is under `docs/`: the app is `docs/index.html`, the manifest is `docs/manifest.json`, and artwork goes in `docs/images/album-art/`. The repo root holds planning docs and tooling that are version-controlled but **not** published. All the GitHub API paths below therefore start with `docs/`.

Two concrete changes from the original PRD you must honor:

1. **`album` is now a required field** on every image entry. Spotify returns it as `track.album.name`. Capture it and write it into the manifest. The web app shows artist → song → album as an MTV-style lower-third caption; a missing album just leaves that line blank, but you should always populate it.
2. **The manifest has a top-level `starters` array.** Do **not** touch it. It lists the two startup images the kiosk shows on load. Leave it exactly as-is when you rewrite the file.

Everything else about your pipeline (Spotify fetch, dedupe against local `history.json`, image generation, GitHub upload) is unchanged from the PRD. Only **Step 6 (manifest update)** is redefined here.

---

## 2. Repository layout the app expects

```
<repo root>/
├── docs/                            # GitHub Pages serves THIS folder
│   ├── index.html                   # the kiosk app — do not edit
│   ├── manifest.json                # YOU maintain this (source of truth)
│   └── images/
│       ├── starter-images/          # startup images — do not touch
│       │   ├── 1.png
│       │   └── 2.png
│       └── album-art/               # YOU add generated covers here
│           ├── BlueOysterCult_DancinInTheRuins.png
│           └── DuaLipa_TheseWalls.png
├── AGENT_MANIFEST_GUIDE.md          # this file (not published)
├── Album_Gallery_Agent_PRD.md       # planning doc (not published)
├── generate-manifest.ps1            # offline scaffold tool (not published)
└── .gitignore
```

- New generated artwork goes in **`docs/images/album-art/`** (GitHub API path).
- Paths *inside* `manifest.json` are **relative to `index.html`** (i.e. relative to `docs/`) and use **forward slashes** (`images/album-art/Foo.png`) — they do **not** include the `docs/` prefix. Only the GitHub API file paths include `docs/`.

---

## 3. `manifest.json` schema (authoritative)

```json
{
  "version": 1,
  "gallery_name": "Album Gallery",
  "updated_at": "2026-06-03T14:30:00Z",
  "starters": [
    "images/starter-images/1.png",
    "images/starter-images/2.png"
  ],
  "images": [
    {
      "id": "20260603-143000-these-walls",
      "filename": "DuaLipa_TheseWalls.png",
      "path": "images/album-art/DuaLipa_TheseWalls.png",
      "artist": "Dua Lipa",
      "song": "These Walls",
      "album": "Radical Optimism",
      "generated_at": "2026-06-03T14:30:00Z"
    }
  ]
}
```

### Top-level fields

| Field | Required | Notes |
|-------|----------|-------|
| `version` | yes | Keep `1`. Bump only if the schema changes. |
| `gallery_name` | yes | Display name; leave as-is. |
| `updated_at` | yes | ISO 8601 UTC. Set to the current time on **every** commit. |
| `starters` | yes | Array of startup image paths. **Leave untouched.** |
| `images` | yes | Array of image entries (below). Append new entries to the **end**. |

### Per-image fields (every field required)

| Field | Source | Notes |
|-------|--------|-------|
| `id` | derived | Stable unique key: `{YYYYMMDD}-{HHMMSS}-{slug}`. See slug rules §5. |
| `filename` | derived | The file's name only, e.g. `DuaLipa_TheseWalls.png`. |
| `path` | derived | `images/album-art/{filename}`, forward slashes. |
| `artist` | Spotify `track.artists[0].name` | Primary (first) artist. Exact string from Spotify. |
| `song` | Spotify `track.name` | Exact string from Spotify. |
| `album` | Spotify `track.album.name` | **Required.** Exact string from Spotify. |
| `generated_at` | run clock | ISO 8601 UTC timestamp of generation. |

**Resilience contract:** the web app ignores unknown fields, so you may add extra metadata later (e.g. `track_id`, `year`) without breaking anything. Never *remove* or *rename* the fields above.

---

## 4. The update procedure (replaces PRD Step 6)

After the image is generated and uploaded to `docs/images/album-art/{filename}` (PRD Step 5), update the manifest:

1. **Fetch** the current manifest via the GitHub Contents API. Keep its `sha`.
   ```
   GET https://api.github.com/repos/{OWNER}/{REPO}/contents/docs/manifest.json
   ```
2. **Decode** the base64 `content` and parse the JSON.
3. **Append** a new object to the `images` array using the schema in §3. Append to the end; do not reorder existing entries.
4. **Set** the top-level `updated_at` to the current UTC time.
5. **Do not modify** `starters`, `version`, or `gallery_name`.
6. **Commit** the updated file back, passing the `sha` you fetched:
   ```
   PUT https://api.github.com/repos/{OWNER}/{REPO}/contents/docs/manifest.json
   {
     "message": "Update manifest: {ARTIST} - {SONG}",
     "content": "{BASE64_OF_UPDATED_JSON}",
     "sha": "{SHA_FROM_STEP_1}",
     "branch": "main"
   }
   ```

**SHA-conflict handling (unchanged from PRD):** if the PUT returns `409`, re-fetch (step 1), re-apply (steps 3–4), and retry once. If it fails again, abort and log — the image is already uploaded, so the next successful run can reconcile.

**Ordering guarantee:** upload the image (Step 5) *before* the manifest entry (Step 6). The app only references images named in the manifest, so an uploaded-but-unlisted image is invisible (harmless) until listed, but a manifest entry pointing at a missing image would show a blank frame.

---

## 5. Deriving `id`, `filename`, and `path`

- **slug** = `song` title, lowercased, spaces → hyphens, non-alphanumeric stripped, collapsed hyphens, truncated to 60 chars.
  - `"These Walls"` → `these-walls`
  - `"Dancin' in the Ruins"` → `dancin-in-the-ruins`
- **id** = `{YYYYMMDD}-{HHMMSS}-{slug}` in UTC, e.g. `20260603-143000-these-walls`.
- **filename** = whatever you saved the image as in `images/album-art/`. The existing convention is `ArtistNameNoSpaces_SongTitleNoSpaces.png` (e.g. `DuaLipa_TheseWalls.png`), but any unique, filesystem-safe name is fine as long as `filename` and `path` match the real file.
- **Collisions (variant art):** if the filename already exists, append `-v2`, `-v3`, … before the extension, and reflect that in `filename`, `path`, and `id`.

---

## 6. How the web app uses the manifest (FYI — no action needed)

So you understand the impact of your writes:

- On load, the app shows a **random `starters` image** first, then rotates through `images` in a reshuffled random order (no back-to-back repeats).
- Each image is shown for **60 seconds** with a crossfade + slow zoom.
- The **caption** (artist on top, song beneath, album under that) fades in with each new image and fades out after **10 seconds**, MTV-style.
- The app **re-fetches `manifest.json` every 5 minutes**, so new entries you commit appear within ~5 minutes **without a page reload**. It folds new images into the rotation automatically and only rebuilds its queue when the set of paths actually changes.
- The page also does a **full self-refresh every 8 hours** as a backstop.

Because of the 5-minute poll, **you do not need to do anything to the running kiosk** — just commit the image and the manifest entry, and the display picks it up.

---

## 7. Quick checklist per run

- [ ] Image uploaded to `docs/images/album-art/{filename}` and committed (PRD Step 5).
- [ ] Fetched `docs/manifest.json` + its `sha`.
- [ ] Appended one `images` entry with **all** fields, including **`album`**.
- [ ] Updated `updated_at`.
- [ ] Left `starters`, `version`, `gallery_name` untouched.
- [ ] Committed with the correct `sha`; handled a 409 with one retry.
- [ ] Updated local `history.json` (PRD Step 7) and logged the run (PRD Step 8).

---

## 8. Local manifest helper (optional, for manual/offline edits)

If you ever rebuild the file from the images on disk instead of via the GitHub API, `generate-manifest.ps1` in the repo root scans `docs/images/starter-images/` and `docs/images/album-art/` and writes a baseline `docs/manifest.json`. **Caveat:** it cannot know artist/song/album metadata, so it is only a scaffold — the agent (with Spotify data) is the authoritative source for those fields. Prefer the API procedure in §4 for normal operation.
