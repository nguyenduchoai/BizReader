import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/device_config.dart';

class DeviceConnectionException implements Exception {
  const DeviceConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebDavDeviceClient {
  WebDavDeviceClient(this.device, {http.Client? client})
    : _client = client ?? http.Client();

  final DeviceConfig device;
  final http.Client _client;

  Uri pathUri(String path) {
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return device.baseUri.replace(pathSegments: segments);
  }

  Future<void> probe() async {
    try {
      if (device.transferToken.isNotEmpty) {
        final response = await _client
            .get(
              device.baseUri.resolve('/api/bizreader/status'),
              headers: {'X-BizReader-Token': device.transferToken},
            )
            .timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) {
          throw DeviceConnectionException(
            'Thiết bị phản hồi HTTP ${response.statusCode}.',
          );
        }
        return;
      }
      final request = http.Request('OPTIONS', device.baseUri);
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 500) {
        throw DeviceConnectionException(
          'Thiết bị phản hồi HTTP ${response.statusCode}.',
        );
      }
    } on TimeoutException {
      throw const DeviceConnectionException(
        'Hết thời gian chờ. Hãy mở Truyền tệp trên BizReader.',
      );
    } on SocketException {
      throw const DeviceConnectionException(
        'Không tìm thấy thiết bị trong mạng Wi-Fi hiện tại.',
      );
    } on http.ClientException {
      throw const DeviceConnectionException(
        'Không thể kết nối tới địa chỉ thiết bị.',
      );
    }
  }

  Future<void> ensureDirectory(String path) async {
    if (device.transferToken.isNotEmpty) return;
    final request = http.Request('MKCOL', pathUri(path));
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 201 ||
        response.statusCode == 200 ||
        response.statusCode == 405) {
      return;
    }
    throw DeviceConnectionException(
      'Không tạo được thư mục $path (HTTP ${response.statusCode}).',
    );
  }

  Future<void> uploadFile({
    required String remotePath,
    required File file,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    final request = http.StreamedRequest('PUT', pathUri(remotePath));
    request.contentLength = total;
    request.headers['Content-Type'] = contentType;
    request.headers['X-Content-SHA256'] = digest.toString();
    if (device.transferToken.isNotEmpty) {
      request.headers['X-BizReader-Token'] = device.transferToken;
    }

    final responseFuture = _client
        .send(request)
        .timeout(const Duration(minutes: 4));
    var sent = 0;
    await request.sink.addStream(
      file.openRead().map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, total);
        return chunk;
      }),
    );
    await request.sink.close();
    final response = await responseFuture;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeviceConnectionException(
        'Tải tệp thất bại (HTTP ${response.statusCode}).',
      );
    }
  }

  Future<void> uploadBytes({
    required String remotePath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await _client
        .put(
          pathUri(remotePath),
          headers: {
            'Content-Type': contentType,
            if (device.transferToken.isNotEmpty)
              'X-BizReader-Token': device.transferToken,
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeviceConnectionException(
        'Đồng bộ thất bại (HTTP ${response.statusCode}).',
      );
    }
  }

  void close() => _client.close();
}
