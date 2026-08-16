import 'dart:typed_data';
import 'package:flutter_epub_viewer/src/epub_data_loader.dart';
import 'package:flutter_epub_viewer/src/io/file_loader.dart';

/// Epub file source
class EpubSource {
  final EpubDataLoader _loader;

  EpubSource._(this._loader);

  /// Loads the EPUB bytes on demand.
  ///
  /// Lazy by design: file/url/asset sources retain no byte buffer between
  /// loads, so the Dart heap does not hold a whole-book copy for the lifetime
  /// of the viewer (the JS runtime keeps its own copy after `loadBook`). Each
  /// call re-reads from the underlying source.
  Future<Uint8List> get epubData => _loader.loadData();

  ///Loading from a file.
  ///
  ///Not supported on the web — use [EpubSource.fromUrl], [EpubSource.fromAsset]
  ///or [EpubSource.fromData] instead.
  factory EpubSource.fromFile(File file) {
    return EpubSource._(FileEpubLoader(file));
  }

  ///Loading from a filesystem path.
  ///
  ///Same as [EpubSource.fromFile], but takes a plain path so callers do not
  ///have to depend on the platform-conditional `File` type (`dart:io` on
  ///native, a stub on the web, where reading throws [UnsupportedError]).
  factory EpubSource.fromFilePath(String path) {
    return EpubSource._(FileEpubLoader(File(path)));
  }

  ///load from a url with optional headers
  factory EpubSource.fromUrl(String url, {Map<String, String>? headers}) {
    return EpubSource._(UrlEpubLoader(url, headers: headers));
  }

  ///load from assets
  factory EpubSource.fromAsset(String assetPath) {
    return EpubSource._(AssetEpubLoader(assetPath));
  }

  ///load from in-memory bytes (works on every platform, including the web)
  factory EpubSource.fromData(Uint8List data) {
    return EpubSource._(DataEpubLoader(data));
  }
}
