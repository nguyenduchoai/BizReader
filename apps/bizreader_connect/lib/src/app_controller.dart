import 'package:flutter/foundation.dart';

import 'models/biz_transfer_status.dart';
import 'models/device_config.dart';
import 'services/biz_transfer_ble_client.dart';
import 'services/device_preferences.dart';
import 'services/webdav_device_client.dart';

enum DeviceConnectionState { unknown, checking, online, offline }

class AppController extends ChangeNotifier {
  AppController(this._preferences, {BizTransferBleClient? bleClient})
    : _bleClient = bleClient ?? BizTransferBleClient();

  final DevicePreferences _preferences;
  final BizTransferBleClient _bleClient;

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

  Stream<BizReaderBleDevice> scanBizReaders() => _bleClient.scan();

  Future<bool> pairDevice(
    BizReaderBleDevice discovered, {
    String? ssid,
    String? password,
  }) async {
    connectionState = DeviceConnectionState.checking;
    connectionMessage = 'Đang kết nối Bluetooth';
    notifyListeners();
    try {
      final status = await _bleClient.connectAndStart(
        deviceId: discovered.id,
        ssid: ssid,
        password: password,
      );
      device = DeviceConfig(
        name: status.deviceName.isEmpty ? discovered.name : status.deviceName,
        host: 'http://${status.ip}:${status.port}',
        bleId: discovered.id,
        transferToken: status.token,
      );
      await _preferences.save(device);
      connectionState = DeviceConnectionState.online;
      connectionMessage = status.message;
      notifyListeners();
      return true;
    } on BizTransferException catch (error) {
      connectionState = DeviceConnectionState.offline;
      connectionMessage = error.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<DeviceConfig> prepareTransfer() async {
    if (device.bleId.isEmpty) {
      if (!device.isConfigured) {
        throw const DeviceConnectionException('Chưa cấu hình BizReader.');
      }
      return device;
    }

    connectionState = DeviceConnectionState.checking;
    connectionMessage = 'Đang mở kết nối truyền sách';
    notifyListeners();
    try {
      final status = await _bleClient.connectAndStart(deviceId: device.bleId);
      device = device.copyWith(
        name: status.deviceName,
        host: 'http://${status.ip}:${status.port}',
        transferToken: status.token,
      );
      await _preferences.save(device);
      connectionState = DeviceConnectionState.online;
      connectionMessage = status.message;
      notifyListeners();
      return device;
    } on BizTransferException catch (error) {
      connectionState = DeviceConnectionState.offline;
      connectionMessage = error.message;
      notifyListeners();
      throw DeviceConnectionException(error.message);
    }
  }

  Future<void> finishTransfer() => _bleClient.stopTransfer();

  Future<void> checkConnection() async {
    if (!device.isConfigured) {
      connectionState = DeviceConnectionState.unknown;
      notifyListeners();
      return;
    }

    if (device.usesBizTransfer && device.transferToken.isEmpty) {
      connectionState = DeviceConnectionState.unknown;
      connectionMessage = 'Sẽ kết nối tự động khi gửi sách.';
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
    await _bleClient.disconnect();
    await _preferences.clear();
    device = const DeviceConfig(name: 'BizReader', host: '');
    connectionState = DeviceConnectionState.unknown;
    connectionMessage = null;
    notifyListeners();
  }
}
