import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_config.dart';

class DevicePreferences {
  static const _nameKey = 'device_name';
  static const _hostKey = 'device_host';

  Future<DeviceConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    return DeviceConfig(
      name: preferences.getString(_nameKey) ?? 'BizReader',
      host: preferences.getString(_hostKey) ?? '',
    );
  }

  Future<void> save(DeviceConfig device) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nameKey, device.name);
    await preferences.setString(_hostKey, device.host);
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_nameKey);
    await preferences.remove(_hostKey);
  }
}
