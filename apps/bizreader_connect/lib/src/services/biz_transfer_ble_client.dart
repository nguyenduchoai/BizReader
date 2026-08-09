import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/biz_transfer_status.dart';

class BizTransferException implements Exception {
  const BizTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BizTransferBleClient {
  BizTransferBleClient({FlutterReactiveBle? ble}) : _injectedBle = ble;

  static final Uuid serviceUuid = Uuid.parse(
    '7d2f1000-8d4f-4f5b-a8d0-53b495a9b001',
  );
  static final Uuid commandUuid = Uuid.parse(
    '7d2f1001-8d4f-4f5b-a8d0-53b495a9b001',
  );
  static final Uuid statusUuid = Uuid.parse(
    '7d2f1002-8d4f-4f5b-a8d0-53b495a9b001',
  );

  final FlutterReactiveBle? _injectedBle;
  FlutterReactiveBle? _bleInstance;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  String? _connectedDeviceId;
  QualifiedCharacteristic? _commandCharacteristic;
  QualifiedCharacteristic? _statusCharacteristic;

  FlutterReactiveBle get _ble =>
      _injectedBle ?? (_bleInstance ??= FlutterReactiveBle());

  Future<void> ensurePermissions() async {
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (permissions.values.any((status) => status.isPermanentlyDenied)) {
      throw const BizTransferException(
        'Quyền Bluetooth đã bị tắt vĩnh viễn. Hãy bật lại trong Cài đặt Android.',
      );
    }

    final status = await _ble.statusStream
        .firstWhere(
          (value) =>
              value == BleStatus.ready ||
              value == BleStatus.unauthorized ||
              value == BleStatus.poweredOff ||
              value == BleStatus.unsupported,
        )
        .timeout(const Duration(seconds: 8), onTimeout: () => _ble.status);
    switch (status) {
      case BleStatus.ready:
        return;
      case BleStatus.poweredOff:
        throw const BizTransferException('Hãy bật Bluetooth trên điện thoại.');
      case BleStatus.unauthorized:
        throw const BizTransferException(
          'Ứng dụng chưa được cấp quyền Bluetooth.',
        );
      case BleStatus.unsupported:
        throw const BizTransferException(
          'Điện thoại này không hỗ trợ Bluetooth Low Energy.',
        );
      default:
        throw const BizTransferException('Bluetooth chưa sẵn sàng.');
    }
  }

  Stream<BizReaderBleDevice> scan() async* {
    await ensurePermissions();
    yield* _ble
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .map(
          (device) => BizReaderBleDevice(
            id: device.id,
            name: device.name.isEmpty ? 'BizReader' : device.name,
            rssi: device.rssi,
          ),
        );
  }

  Future<BizTransferStatus> connectAndStart({
    required String deviceId,
    String? ssid,
    String? password,
  }) async {
    await ensurePermissions();
    await _connect(deviceId);

    final operation = ssid == null || ssid.trim().isEmpty
        ? <String, dynamic>{'op': 'start'}
        : <String, dynamic>{
            'op': 'provision',
            'ssid': ssid.trim(),
            'password': password ?? '',
          };

    final requestId = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    operation['request'] = requestId;
    try {
      await _ble.writeCharacteristicWithResponse(
        _commandCharacteristic!,
        value: utf8.encode(jsonEncode(operation)),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      Object? lastReadError;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        try {
          final status = await _readCurrentStatus();
          lastReadError = null;
          if (status.requestId != requestId) continue;
          if (status.isError) throw BizTransferException(status.message);
          if (status.isReady) {
            if (status.ip.isEmpty || status.token.isEmpty) {
              throw const BizTransferException(
                'Thiết bị chưa trả về địa chỉ truyền sách.',
              );
            }
            return status;
          }
        } on BizTransferException {
          rethrow;
        } catch (error) {
          lastReadError = error;
        }
      }
      if (lastReadError != null) {
        throw BizTransferException('Mất phản hồi BLE: $lastReadError');
      }
      throw const BizTransferException(
        'Hết thời gian chờ BizReader kết nối Wi-Fi.',
      );
    } on BizTransferException {
      rethrow;
    } catch (error) {
      throw BizTransferException('Không trao đổi được dữ liệu BLE: $error');
    }
  }

  Future<void> stopTransfer() async {
    final characteristic = _commandCharacteristic;
    if (characteristic == null) return;
    try {
      await _ble.writeCharacteristicWithResponse(
        characteristic,
        value: utf8.encode('{"op":"stop"}'),
      );
    } catch (_) {
      // Firmware also closes an abandoned session after its idle timeout.
    }
  }

  Future<void> _connect(String deviceId) async {
    if (_connectedDeviceId == deviceId &&
        _commandCharacteristic != null &&
        _statusCharacteristic != null) {
      return;
    }

    await disconnect();
    final connected = Completer<void>();
    _connectionSubscription = _ble
        .connectToAdvertisingDevice(
          id: deviceId,
          withServices: [serviceUuid],
          prescanDuration: const Duration(seconds: 8),
          servicesWithCharacteristicsToDiscover: {
            serviceUuid: [commandUuid, statusUuid],
          },
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) {
            if (update.connectionState == DeviceConnectionState.connected) {
              _connectedDeviceId = deviceId;
              if (!connected.isCompleted) connected.complete();
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _connectedDeviceId = null;
              if (!connected.isCompleted) {
                connected.completeError(
                  const BizTransferException(
                    'Không kết nối được Bluetooth với BizReader.',
                  ),
                );
              }
            }
          },
          onError: (Object error) {
            _connectedDeviceId = null;
            if (!connected.isCompleted) {
              connected.completeError(
                BizTransferException('Lỗi kết nối Bluetooth: $error'),
              );
            }
          },
        );

    await connected.future.timeout(
      const Duration(seconds: 22),
      onTimeout: () =>
          throw const BizTransferException('Không tìm thấy BizReader ở gần.'),
    );

    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: 247);
    } catch (_) {
      // A smaller MTU still fits normal Wi-Fi credentials via GATT long writes.
    }

    _commandCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: commandUuid,
      deviceId: deviceId,
    );
    _statusCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: statusUuid,
      deviceId: deviceId,
    );
    // Reading an encrypted characteristic starts Android pairing immediately.
    final pairingDeadline = DateTime.now().add(const Duration(seconds: 20));
    Object? pairingError;
    while (DateTime.now().isBefore(pairingDeadline)) {
      try {
        await _readCurrentStatus();
        return;
      } catch (error) {
        pairingError = error;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw BizTransferException(
      'Không hoàn tất ghép đôi bảo mật: $pairingError',
    );
  }

  Future<BizTransferStatus> _readCurrentStatus() async {
    final bytes = await _ble.readCharacteristic(_statusCharacteristic!);
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Trạng thái BLE không hợp lệ');
    }
    return BizTransferStatus.fromJson(json);
  }

  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectedDeviceId = null;
    _commandCharacteristic = null;
    _statusCharacteristic = null;
  }
}
