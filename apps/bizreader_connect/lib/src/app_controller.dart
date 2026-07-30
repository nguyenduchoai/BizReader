import 'package:flutter/foundation.dart';

import 'models/device_config.dart';
import 'services/device_preferences.dart';
import 'services/webdav_device_client.dart';

enum DeviceConnectionState { unknown, checking, online, offline }

class AppController extends ChangeNotifier {
  AppController(this._preferences);

  final DevicePreferences _preferences;

  DeviceConfig device = const DeviceConfig(name: 'BizReader', host: '');
  DeviceConnectionState connectionState = DeviceConnectionState.unknown;
  String? connectionMessage;

  Future<void> load() async {
    device = await _preferences.load();
  }

  Future<bool> configure(DeviceConfig next, {bool probe = true}) async {
    connectionState = DeviceConnectionState.checking;
    connectionMessage = null;
    notifyListeners();

    if (probe) {
      final client = WebDavDeviceClient(next);
      try {
        await client.probe();
      } on DeviceConnectionException catch (error) {
        connectionState = DeviceConnectionState.offline;
        connectionMessage = error.message;
        notifyListeners();
        return false;
      } finally {
        client.close();
      }
    }

    device = next;
    await _preferences.save(device);
    connectionState = probe
        ? DeviceConnectionState.online
        : DeviceConnectionState.unknown;
    notifyListeners();
    return true;
  }

  Future<void> checkConnection() async {
    if (!device.isConfigured) {
      connectionState = DeviceConnectionState.unknown;
      notifyListeners();
      return;
    }

    connectionState = DeviceConnectionState.checking;
    connectionMessage = null;
    notifyListeners();
    final client = WebDavDeviceClient(device);
    try {
      await client.probe();
      connectionState = DeviceConnectionState.online;
    } on DeviceConnectionException catch (error) {
      connectionState = DeviceConnectionState.offline;
      connectionMessage = error.message;
    } finally {
      client.close();
      notifyListeners();
    }
  }

  Future<void> forgetDevice() async {
    await _preferences.clear();
    device = const DeviceConfig(name: 'BizReader', host: '');
    connectionState = DeviceConnectionState.unknown;
    connectionMessage = null;
    notifyListeners();
  }
}
