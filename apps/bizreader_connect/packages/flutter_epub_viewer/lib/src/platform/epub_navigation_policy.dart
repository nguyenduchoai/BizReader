/// The package-owned directory that may be loaded by the EPUB WebView.
const String epubViewerAssetPath =
    '/packages/flutter_epub_viewer/lib/assets/webpage/';

/// Local-file platforms must never fetch remote EPUB subresources.
bool shouldBlockEpubNetworkLoads({required bool isMacOS}) => !isMacOS;

/// Returns whether a WebView navigation is part of the local EPUB renderer.
///
/// The host page and its static assets are the only `file:` URLs accepted.
/// macOS serves the same directory from its loopback-only asset server. Blob
/// and data documents are limited to subframes because epub.js uses them to
/// render unpacked book resources.
bool isAllowedEpubNavigation(
  Uri? uri, {
  required bool isMacOS,
  int? localhostPort,
  bool isMainFrame = true,
}) {
  if (uri == null) return false;

  switch (uri.scheme.toLowerCase()) {
    case 'about':
      return uri.path == 'blank';
    case 'data':
      return !isMainFrame;
    case 'blob':
      return !isMainFrame &&
          _hasLocalBlobOrigin(
            uri.toString().substring('blob:'.length),
            isMacOS: isMacOS,
            localhostPort: localhostPort,
          );
    case 'file':
      return _isPackageAssetPath(uri.path);
    case 'http':
      return isMacOS &&
          uri.host.toLowerCase() == 'localhost' &&
          (localhostPort == null || uri.port == localhostPort) &&
          _isPackageAssetPath(uri.path);
    default:
      return false;
  }
}

bool _isPackageAssetPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  if (segments.any((segment) => segment == '.' || segment == '..')) {
    return false;
  }
  if (normalized.startsWith(epubViewerAssetPath)) return true;

  const marker = '/flutter_assets';
  final markerIndex = normalized.indexOf(marker);
  if (markerIndex <= 0 || normalized.indexOf(marker, markerIndex + 1) != -1) {
    return false;
  }
  final privateRoot = normalized.substring(0, markerIndex);
  if (!privateRoot.startsWith('/data/') &&
      !privateRoot.startsWith('/private/')) {
    return false;
  }
  return normalized
      .substring(markerIndex)
      .startsWith('$marker$epubViewerAssetPath');
}

bool _hasLocalBlobOrigin(
  String value, {
  required bool isMacOS,
  int? localhostPort,
}) {
  final origin = Uri.tryParse(value);
  if (origin == null) return false;

  if (origin.scheme == 'file') return true;
  return isMacOS &&
      origin.scheme == 'http' &&
      origin.host.toLowerCase() == 'localhost' &&
      (localhostPort == null || origin.port == localhostPort);
}
