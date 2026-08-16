import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/biz_device_section.dart';
import '../models/device_config.dart';

class DevicePreferences {
  static const _nameKey = 'device_name';
  static const _hostKey = 'device_host';
  static const _bleIdKey = 'device_ble_id';
  static const _deviceStateKey = 'device_state_v1';

  Future<DeviceConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    return DeviceConfig(
      name: preferences.getString(_nameKey) ?? 'BizReader',
      host: preferences.getString(_hostKey) ?? '',
      bleId: preferences.getString(_bleIdKey) ?? '',
    );
  }

  Future<void> save(DeviceConfig device) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nameKey, device.name);
    await preferences.setString(_hostKey, device.host);
    await preferences.setString(_bleIdKey, device.bleId);
  }

  Future<BizDeviceState> loadDeviceState() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_deviceStateKey);
    if (value == null || value.isEmpty) return const BizDeviceState();
    try {
      return BizDeviceState.fromJson(
        (jsonDecode(value) as Map).cast<String, Object?>(),
      );
    } on Object {
      return const BizDeviceState();
    }
  }

  Future<void> saveDeviceState(BizDeviceState state) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_deviceStateKey, jsonEncode(state.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_nameKey);
    await preferences.remove(_hostKey);
    await preferences.remove(_bleIdKey);
    await preferences.remove(_deviceStateKey);
  }
}
