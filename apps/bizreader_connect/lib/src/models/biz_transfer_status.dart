class BizTransferStatus {
  const BizTransferStatus({
    required this.state,
    required this.message,
    this.requestId = '',
    this.deviceName = 'BizReader',
    this.ip = '',
    this.token = '',
    this.port = 80,
    this.received = 0,
    this.total = 0,
    this.filename = '',
    this.sha256 = '',
  });

  factory BizTransferStatus.fromJson(Map<String, dynamic> json) {
    return BizTransferStatus(
      state: json['state'] as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
      requestId: json['request'] as String? ?? '',
      deviceName: json['device'] as String? ?? 'BizReader',
      ip: json['ip'] as String? ?? '',
      token: json['token'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 80,
      received: (json['received'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      filename: json['filename'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
    );
  }

  final String state;
  final String message;
  final String requestId;
  final String deviceName;
  final String ip;
  final String token;
  final int port;
  final int received;
  final int total;
  final String filename;
  final String sha256;

  bool get isReady => state == 'ready' || state == 'complete';
  bool get isError => state == 'error';
}

class BizReaderBleDevice {
  const BizReaderBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}
