import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_epub_viewer/src/epub_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chunks a large EPUB into independently decodable bridge messages', () {
    final data = Uint8List.fromList(
      List<int>.generate(
        epubTransferChunkBytes * 2 + 17,
        (index) => index % 251,
      ),
    );

    final chunks = encodeEpubChunks(data).toList();
    final restored = <int>[for (final chunk in chunks) ...base64Decode(chunk)];

    expect(chunks, hasLength(3));
    expect(base64Decode(chunks.first), hasLength(epubTransferChunkBytes));
    expect(restored, data);
  });

  test('empty input produces no transfer chunks', () {
    expect(encodeEpubChunks(Uint8List(0)), isEmpty);
  });
}
