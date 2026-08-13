import 'package:bizreader_connect/src/models/biz_content.dart';
import 'package:bizreader_connect/src/models/biz_sync_snapshot.dart';
import 'package:bizreader_connect/src/models/device_reading_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot keeps the 100 newest unique reading positions', () {
    final snapshot = BizSyncSnapshot(
      content: const BizContent(),
      progress: [
        for (var index = 0; index < 101; index++)
          DeviceReadingProgress(
            filename: 'book-$index.epub',
            percentage: index / 101,
            updatedAt: index,
          ),
        const DeviceReadingProgress(
          filename: 'book-100.epub',
          percentage: 0.9,
          updatedAt: 500,
        ),
      ],
    );

    final progress = snapshot.toJson()['progress'] as List;

    expect(progress, hasLength(100));
    expect(
      progress.where((item) => (item as Map)['filename'] == 'book-100.epub'),
      hasLength(1),
    );
    expect(
      progress.where((item) => (item as Map)['filename'] == 'book-0.epub'),
      isEmpty,
    );
  });

  test('maps device page position to chapter percentage', () {
    const progress = DeviceReadingProgress(
      filename: 'book.epub',
      percentage: 0.4,
      pageNumber: 12,
      pageCount: 25,
    );

    expect(progress.chapterProgressPercent, 50);
  });

  test(
    'legacy device progress beats an untouched old app import timestamp',
    () {
      const local = DeviceReadingProgress(
        filename: 'book.epub',
        percentage: 0,
        updatedAt: 1000,
      );
      const remote = DeviceReadingProgress(
        filename: 'book.epub',
        percentage: 0.6,
        spineIndex: 4,
        pageNumber: 12,
        pageCount: 25,
        updatedAt: 0,
      );

      final merged = BizSyncSnapshot.mergeProgress([local], [remote]);

      expect(merged.single.percentage, 0.6);
      expect(merged.single.spineIndex, 4);
    },
  );

  test('genuinely read app progress still beats legacy device progress', () {
    const local = DeviceReadingProgress(
      filename: 'book.epub',
      percentage: 0.2,
      spineIndex: 1,
      updatedAt: 1000,
    );
    const remote = DeviceReadingProgress(
      filename: 'book.epub',
      percentage: 0.6,
      spineIndex: 4,
      updatedAt: 0,
    );

    final merged = BizSyncSnapshot.mergeProgress([local], [remote]);

    expect(merged.single.percentage, 0.2);
    expect(merged.single.pending, isTrue);
  });
}
