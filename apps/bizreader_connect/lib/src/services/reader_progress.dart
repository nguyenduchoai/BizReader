class ReaderProgress {
  const ReaderProgress({
    required this.overall,
    required this.chapterNumber,
    required this.chapterProgress,
    required this.pageNumber,
    required this.pageCount,
  });

  final double overall;
  final int chapterNumber;
  final double chapterProgress;
  final int pageNumber;
  final int pageCount;

  factory ReaderProgress.fromLocation({
    required double overall,
    required int spineIndex,
    required int pageNumber,
    required int pageCount,
  }) {
    final safeCount = pageCount < 0 ? 0 : pageCount;
    final maxPage = safeCount > 0 ? safeCount - 1 : 0;
    final safePage = pageNumber.clamp(0, maxPage);
    final chapterProgress = safeCount > 1
        ? safePage * 100 / (safeCount - 1)
        : 0.0;
    return ReaderProgress(
      overall: overall.clamp(0, 1),
      chapterNumber: spineIndex < 0 ? 1 : spineIndex + 1,
      chapterProgress: chapterProgress.clamp(0, 100),
      pageNumber: safePage,
      pageCount: safeCount,
    );
  }
}
