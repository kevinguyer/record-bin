# Album Gallery Agent — Product Requirements Document

**Version:** 1.0
**Date:** 2026-05-27
**Status:** Draft — Phase 1 (Agent Pipeline)

---

## 1. Purpose

Build an automated pipeline that transforms a listener's Spotify history into a growing gallery of original AI-generated album art. An OpenClaw agent running locally on a cron schedule will periodically check recently played songs, select one for processing, generate a stylized 45 RPM single sleeve image, and publish it to a GitHub Pages repository where a kiosk web app displays the collection as a rotating slideshow.

---

## 2. Architecture Overview

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌───────────────┐
│  Spotify API │ ──▶ │  Dedupe      │ ──▶ │  Gemini LLM  │ ──▶ │ Google Imagen │
│  (recently   │     │  (local      │     │  (interpret   │     │ (generate     │
│   played)    │     │   history)   │     │   song, craft │     │  1920×1080    │
└─────────────┘     └──────────────┘     │   img prompt) │     │  image)       │
                                          └──────────────┘     └───────┬───────┘
                                                                       │
                                          ┌──────────────┐     ┌───────▼───────┐
                                          │ Update local │ ◀── │ Publish to    │
                                          │ history.json │     │ GitHub repo   │
                                          └──────────────┘     │ (image +      │
                                                               │  manifest)    │
                                                               └───────────────┘
```

**Runtime:** OpenClaw agent, running locally, using Claude models for orchestration. Scheduled via cron, 2–3 times per day.

---

## 3. Prerequisites & Setup

### 3.1 Spotify API

**One-time setup:**

1. Create a Spotify Developer App at https://developer.spotify.com/dashboard
2. Set a redirect URI (e.g., `http://localhost:8888/callback`)
3. Record the **Client ID** and **Client Secret**
4. Complete the OAuth2 Authorization Code flow to obtain a **refresh token** with the `user-read-recently-played` scope

**How to get the refresh token:**

1. Direct the user's browser to:
   ```
   https://accounts.spotify.com/authorize?client_id={CLIENT_ID}&response_type=code&redirect_uri={REDIRECT_URI}&scope=user-read-recently-played
   ```
2. After authorization, Spotify redirects to your URI with a `code` parameter
3. Exchange the code for tokens:
   ```
   POST https://accounts.spotify.com/api/token
   Content-Type: application/x-www-form-urlencoded

   grant_type=authorization_code&code={CODE}&redirect_uri={REDIRECT_URI}
   Authorization: Basic {base64(CLIENT_ID:CLIENT_SECRET)}
   ```
4. Store the `refresh_token` from the response. It does not expire unless the user revokes access.

**Ongoing token refresh (every agent run):**

```
POST https://accounts.spotify.com/api/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token={REFRESH_TOKEN}
Authorization: Basic {base64(CLIENT_ID:CLIENT_SECRET)}
```

Response provides a fresh `access_token` (valid ~1 hour).

**Credential storage:** Store `CLIENT_ID`, `CLIENT_SECRET`, and `REFRESH_TOKEN` in environment variables or a local `.env` file that the agent can read. Never commit these to the GitHub repo.

### 3.2 Google Cloud (Gemini + Imagen)

1. Create a Google Cloud project (or use an existing one)
2. Enable the **Generative Language API** (for Gemini) and the **Imagen API** (via Vertex AI or the generativelanguage endpoint)
3. Create an API key or service account credentials
4. Store the API key in the same `.env` / environment variable setup

**API options for image generation:**

- **Option A — Gemini with native image generation:** Recent Gemini models (Gemini 2.0 Flash and later) support generating images directly in a single call. The agent sends the full reasoning prompt to Gemini and receives both the text reasoning and the generated image. This is the simplest path.
- **Option B — Gemini reasoning + separate Imagen call:** Gemini reasons about the song and outputs a structured image generation prompt. The agent then passes that prompt to the Imagen API separately. More control over the image generation parameters, but two API calls.

**Recommendation:** Start with Option A. If image quality or control is insufficient, fall back to Option B.

### 3.3 GitHub Repository

1. Create a public GitHub repository (e.g., `album-gallery`)
2. Enable GitHub Pages (Settings → Pages → Deploy from branch `main`, root `/`)
3. Create a **Personal Access Token (PAT)** with `repo` scope (or fine-grained with Contents read/write on the specific repo)
4. Store the PAT in the agent's environment variables

