import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/biz_transfer_status.dart';
import '../models/biz_sync_snapshot.dart';
import '../models/biz_content.dart';
import '../models/biz_device_section.dart';
import 'ble_sync_codec.dart';

class BizTransferException implements Exception {
  const BizTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Máy đọc không phản hồi lệnh quét Wi-Fi trong thời hạn: firmware cũ chưa
/// hỗ trợ `wifi_scan`, hoặc quét quá hạn. UI nên quay về nhập SSID thủ công.
class BizWifiScanUnsupportedException extends BizTransferException {
  const BizWifiScanUnsupportedException()
    : super(
        'Máy đọc chưa hỗ trợ quét Wi-Fi (firmware cũ) hoặc không phản hồi.',
      );
}

class BizTransferBleClient {
  BizTransferBleClient({FlutterReactiveBle? ble}) : _injectedBle = ble;

  static const _maxContentBytes = 32 * 1024;
  static const _maxSnapshotBytes = 48 * 1024;

  static final Uuid serviceUuid = Uuid.parse(
    '7d2f1000-8d4f-4f5b-a8d0-53b495a9b001',
  );
  static final Uuid commandUuid = Uuid.parse(
    '7d2f1001-8d4f-4f5b-a8d0-53b495a9b001',
  );
  static final Uuid statusUuid = Uuid.parse(
    '7d2f1002-8d4f-4f5b-a8d0-53b495a9b001',
  );
  static final Uuid syncRxUuid = Uuid.parse(
    '7d2f1004-8d4f-4f5b-a8d0-53b495a9b001',
  );
  static final Uuid syncTxUuid = Uuid.parse(
    '7d2f1005-8d4f-4f5b-a8d0-53b495a9b001',
  );

  final FlutterReactiveBle? _injectedBle;
  FlutterReactiveBle? _bleInstance;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  String? _connectedDeviceId;
  QualifiedCharacteristic? _commandCharacteristic;
  QualifiedCharacteristic? _statusCharacteristic;
  QualifiedCharacteristic? _syncRxCharacteristic;
  QualifiedCharacteristic? _syncTxCharacteristic;
  int _mtu = 23;

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

  Future<BizTransferStatus> connectAndStart({required String deviceId}) async {
    await ensurePermissions();
    try {
      await _connect(deviceId);
      // 'now' lets firmware adopt the phone clock (ms since epoch) when its
      // own clock is unset; older firmware ignores unknown fields.
      final operation = <String, dynamic>{
        'op': 'start',
        'now': DateTime.now().millisecondsSinceEpoch,
      };
      final requestId = Random.secure().nextInt(0x7fffffff).toRadixString(16);
      operation['request'] = requestId;
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
      await disconnect();
      rethrow;
    } catch (error) {
      await disconnect();
      throw BizTransferException('Không trao đổi được dữ liệu BLE: $error');
    }
  }

  Future<void> stopTransfer() async {
    final characteristic = _commandCharacteristic;
    try {
      if (characteristic != null) {
        await _ble.writeCharacteristicWithResponse(
          characteristic,
          value: utf8.encode('{"op":"stop"}'),
        );
      }
    } catch (_) {
      // Firmware also closes an abandoned session after its idle timeout.
    } finally {
      await disconnect();
    }
  }

  Future<BizSyncSnapshot> synchronize({
    required String deviceId,
    required BizSyncSnapshot local,
  }) async {
    await ensurePermissions();
    try {
      await _connect(deviceId);
      final remote = await _pullSnapshot();
      final merged = BizSyncSnapshot(
        content: BizContent.merge(local.content, remote.content),
        progress: BizSyncSnapshot.mergeProgress(
          local.progress,
          remote.progress,
        ),
        // Cấu hình máy do app quyết định (last edit wins): phủ các key đã sửa
        // lên settings vừa pull để không ghi đè key lạ hoặc thay đổi
        // thực hiện trực tiếp trên máy. Null khi không có gì chờ -> bỏ khỏi push.
        device: BizDeviceSection.mergeForPush(local.device, remote.device),
      );
      return await _pushSnapshot(merged);
    } on BizTransferException {
      rethrow;
    } on Object catch (error) {
      throw BizTransferException('Không đồng bộ được qua BLE: $error');
    } finally {
      await disconnect();
    }
  }

  /// Yêu cầu máy đọc quét Wi-Fi xung quanh rồi trả danh sách kết quả.
  ///
  /// Ghi op `wifi_scan` lên characteristic lệnh, poll status tới khi field
  /// `scan` xuất hiện (quét xong), rồi pull snapshot bằng đường `sync_pull`
  /// sẵn có để lấy `device.wifiScan`. Hết [timeout] mà `scan` chưa xuất hiện
  /// (firmware cũ bỏ qua op lạ) thì ném [BizWifiScanUnsupportedException].
  Future<List<BizWifiScanResult>> scanDeviceWifi({
    required String deviceId,
    Duration timeout = const Duration(seconds: 12),
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    await ensurePermissions();
    try {
      await _connect(deviceId);
      final requestId = Random.secure().nextInt(0x7fffffff).toRadixString(16);
      await _ble.writeCharacteristicWithResponse(
        _commandCharacteristic!,
        value: utf8.encode(
          jsonEncode({
            'op': 'wifi_scan',
            'request': requestId,
            'now': DateTime.now().millisecondsSinceEpoch,
          }),
        ),
      );
      final deadline = DateTime.now().add(timeout);
      var completed = false;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(pollInterval);
        final status = await _readCurrentStatus();
        if (status.requestId != requestId) continue;
        if (status.isError) throw BizTransferException(status.message);
        if (status.scanCount != null) {
          completed = true;
          break;
        }
      }
      if (!completed) throw const BizWifiScanUnsupportedException();
      final snapshot = await _pullSnapshot();
      return snapshot.device?.wifiScan ?? const [];
    } on BizTransferException {
      rethrow;
    } on Object catch (error) {
      throw BizTransferException('Không quét được Wi-Fi qua BLE: $error');
    } finally {
      await disconnect();
    }
  }

