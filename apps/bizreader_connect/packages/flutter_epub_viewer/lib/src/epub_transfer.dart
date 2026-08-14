import 'dart:convert';
import 'dart:typed_data';

/// Keeps each JavaScript bridge call bounded while preserving 3-byte base64
/// boundaries, so the WebView can decode every chunk independently.
const int epubTransferChunkBytes = 192 * 1024;

Iterable<String> encodeEpubChunks(Uint8List data) sync* {
  for (var offset = 0; offset < data.length; offset += epubTransferChunkBytes) {
    final end = (offset + epubTransferChunkBytes).clamp(0, data.length);
    yield base64Encode(Uint8List.sublistView(data, offset, end));
  }
}
