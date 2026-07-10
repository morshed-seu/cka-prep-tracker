# CKA Prep — 8-Week Internals Tracker

A single-page, dependency-free study tracker for the Certified Kubernetes Administrator (CKA) exam:

- **8 weeks, ~160 tiny checkpoints** you can tick off; progress saves in the browser (localStorage — per device, no backend).
- Every topic pairs the hands-on exam task with an **"Under the hood"** note explaining the internals.
- Exam-day countdown (set your date in the sidebar), per-week progress nav, light/dark theme toggle.
- Built for the post-Feb-2025 CKA curriculum (Gateway API, Helm, Kustomize, CRDs, CNI internals).

Everything lives in one file: [`index.html`](index.html). No build step, no dependencies.

## Run locally

Open `index.html` in a browser, or:

```bash
python3 -m http.server 8000
# → http://localhost:8000
```

## Publish on GitHub Pages

1. Create a repository on GitHub (e.g. `cka-prep`) and push:

   ```bash
   git remote add origin git@github.com:<your-username>/cka-prep.git
   git push -u origin main
   ```

2. On GitHub: **Settings → Pages → Build and deployment** — set *Source* to **Deploy from a branch**, choose branch **`main`** and folder **`/ (root)`**, then save.

3. After a minute the site is live at `https://<your-username>.github.io/cka-prep/`.

> Note: GitHub Pages sites on the free plan are public. Progress is stored in each browser's localStorage, so your checkmarks stay on your device and are not shared through the site.