  Future<BizSyncSnapshot> _pullSnapshot() async {
    final frameSize = min(240, max(20, _mtu - 3));
    final status = await _writeCommandAndWait(
      'sync_pull',
      extra: {'frameSize': frameSize},
      acceptedState: 'sync_ready',
    );
    return _readSnapshot(status);
  }

  Future<BizSyncSnapshot> _pushSnapshot(BizSyncSnapshot snapshot) async {
    final contentBytes = utf8.encode(jsonEncode(snapshot.content.toJson()));
    if (contentBytes.length > _maxContentBytes) {
      throw const BizTransferException(
        'Ghi chú và công việc vượt giới hạn đồng bộ 32 KiB. '
        'Hãy rút gọn hoặc xóa bớt nội dung.',
      );
    }
    final bytes = utf8.encode(jsonEncode(snapshot.toJson()));
    if (bytes.length > _maxSnapshotBytes) {
      throw const BizTransferException(
        'Dữ liệu đồng bộ vượt giới hạn 48 KiB của BizReader.',
      );
    }
    final payloadSize = min(236, max(16, _mtu - 7));
    final frames = encodeBleSyncFrames(bytes, payloadSize);
    await _writeCommandAndWait(
      'sync_begin',
      extra: {'size': bytes.length, 'chunks': frames.length},
      acceptedState: 'sync_receiving',
    );
    for (final frame in frames) {
      await _ble.writeCharacteristicWithResponse(
        _syncRxCharacteristic!,
        value: frame,
      );
    }
    final status = await _writeCommandAndWait(
      'sync_commit',
      acceptedState: 'sync_ready',
    );
    return _readSnapshot(status);
  }

  Future<BizSyncSnapshot> _readSnapshot(BizTransferStatus status) async {
    if (status.syncChunks < 1 || status.syncSize < 1) {
      throw const BizTransferException('Thiết bị không trả snapshot BLE.');
    }
    final frames = <List<int>>[];
    for (var index = 0; index < status.syncChunks; index++) {
      frames.add(await _ble.readCharacteristic(_syncTxCharacteristic!));
    }
    final bytes = decodeBleSyncFrames(frames);
    if (bytes.length != status.syncSize) {
      throw const BizTransferException('Kích thước snapshot BLE không khớp.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const BizTransferException('Snapshot BLE không hợp lệ.');
    }
    return BizSyncSnapshot.fromJson(decoded.cast<String, Object?>());
  }

  Future<BizTransferStatus> _writeCommandAndWait(
    String operation, {
    Map<String, Object?> extra = const {},
    required String acceptedState,
  }) async {
    final requestId = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    await _ble.writeCharacteristicWithResponse(
      _commandCharacteristic!,
      value: utf8.encode(
        jsonEncode({
          'op': operation,
          'request': requestId,
          // Phone clock for firmware progress timestamps; older firmware
          // ignores unknown fields.
          'now': DateTime.now().millisecondsSinceEpoch,
          ...extra,
        }),
      ),
    );
    // Committing can rewrite up to 100 progress files on a slow SD card, so
    // sync_commit gets a longer deadline than the quick control commands.
    final deadline = DateTime.now().add(
      operation == 'sync_commit'
          ? const Duration(seconds: 30)
          : const Duration(seconds: 15),
    );
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final status = await _readCurrentStatus();
      if (status.requestId != requestId) continue;
      if (status.isError) throw BizTransferException(status.message);
      if (status.state == acceptedState) return status;
    }
    throw const BizTransferException('Hết thời gian chờ đồng bộ BLE.');
  }

  Future<void> _connect(String deviceId) async {
    if (_connectedDeviceId == deviceId &&
        _commandCharacteristic != null &&
        _statusCharacteristic != null &&
        _syncRxCharacteristic != null &&
        _syncTxCharacteristic != null) {
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
            serviceUuid: [commandUuid, statusUuid, syncRxUuid, syncTxUuid],
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
      onTimeout: () => throw const BizTransferException(
        'Không tìm thấy BizReader. Hãy mở Truyền tệp > Kết nối App trên máy đọc.',
      ),
    );

    try {
      _mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 247);
    } catch (_) {
      // Status reads still work through standard GATT long-read behavior.
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
    _syncRxCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: syncRxUuid,
      deviceId: deviceId,
    );
    _syncTxCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: syncTxUuid,
      deviceId: deviceId,
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
    _syncRxCharacteristic = null;
    _syncTxCharacteristic = null;
    _mtu = 23;
  }
}
