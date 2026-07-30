class DeviceConfig {
  const DeviceConfig({required this.name, required this.host});

  final String name;
  final String host;

  bool get isConfigured => host.trim().isNotEmpty;

  Uri get baseUri {
    var value = host.trim();
    if (!value.contains('://')) {
      value = 'http://$value';
    }
    final uri = Uri.parse(value);
    return uri.replace(path: '', query: null, fragment: null);
  }

  DeviceConfig copyWith({String? name, String? host}) {
    return DeviceConfig(name: name ?? this.name, host: host ?? this.host);
  }
}