**Initial repo structure:**

```
album-gallery/
├── index.html              # Kiosk web app (Phase 2)
├── manifest.json           # Image registry — the web app reads this
├── images/                 # Generated artwork
│   └── .gitkeep
└── README.md               # Optional
```

The agent will create and commit to this structure via the GitHub Contents API.

### 3.4 Local Files

The agent maintains one local file:

```
{AGENT_WORKING_DIR}/history.json
```

This file lives on the machine running the agent and is NOT committed to the GitHub repo.

---

## 4. Data Formats

### 4.1 Local History File (`history.json`)

```json
{
  "version": 1,
  "entries": [
    {
      "track_id": "4bN3LOhICKDOqfVGGJhpME",
      "artist": "The Replacements",
      "song": "Bastards of Young",
      "first_processed_at": "2026-05-27T14:30:00Z",
      "run_count": 1,
      "last_run_at": "2026-05-27T14:30:00Z"
    }
  ]
}
```

**Fields:**

- `track_id`: Spotify track ID — the primary deduplication key (unique per track across all of Spotify)
- `artist` / `song`: Exact strings as returned by Spotify (used for display and fallback matching)
- `first_processed_at`: ISO 8601 timestamp of the first time this song was processed
- `run_count`: How many times art has been generated for this song (incremented for variant art)
- `last_run_at`: Timestamp of the most recent generation

**Matching logic:** A song is considered "already processed" if there exists an entry where `track_id` matches (primary key), OR where both `artist` and `song` match case-insensitively (fallback for legacy entries). For multi-artist tracks, use the primary (first) artist only.

### 4.2 GitHub Manifest (`manifest.json`)

```json
{
  "version": 1,
  "gallery_name": "Album Gallery",
  "updated_at": "2026-05-27T14:30:00Z",
  "images": [
    {
      "id": "20260527-143000-bastards-of-young",
      "filename": "20260527-143000-bastards-of-young.png",
      "path": "images/20260527-143000-bastards-of-young.png",
      "artist": "The Replacements",
      "song": "Bastards of Young",
      "generated_at": "2026-05-27T14:30:00Z"
    }
  ]
}
```

**Image naming convention:**
```
{YYYYMMDD}-{HHMMSS}-{slugified-song-title}.png
```

Where `slugified-song-title` is the song name lowercased, spaces replaced with hyphens, non-alphanumeric characters stripped, truncated to 60 characters. If this would collide with an existing filename (variant art), append `-v2`, `-v3`, etc.

The manifest is the **single source of truth** for the web app. The kiosk page reads this file on load and periodically to discover new images.

---

## 5. Agent Workflow — Step by Step

Each agent run executes the following steps in order. If any step fails, the agent should log the error and exit gracefully (no partial state changes).

### Step 1: Refresh Spotify Access Token

```
POST https://accounts.spotify.com/api/token
grant_type=refresh_token
refresh_token={REFRESH_TOKEN}
Authorization: Basic {base64(CLIENT_ID:CLIENT_SECRET)}
```

Extract the `access_token` from the response. If this fails (network error, revoked token), abort the run with an error log.

### Step 2: Fetch Recently Played Tracks

```
GET https://api.spotify.com/v1/me/player/recently-played?limit=10
Authorization: Bearer {ACCESS_TOKEN}
```

From the response, extract for each item:
- `items[n].track.id` → Spotify track ID (unique identifier)
- `items[n].track.name` → song title
- `items[n].track.artists[0].name` → primary artist name

This returns up to 10 recently played tracks, ordered most-recent-first. Fetching more than 2 gives the dedupe logic a better chance of finding an unprocessed song before falling back to variant art mode.

**Edge case:** If the response contains 0 items, abort gracefully.

### Step 3: Deduplicate Against History

Load `history.json` from the local working directory. If the file does not exist (first run), create it with the empty structure `{"version": 1, "entries": []}` and proceed — every song will be new.

Iterate through the fetched tracks (most recent first) and apply this logic:

```
FOR each track in recently_played (index 0 = most recent):
    IF track is NOT in history:
        selected = track
        variant_mode = false
        BREAK

IF no unprocessed track found:
    selected = recently_played[0]  (variant art — already in history)
    variant_mode = true
```

