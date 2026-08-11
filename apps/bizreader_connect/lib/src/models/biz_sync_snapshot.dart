import 'biz_content.dart';
import 'device_reading_progress.dart';

class BizSyncSnapshot {
  const BizSyncSnapshot({required this.content, required this.progress});

  final BizContent content;
  final List<DeviceReadingProgress> progress;

  Map<String, Object?> toJson() => {
    'protocol': 2,
    'content': content.toJson(),
    'progress': progress.take(100).map((item) => item.toJson()).toList(),
  };

  factory BizSyncSnapshot.fromJson(Map<String, Object?> json) {
    if ((json['protocol'] as num?)?.toInt() != 2) {
      throw const FormatException('BizReader Sync không tương thích');
    }
    final content = json['content'];
    final progress = json['progress'];
    if (content is! Map || progress is! List) {
      throw const FormatException('Snapshot BizReader không hợp lệ');
    }
    return BizSyncSnapshot(
      content: BizContent.fromJson(content.cast<String, Object?>()),
      progress: progress
          .whereType<Map>()
          .map(
            (item) =>
                DeviceReadingProgress.fromJson(item.cast<String, Object?>()),
          )
          .where((item) => item.filename.isNotEmpty)
          .toList(),
    );
  }
}
