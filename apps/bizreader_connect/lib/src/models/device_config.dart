class DeviceConfig {
  const DeviceConfig({
    required this.name,
    required this.host,
    this.bleId = '',
    this.transferToken = '',
  });

  final String name;
  final String host;
  final String bleId;
  final String transferToken;

  bool get isConfigured => host.trim().isNotEmpty || bleId.trim().isNotEmpty;
  bool get usesBizTransfer => bleId.isNotEmpty;

  Uri get baseUri {
    var value = host.trim();
    if (!value.contains('://')) {
      value = 'http://$value';
    }
    final uri = Uri.parse(value);
    return uri.replace(path: '', query: null, fragment: null);
  }

  DeviceConfig copyWith({
    String? name,
    String? host,
    String? bleId,
    String? transferToken,
  }) {
    return DeviceConfig(
      name: name ?? this.name,
      host: host ?? this.host,
      bleId: bleId ?? this.bleId,
      transferToken: transferToken ?? this.transferToken,
    );
  }
}