**"In history"** means: an entry exists where `track_id` matches, OR (fallback) where both `artist` and `song` match case-insensitively. The `track_id` check is primary because different artists can have songs with the same title.

### Step 4: Generate the Image Prompt via Gemini

Take the prompt template from the file `image_gen_prompt.md` (stored alongside the agent's configuration — see Section 8 for the full template).

Substitute the placeholders:
- `{{ARTIST}}` → the selected song's artist
- `{{SONG}}` → the selected song's title

Send the filled prompt to **Gemini** (with image generation enabled).

**If using Option A (Gemini native image gen):**
Send the full prompt to Gemini in a single call. The response will contain both reasoning text and a generated image. Extract the image (base64-encoded) from the response.

**If using Option B (Gemini reasoning + separate Imagen call):**
Send the prompt to Gemini with an instruction to output only the final image generation prompt (a detailed text description). Then send that description to the Imagen API via Vertex AI:

```
POST https://{REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT_ID}/locations/{REGION}/publishers/google/models/imagen-3.0-generate-002:predict
Authorization: Bearer {GOOGLE_ACCESS_TOKEN}
Content-Type: application/json

{
  "instances": [{"prompt": "{GENERATED_PROMPT}"}],
  "parameters": {
    "sampleCount": 1,
    "aspectRatio": "16:9"
  }
}
```

Note: The Vertex AI endpoint requires a regional URL (e.g., `us-central1`). Authentication uses an OAuth2 access token from the service account, not a simple API key. If using the `generativelanguage.googleapis.com` endpoint instead, only Gemini's native image generation (Option A) is available there — Imagen is not exposed on that endpoint.

Extract the base64-encoded image from the response.

**Important notes:**
- The prompt instructs the model to generate a 1920×1080 (16:9) landscape image. Ensure the API call specifies 16:9 aspect ratio.
- Imagen may not render text on the sleeve perfectly. This is a known limitation of current image models. Accept the result — imperfect text on vinyl sleeves adds to the handmade aesthetic. Do NOT retry in a loop trying to get perfect text.
- Save the raw image bytes to a temporary local file before uploading to GitHub.

### Step 5: Upload the Image to GitHub

Generate the filename per the naming convention (Section 4.2).

Use the GitHub Contents API to create the file:

```
PUT https://api.github.com/repos/{OWNER}/{REPO}/contents/images/{FILENAME}
Authorization: Bearer {GITHUB_PAT}
Content-Type: application/json

{
  "message": "Add artwork: {ARTIST} - {SONG}",
  "content": "{BASE64_ENCODED_IMAGE}",
  "branch": "main"
}
```

If the upload fails, abort. Do not update the manifest or history.

### Step 6: Update the Manifest on GitHub

First, fetch the current `manifest.json`:

```
GET https://api.github.com/repos/{OWNER}/{REPO}/contents/manifest.json
Authorization: Bearer {GITHUB_PAT}
```

Decode the content (base64), parse the JSON, and append the new image entry:

```json
{
  "id": "{GENERATED_ID}",
  "filename": "{FILENAME}",
  "path": "images/{FILENAME}",
  "artist": "{ARTIST}",
  "song": "{SONG}",
  "generated_at": "{ISO_TIMESTAMP}"
}
```

Update the top-level `updated_at` field.

Then commit the updated manifest:

```
PUT https://api.github.com/repos/{OWNER}/{REPO}/contents/manifest.json
Authorization: Bearer {GITHUB_PAT}
Content-Type: application/json

{
  "message": "Update manifest: {ARTIST} - {SONG}",
  "content": "{BASE64_ENCODED_UPDATED_JSON}",
  "sha": "{CURRENT_FILE_SHA}",
  "branch": "main"
}
```

The `sha` field (from the GET response) is required to prove you're updating the latest version and prevent conflicts.

### Step 7: Update Local History

Update `history.json`:

- If the song is new (not in history): add a new entry with `track_id`, `artist`, `song`, `first_processed_at`, `run_count: 1`, and `last_run_at`
- If the song is already in history (variant art): increment `run_count` and update `last_run_at`

Write the file atomically (write to a temp file, then rename) to prevent corruption if the process is interrupted.

### Step 8: Log the Run

Append a line to a local `run_log.txt` (or similar) for debugging:

```
2026-05-27T14:30:00Z | OK | The Replacements - Bastards of Young | variant=false | image=20260527-143000-bastards-of-young.png
```

Or on failure:
```
2026-05-27T14:30:00Z | FAIL | Step 4 | Gemini API returned 429 Too Many Requests
```

---

## 6. Error Handling

| Step | Failure Mode | Action |
|------|-------------|--------|
| 1 (Token refresh) | Network error or revoked token | Log error, abort run. If token is revoked, alert user — requires re-auth. |
| 2 (Spotify fetch) | API error, rate limit, 0 results | Log error, abort run. Spotify rate limits are generous but respect 429s with backoff. |
| 3 (Dedupe) | `history.json` missing or corrupt | If missing, create a new empty history file and proceed (treat everything as new). If corrupt, log error and abort. |
| 4 (Image gen) | Gemini/Imagen API error, content filter block | Log error, abort run. Content filters may trigger on certain song titles — log which song caused it so the user can review. |
| 5 (GitHub upload) | API error, auth failure | Log error, abort. Do NOT update manifest or history. |
| 6 (Manifest update) | SHA conflict (concurrent update) | Retry once: re-fetch manifest, re-apply the addition, re-commit. If it fails again, abort. |
| 7 (History update) | File write error | Log error. The image is already published — next run will see the song in the manifest even if history is stale. |

**General principle:** Never leave the system in a half-updated state. The image upload (Step 5) and manifest update (Step 6) are the critical pair. If the image uploads but the manifest update fails, the image exists in the repo but is invisible to the web app — on the next successful run, you could add a recovery step that checks for orphaned images in the `images/` directory that aren't in the manifest.

---

## 7. Scheduling

**Cron expression (3x daily):**
```
0 9,14,20 * * *
```
Runs at 9:00 AM, 2:00 PM, and 8:00 PM local time.

Adjust to match when the user is most likely to have played new music. Evening runs will catch daytime listening; morning runs catch late-night sessions.

**Alternative (2x daily):**
```
0 10,21 * * *
```
Runs at 10:00 AM and 9:00 PM.

The agent should complete a full run in under 60 seconds under normal conditions (most time spent on image generation).

---

## 8. Prompt Template

The image generation prompt is maintained in `image_gen_prompt.md` (stored in the agent's working directory alongside `history.json`). The agent reads this file at the start of each run and performs `{{ARTIST}}` and `{{SONG}}` substitution before sending to Gemini.

This is the current version of the prompt — see the file itself for the canonical copy:

> You are an art director creating an ALTERNATE, original 45 RPM single sleeve for a song, staged inside a record shop...

The prompt includes:
- Song interpretation instructions (genre, era, mood, lyrics — including a web search/grounding step)
- Art style diversity requirements (documentary photo, cel-shaded anime, risograph, etc.)
- Two randomization gates: "37crows Records" store name (3-in-10 chance, integers 8/9/10) and "WXKG" sticker (1-in-10 chance, integer 10 only), with an explicit instruction to "lean toward leaving both out"
- Image composition requirements: 16:9 landscape, 1920×1080, square vinyl sleeve as focal object, record store setting
- Text requirements: artist name and song title legibly printed on the sleeve

**Do not modify this prompt** without the user's explicit approval. The prompt is designed to produce diverse, high-quality results and the randomization gates are intentional creative features.

**Note:** The current `image_gen_prompt.md` file contains a trailing paragraph (after the image generation instructions) about writing to a memory list and publishing to a specified location. This was scaffolding from the manual workflow and should be **removed before agent use** — the agent handles history and publishing via Steps 5–7 of this workflow, not via the image generation prompt. Leaving it in could confuse a model that reads the prompt literally.

---

## 9. Configuration Summary

All configuration should be stored in environment variables or a `.env` file accessible to the agent:

| Variable | Description |
|----------|-------------|
| `SPOTIFY_CLIENT_ID` | Spotify Developer App client ID |
| `SPOTIFY_CLIENT_SECRET` | Spotify Developer App client secret |
| `SPOTIFY_REFRESH_TOKEN` | OAuth2 refresh token (user-read-recently-played scope) |
| `GOOGLE_API_KEY` | Google Cloud API key for Gemini (Option A) or service account credentials path for Vertex AI (Option B) |
| `GOOGLE_PROJECT_ID` | Google Cloud project ID (required for Option B / Vertex AI only) |
| `GOOGLE_REGION` | Vertex AI region, e.g. `us-central1` (required for Option B only) |
| `GITHUB_PAT` | GitHub Personal Access Token with repo contents access |
| `GITHUB_OWNER` | GitHub username or org (repo owner) |
| `GITHUB_REPO` | Repository name (e.g., `album-gallery`) |
| `HISTORY_FILE_PATH` | Path to local `history.json` (default: `./history.json`) |
| `PROMPT_FILE_PATH` | Path to `image_gen_prompt.md` (default: `./image_gen_prompt.md`) |

---

## 10. Phase 2 Touchpoints

The web app (Phase 2) will be built independently but depends on the contract established here:

- **Reads `manifest.json`** from the repo root to discover images
- **Images are in `images/`** relative to the repo root
- **Manifest schema** is defined in Section 4.2 — the web app should be resilient to new fields being added
- **Polling for updates:** The kiosk page should periodically re-fetch `manifest.json` (e.g., every 5 minutes) to pick up new images without requiring a page reload
- **Display duration:** 60 seconds per image (configurable)
- **Transition effects:** Visual transition between slides (crossfade, slide, etc.)
- **No authentication required:** The GitHub Pages site is public

---

## 11. Open Questions

1. **Gemini model version:** Which Gemini model to target? Gemini 2.0 Flash is fast and cheap but image gen quality may vary. Gemini 2.5 Pro may produce better image prompts if using the two-step approach. Test both.

2. **Image format:** PNG is assumed throughout. JPEG would reduce file sizes significantly (~60-80% smaller for photographic images) at the cost of some quality. For a kiosk display, JPEG at quality 90 is likely indistinguishable. Consider JPEG if repo size becomes a concern.

3. **GitHub Pages bandwidth:** GitHub Pages has a soft bandwidth limit of 100GB/month. A single kiosk refreshing images shouldn't come close, but worth monitoring if the gallery grows very large.

4. **Notification on failure:** Should the agent send a notification (email, push) if a run fails? Or is checking the log file sufficient?

5. **Gallery curation:** Is there ever a need to remove images from the gallery? If so, the agent would need a "remove from manifest" capability, or the user does it manually.

---

## Appendix A: Example Run Trace

```
[2026-05-27T14:30:00Z] Starting Album Gallery Agent run
[2026-05-27T14:30:00Z] Step 1: Refreshing Spotify token... OK
[2026-05-27T14:30:01Z] Step 2: Fetching recently played...
  Song 1: "Bastards of Young" by The Replacements
  Song 2: "Ever Fallen in Love" by Buzzcocks
[2026-05-27T14:30:01Z] Step 3: Checking history...
  Song 1 "Bastards of Young": NOT in history
  → Selected: "Bastards of Young" by The Replacements
[2026-05-27T14:30:01Z] Step 4: Generating image via Gemini...
  Prompt template loaded, substitutions applied
  Gemini response received (image + reasoning)
  Image: 1920x1080 PNG, 847KB
[2026-05-27T14:30:18Z] Step 5: Uploading to GitHub...
  Filename: 20260527-143000-bastards-of-young.png
  Committed: abc123f
[2026-05-27T14:30:20Z] Step 6: Updating manifest...
  manifest.json SHA: def456a → new commit: ghi789b
  Gallery now contains 47 images
[2026-05-27T14:30:21Z] Step 7: Updating history...
  New entry added. History contains 43 unique songs.
[2026-05-27T14:30:21Z] Run complete. Duration: 21s
```

---

## Appendix B: Variant Art Run Trace

```
[2026-05-27T20:00:00Z] Starting Album Gallery Agent run
[2026-05-27T20:00:01Z] Step 2: Fetching recently played...
  Song 1: "Bastards of Young" by The Replacements
  Song 2: "Bastards of Young" by The Replacements
[2026-05-27T20:00:01Z] Step 3: Checking history...
  Song 1 "Bastards of Young": IN HISTORY (run_count: 1)
  Song 2 "Bastards of Young": IN HISTORY (same song)
  → Both processed. Selected: Song 1 (variant art mode)
[2026-05-27T20:00:01Z] Step 4: Generating image via Gemini...
  (proceeds normally — new art, same song)
  ...
[2026-05-27T20:00:19Z] Step 7: Updating history...
  Existing entry updated: run_count 1 → 2
```
