int epubResumeIndex({
  required List<int> chapterStartIndexes,
  required int chapterNumber,
  required double chapterProgress,
  required double bookProgress,
}) {
  if (chapterStartIndexes.isEmpty) return 0;
  final chapterIndex = chapterNumber > 0
      ? (chapterNumber - 1).clamp(0, chapterStartIndexes.length - 1)
      : (bookProgress * chapterStartIndexes.length).floor().clamp(
          0,
          chapterStartIndexes.length - 1,
        );
  final start = chapterStartIndexes[chapterIndex];
  if (chapterIndex + 1 >= chapterStartIndexes.length) return start;

  final next = chapterStartIndexes[chapterIndex + 1];
  if (next <= start + 1) return start;
  final ratio = (chapterProgress / 100).clamp(0, 1);
  return start + ((next - start - 1) * ratio).round();
}
