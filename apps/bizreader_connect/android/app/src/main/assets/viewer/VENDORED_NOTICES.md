# Vendored viewer libraries

Gander renders Office formats, Markdown and spreadsheets with open source
JavaScript libraries bundled under `app/src/main/assets/viewer/lib/`. They are
vendored (not fetched at runtime) because the app has no network access at all.

`scripts/fetch-viewer-libs.sh` re-downloads every file below from its upstream.

| File | Project | Version | License | Upstream |
| --- | --- | --- | --- | --- |
| `pdf.min.mjs` | pdf.js (legacy build) | 5.7.284 | Apache-2.0 | https://github.com/mozilla/pdf.js |
| `pdf.worker.min.mjs` | pdf.js worker (legacy build) | 5.7.284 | Apache-2.0 | https://github.com/mozilla/pdf.js |
| `jszip3.min.js` | JSZip | 3.10.1 | MIT or GPL-3.0 dual | https://github.com/Stuk/jszip |
| `docx-preview.min.js` | docx-preview | 0.3.x (jsdelivr latest, fetched 2026-07-19) | Apache-2.0 | https://github.com/VolodymyrBaydalka/docxjs |
| `xlsx.full.min.js` | SheetJS Community Edition | 0.20.3 | Apache-2.0 | https://git.sheetjs.com/sheetjs/sheetjs |
| `marked.min.js` | marked | 15.0.12 | MIT | https://github.com/markedjs/marked |
| `purify.min.js` | DOMPurify | 3.4.12 | Apache-2.0 or MPL-2.0 dual | https://github.com/cure53/DOMPurify |
| `pptx/pptxjs.js` | PPTXjs | 1.21.1 | MIT | https://github.com/meshesha/PPTXjs |
| `pptx/divs2slides.js` | divs2slides (PPTXjs) | 1.3.2 | MIT | https://github.com/meshesha/PPTXjs |
| `pptx/filereader.js` | FileReader.js (PPTXjs bundle) | 0.99 | MIT | https://github.com/meshesha/PPTXjs |
| `pptx/jquery.min.js` | jQuery | 1.11.3 | MIT | https://github.com/jquery/jquery |
| `pptx/jszip2.min.js` | JSZip 2.x (PPTXjs bundle) | 2.x | MIT or GPL-3.0 dual | https://github.com/meshesha/PPTXjs |
| `pptx/d3.min.js` | D3 | 3.5.10 | BSD-3-Clause | https://github.com/d3/d3 |
| `pptx/nv.d3.min.js` | NVD3 | 1.8.1 | Apache-2.0 | https://github.com/novus/nvd3 |
| `pptx/pptxjs.css`, `pptx/nv.d3.min.css` | PPTXjs / NVD3 styles | see above | see above | see above |

## Before upgrading pdf.js

`pdf.html` is the only viewer loaded as an ES module, and a module the WebView
cannot parse never runs, so the page has no way to report the problem from inside
itself. That makes the Chromium floor a fact to check rather than a preference.

- The legacy build of 5.7.284 supports **Chromium 125 and newer** (Mozilla's
  pdf.js FAQ). That number is `PDFJS_MIN_CHROMIUM_MAJOR` in
  `app/src/main/java/com/arjun/gander/ViewerActivity.kt`, compared against the
  WebView package actually in use. Below it, `pdf.html` shows a card explaining
  that Android System WebView needs updating instead of loading the renderer.
- **Chromium 138 is the ceiling on Android 8.0, 8.1 and 9.0.** Chromium 139
  requires Android 10, so those releases will never receive a newer WebView, and
  minSdk here is 26. A pdf.js version needing more than 138 therefore does not
  degrade on API 26 to 28, it ends PDF support there. Check the new version's
  floor first: if it is above 138, this is a decision about dropping PDFs on
  Android 8 and 9, not a version bump.

Bumping pdf.js means editing together the two `pdf.*.mjs` rows above, `PDFJS` in
`scripts/fetch-viewer-libs.sh`, and `PDFJS_MIN_CHROMIUM_MAJOR`. The card's wording
lives in `pdf.html` and reads both version numbers out of the query string, so it
needs no edit.

Notes for packagers (F-Droid and friends): the minified files are unmodified
upstream distribution artifacts. If unminified sources are required, every
project above publishes them at the linked repository, and the fetch script can
be pointed at the unminified dist files where upstream provides them.
