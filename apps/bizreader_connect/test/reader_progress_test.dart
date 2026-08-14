import 'package:bizreader_connect/src/services/reader_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps EPUB location to zero-based chapter page progress', () {
    final position = ReaderProgress.fromLocation(
      overall: 0.42,
      spineIndex: 3,
      pageNumber: 6,
      pageCount: 13,
    );

    expect(position.overall, 0.42);
    expect(position.chapterNumber, 4);
    expect(position.pageNumber, 6);
    expect(position.pageCount, 13);
    expect(position.chapterProgress, 50);
  });

  test('clamps malformed page data to a valid reading position', () {
    final position = ReaderProgress.fromLocation(
      overall: 2,
      spineIndex: -4,
      pageNumber: 50,
      pageCount: 4,
    );

    expect(position.overall, 1);
    expect(position.chapterNumber, 1);
    expect(position.pageNumber, 3);
    expect(position.chapterProgress, 100);
  });
}
