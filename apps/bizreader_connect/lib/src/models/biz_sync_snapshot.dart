import 'biz_content.dart';
import 'biz_device_section.dart';
import 'device_reading_progress.dart';

class BizSyncSnapshot {
  const BizSyncSnapshot({
    required this.content,
    required this.progress,
    this.device,
  });

  final BizContent content;
  final List<DeviceReadingProgress> progress;

  /// Phần cấu hình máy đọc — tùy chọn; firmware cũ bỏ qua key này.
  final BizDeviceSection? device;

  static List<DeviceReadingProgress> _boundedProgress(
    Iterable<DeviceReadingProgress> values,
  ) {
    final newestByFilename = <String, DeviceReadingProgress>{};
    for (final value in values) {
      if (value.filename.isEmpty) continue;
      final previous = newestByFilename[value.filename];
      if (previous == null || value.updatedAt > previous.updatedAt) {
        newestByFilename[value.filename] = value;
      }
    }
    final newest = newestByFilename.values.toList()
      ..sort((a, b) {
        final timestamp = b.updatedAt.compareTo(a.updatedAt);
        return timestamp != 0 ? timestamp : a.filename.compareTo(b.filename);
      });
    return newest.take(100).toList(growable: false);
  }

  static List<DeviceReadingProgress> mergeProgress(
    List<DeviceReadingProgress> local,
    List<DeviceReadingProgress> remote,
  ) {
    bool hasReadingPosition(DeviceReadingProgress item) =>
        item.percentage > 0 ||
        item.spineIndex > 0 ||
        item.pageNumber > 0 ||
        item.pageCount > 0;

    final merged = <String, DeviceReadingProgress>{};
    for (final item in remote) {
      if (item.filename.isNotEmpty) merged[item.filename] = item;
    }
    for (final item in local) {
      final previous = merged[item.filename];
      final preserveLegacyDevicePosition =
          previous != null &&
          previous.updatedAt == 0 &&
          hasReadingPosition(previous) &&
          !hasReadingPosition(item);
      if (!preserveLegacyDevicePosition &&
          (previous == null || item.updatedAt > previous.updatedAt)) {
        merged[item.filename] = DeviceReadingProgress(
          filename: item.filename,
          percentage: item.percentage,
          spineIndex: item.spineIndex,
          pageNumber: item.pageNumber,
          pageCount: item.pageCount,
          pending: true,
          updatedAt: item.updatedAt,
        );
      }
    }
    return _boundedProgress(merged.values);
  }

  Map<String, Object?> toJson() {
    final deviceJson = device?.toJson();
    return {
      'protocol': 2,
      'content': content.toJson(),
      'progress': _boundedProgress(
        progress,
      ).map((item) => item.toJson()).toList(),
      if (deviceJson != null && deviceJson.isNotEmpty) 'device': deviceJson,
    };
  }

  factory BizSyncSnapshot.fromJson(Map<String, Object?> json) {
    if ((json['protocol'] as num?)?.toInt() != 2) {
      throw const FormatException('BizReader Sync không tương thích');
    }
    final content = json['content'];
    final progress = json['progress'];
    if (content is! Map || progress is! List) {
      throw const FormatException('Snapshot BizReader không hợp lệ');
    }
    final device = json['device'];
    return BizSyncSnapshot(
      content: BizContent.fromJson(content.cast<String, Object?>()),
      progress: _boundedProgress(
        progress.whereType<Map>().map(
          (item) =>
              DeviceReadingProgress.fromJson(item.cast<String, Object?>()),
        ),
      ),
      device: device is Map
          ? BizDeviceSection.fromJson(device.cast<String, Object?>())
          : null,
    );
  }
}
