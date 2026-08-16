import 'dart:convert';

import 'package:bizreader_connect/src/models/biz_content.dart';
import 'package:bizreader_connect/src/models/biz_device_section.dart';
import 'package:bizreader_connect/src/services/ble_sync_codec.dart';
import 'package:bizreader_connect/src/services/biz_transfer_ble_client.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses wifiScan preserving order, rssi and sec', () {
    final device = BizDeviceSection.fromJson({
      'settings': {'fontSize': 1},
      'wifiSsids': ['NhaRieng'],
      'wifiScan': [
        {'ssid': 'NhaRieng', 'rssi': -48, 'sec': true},
        {'ssid': 'VanPhong', 'rssi': -66, 'sec': 1},
        {'ssid': 'CafeSach', 'rssi': -82, 'sec': false},
        {'rssi': -90}, // thiếu ssid -> loại bỏ
      ],
    });

    expect(device.wifiScan.map((n) => n.ssid), [
      'NhaRieng',
      'VanPhong',
      'CafeSach',
    ]);
    expect(device.wifiScan.first.rssi, -48);
    expect(device.wifiScan.first.secured, isTrue);
    expect(device.wifiScan[1].secured, isTrue); // sec dạng số cũng hiểu được
    expect(device.wifiScan.last.secured, isFalse);
  });

  test('wifiScan absent -> empty list, and never pushed back', () {
    final withoutScan = BizDeviceSection.fromJson({
      'settings': {'fontSize': 1},
      'wifiSsids': <Object?>[],
    });
    expect(withoutScan.wifiScan, isEmpty);

    // Kết quả quét chỉ có chiều pull: không tạo payload push, không vào JSON.
    const holdingScan = BizDeviceSection(
      wifiScan: [BizWifiScanResult(ssid: 'NhaRieng', rssi: -48)],
    );
    expect(holdingScan.hasPushPayload, isFalse);
    expect(holdingScan.toJson(), isEmpty);
  });

  test('scan flow: status without `scan` times out as unsupported', () async {
    final ble = _FakeReactiveBle(scanCompletes: false);
    final client = _TestScanClient(ble);

    await expectLater(
      client.scanDeviceWifi(
        deviceId: 'reader',
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 40),
      ),
      throwsA(isA<BizWifiScanUnsupportedException>()),
    );
    // Không hỗ trợ thì không được kéo snapshot.
    expect(ble.commands.map((c) => c['op']), ['wifi_scan']);
  });

  test('scan flow: `scan` in status -> pulls and parses the list', () async {
    final ble = _FakeReactiveBle(scanCompletes: true);
    final client = _TestScanClient(ble);

    final results = await client.scanDeviceWifi(
      deviceId: 'reader',
      timeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 10),
    );

    expect(results.map((n) => n.ssid), ['NhaRieng', 'CafeSach']);
    expect(results.first.rssi, -50);
    expect(results.first.secured, isTrue);
    expect(results.last.secured, isFalse);

    // Đúng hợp đồng lệnh: op + request + now, rồi mới sync_pull.
    final scanCommand = ble.commands.first;
    expect(scanCommand['op'], 'wifi_scan');
    expect(scanCommand['request'], isA<String>());
    expect(scanCommand['now'], isA<num>());
    expect(ble.commands.map((c) => c['op']), ['wifi_scan', 'sync_pull']);
  });
}

class _TestScanClient extends BizTransferBleClient {
  _TestScanClient(FlutterReactiveBle ble) : super(ble: ble);

  // Bỏ qua permission_handler (kênh nền tảng không có trong test).
  @override
  Future<void> ensurePermissions() async {}
}

/// Giả lập firmware ở tầng BLE: echo `request`, thêm field `scan` vào status
/// sau lần poll thứ hai (khi [scanCompletes]), và phục vụ sync_pull bằng
/// snapshot có `device.wifiScan`.
class _FakeReactiveBle implements FlutterReactiveBle {
  _FakeReactiveBle({required this.scanCompletes});

  final bool scanCompletes;
  final List<Map<String, Object?>> commands = [];
  int _scanPolls = 0;
  List<int> _snapshotBytes = const [];
  final List<List<int>> _txFrames = [];

  Map<String, Object?> get _lastCommand =>
      commands.isEmpty ? const {} : commands.last;

  @override
  Stream<ConnectionStateUpdate> connectToAdvertisingDevice({
    required String id,
    required List<Uuid> withServices,
    required Duration prescanDuration,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) => Stream.value(
    ConnectionStateUpdate(
      deviceId: id,
      connectionState: DeviceConnectionState.connected,
      failure: null,
    ),
  );

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async =>
      mtu;

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async {
    if (characteristic.characteristicId != BizTransferBleClient.commandUuid) {
      return;
    }
    final command = (jsonDecode(utf8.decode(value)) as Map)
        .cast<String, Object?>();
    commands.add(command);
    if (command['op'] == 'sync_pull') {
      _snapshotBytes = utf8.encode(
        jsonEncode({
          'protocol': 2,
          'content': const BizContent().toJson(),
          'progress': <Object?>[],
          'device': {
            'settings': {'fontSize': 1},
            'wifiSsids': ['NhaRieng'],
            'wifiScan': [
              {'ssid': 'NhaRieng', 'rssi': -50, 'sec': true},
              {'ssid': 'CafeSach', 'rssi': -80, 'sec': false},
            ],
          },
        }),
      );
      _txFrames
        ..clear()
        ..addAll(encodeBleSyncFrames(_snapshotBytes, 200));
    }
  }

  @override
  Future<List<int>> readCharacteristic(
    QualifiedCharacteristic characteristic,
  ) async {
    if (characteristic.characteristicId == BizTransferBleClient.syncTxUuid) {
      return _txFrames.removeAt(0);
    }
    if (characteristic.characteristicId != BizTransferBleClient.statusUuid) {
      throw StateError('đọc characteristic không mong đợi');
    }
    final request = _lastCommand['request'];
    switch (_lastCommand['op']) {
      case 'wifi_scan':
        _scanPolls++;
        return utf8.encode(
          jsonEncode({
            'state': 'ready',
            'message': '',
            'request': request,
            if (scanCompletes && _scanPolls >= 2) 'scan': 2,
          }),
        );
      case 'sync_pull':
        return utf8.encode(
          jsonEncode({
            'state': 'sync_ready',
            'message': '',
            'request': request,
            'syncChunks': _txFrames.length,
            'syncSize': _snapshotBytes.length,
          }),
        );
      default:
        return utf8.encode('{"state":"ready","message":""}');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeReactiveBle: ${invocation.memberName}');
}
