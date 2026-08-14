# BizReader local fork

This directory contains a source fork of `flutter_epub_viewer` 2.0.0 for the
BizReader Android application. The upstream BSD 3-Clause license is preserved
in `LICENSE`, together with epub.js 0.3.93 and its license in
`EPUBJS_LICENSE`. The upstream package's vulnerable JSZip 3.1.5 bundle was
replaced with JSZip 3.10.1 under its MIT option. `JSZIP_LICENSE` preserves its
license and `PAKO_LICENSE` covers the pako 1.0.5 code embedded in that bundle.
`EPUBJS_THIRD_PARTY_NOTICES.md` inventories the runtime dependency code
compiled into `epub.js`, records version ambiguities where generated code does
not prove one exact npm release, and preserves all applicable license texts.
The JSZip asset is byte-identical to BizReader's audited document-viewer copy
and has SHA-256
`acc7e41455a80765b5fd9c7ee1b8078a6d160bbbca455aeae854de65c947d59e`.

Local changes:

- upgrade JSZip from 3.1.5 to 3.10.1;
- deny every native WebView permission request;
- allow navigation only within the package renderer and its local EPUB frames;
- block remote EPUB image, font, CSS, media, and document subresources;
- disable autoplay, inline media, fullscreen, and script-created windows;
- transfer EPUB payloads across the Dart/JavaScript bridge in bounded 192 KiB
  chunks and decode directly into one preallocated byte array;
- disable Android content access, geolocation, WebView storage, cookies, form
  persistence, and caching for the local reader;
- report renderer failures through `EpubViewer.onDisplayError`;
- expose zero-based spine/page location data in `EpubLocation`;
- report the current CFI/location again after font or theme reflow.

EPUB scripted content remains disabled by default through
`EpubDisplaySettings.allowScriptedContent`.

The BizReader companion is Android-only. Other platform implementations remain
available for upstream compatibility, but are outside BizReader's release and
security support boundary.
