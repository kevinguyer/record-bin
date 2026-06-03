# record-bin

An agent-fed gallery that turns Kevin's Spotify listening into a rotating
display of original, AI-generated 45 RPM single sleeves.

## Repository layout

```
record-bin/
├── docs/                       # ← GitHub Pages serves THIS folder (the website)
│   ├── index.html              #    the kiosk slideshow app
│   ├── manifest.json           #    source of truth for what's displayed
│   └── images/
│       ├── starter-images/     #    shown on load (1.png, 2.png)
│       └── album-art/          #    generated covers (agent appends here)
├── Album_Gallery_Agent_PRD.md  # original product spec (not published)
├── AGENT_MANIFEST_GUIDE.md     # how the agent updates the gallery (not published)
├── generate-manifest.ps1       # offline manifest scaffold tool (not published)
├── .gitignore
└── README.md
```

Only the contents of **`docs/`** are public. Everything at the repo root is
version-controlled but never served to the web.

## The web app (`docs/index.html`)

- Shows a random **starter image** on load, then rotates through `album-art/`
  covers in shuffled order (no back-to-back repeats).
- Each cover displays for **60 seconds** with a crossfade + slow zoom, shown
  full and centered over a blurred backdrop of itself.
- An **MTV-style lower-third caption** (artist / song / album) fades in with
  each new cover, holds for 10 seconds, then fades out.
- **Polls `manifest.json` every 5 minutes** to pick up new art with no reload,
  and does a full **self-refresh every 8 hours** as a backstop.

It's a single self-contained HTML file — no build step, no dependencies.

## GitHub Pages setup (one time)

1. Push this repo to GitHub.
2. **Settings → Pages → Build and deployment.**
3. Source: **Deploy from a branch**. Branch: **`main`**, folder: **`/docs`**. Save.
4. Wait ~1 minute. Your site goes live at
   `https://<your-username>.github.io/<repo-name>/`.

To update the gallery, the agent commits a new image into
`docs/images/album-art/` and appends an entry to `docs/manifest.json`
(see **AGENT_MANIFEST_GUIDE.md**). The live page reflects it within ~5 minutes.

## Local preview

```
python -m http.server 8899 --directory docs
```

Then open <http://localhost:8899>. (Serve over HTTP, not `file://`, so the app
can fetch `manifest.json`.)
