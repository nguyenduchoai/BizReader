class DeviceReadingProgress {
  const DeviceReadingProgress({
    required this.filename,
    required this.percentage,
    this.spineIndex = 0,
    this.pageNumber = 0,
    this.pageCount = 0,
    this.pending = false,
  });

  final String filename;
  final double percentage;
  final int spineIndex;
  final int pageNumber;
  final int pageCount;
  final bool pending;

  factory DeviceReadingProgress.fromJson(Map<String, Object?> json) {
    return DeviceReadingProgress(
      filename: json['filename'] as String? ?? '',
      percentage: ((json['percentage'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      spineIndex: (json['spineIndex'] as num?)?.toInt() ?? 0,
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 0,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      pending: json['pending'] as bool? ?? false,
    );
  }
}
