import 'package:bizreader_connect/src/services/epub_resume_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores a relative position inside the synced chapter', () {
    final index = epubResumeIndex(
      chapterStartIndexes: const [0, 100, 220],
      chapterNumber: 2,
      chapterProgress: 50,
      bookProgress: 0.45,
    );

    expect(index, 160);
  });

  test('falls back to overall progress when chapter is unknown', () {
    final index = epubResumeIndex(
      chapterStartIndexes: const [0, 100, 220, 400],
      chapterNumber: 0,
      chapterProgress: 0,
      bookProgress: 0.6,
    );

    expect(index, 220);
  });

  test('clamps synced chapter progress inside the current chapter', () {
    expect(
      epubResumeIndex(
        chapterStartIndexes: const [0, 100, 220],
        chapterNumber: 2,
        chapterProgress: 200,
        bookProgress: 0,
      ),
      219,
    );
  });
}
