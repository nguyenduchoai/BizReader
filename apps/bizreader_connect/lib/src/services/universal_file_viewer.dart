import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class UniversalFileViewerException implements Exception {
  const UniversalFileViewerException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class FileViewer {
  Future<void> open(File file);
}

class UniversalFileViewer implements FileViewer {
  static const _channel = MethodChannel(
    'vn.bizreader.connect/universal_viewer',
  );

  @override
  Future<void> open(File file) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const UniversalFileViewerException(
        'Trình đọc đa định dạng hiện chỉ hỗ trợ Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('openFile', {'path': file.path});
    } on PlatformException catch (error) {
      throw UniversalFileViewerException(
        error.message ?? 'Không thể mở tệp đã chọn.',
      );
    }
  }
}
