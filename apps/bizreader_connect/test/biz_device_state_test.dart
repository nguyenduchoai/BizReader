import 'dart:async';
import 'dart:io';

import 'package:bizreader_connect/src/app_controller.dart';
import 'package:bizreader_connect/src/models/biz_content.dart';
import 'package:bizreader_connect/src/models/biz_device_section.dart';
import 'package:bizreader_connect/src/models/biz_sync_snapshot.dart';
import 'package:bizreader_connect/src/models/device_config.dart';
import 'package:bizreader_connect/src/models/local_book.dart';
import 'package:bizreader_connect/src/services/biz_transfer_ble_client.dart';
import 'package:bizreader_connect/src/services/book_library_service.dart';
import 'package:bizreader_connect/src/services/device_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('parses the device section from a pull snapshot', () {
    final snapshot = BizSyncSnapshot.fromJson({
      'protocol': 2,
      'content': const BizContent().toJson(),
      'progress': <Object?>[],
      'device': {
        'settings': {'fontSize': 1, 'language': 'VI', 'mysteryKey': 7},
        'wifiSsids': ['NhaRieng', 'VanPhong'],
      },
    });

    final device = snapshot.device!;
    expect(device.settingInt('fontSize'), 1);
    expect(device.settingString('language'), 'VI');
    // Key lạ được giữ nguyên (passthrough).
    expect(device.settings['mysteryKey'], 7);
    expect(device.wifiSsids, ['NhaRieng', 'VanPhong']);
  });

  test('omits the device section when there is nothing to push', () {
    const withoutDevice = BizSyncSnapshot(content: BizContent(), progress: []);
    const withEmptyDevice = BizSyncSnapshot(
      content: BizContent(),
      progress: [],
      device: BizDeviceSection(),
    );

    expect(withoutDevice.toJson().containsKey('device'), isFalse);
    expect(withEmptyDevice.toJson().containsKey('device'), isFalse);
  });

  test('serializes the push shape with the exact contract keys', () {
    const snapshot = BizSyncSnapshot(
      content: BizContent(),
      progress: [],
      device: BizDeviceSection(
        settings: {'fontSize': 2, 'mysteryKey': 7},
        wifiAdd: [BizWifiCredential(ssid: 'VanPhong', password: 'matkhau123')],
        wifiRemove: ['MangCu'],
      ),
    );

    final device = snapshot.toJson()['device'] as Map;
    expect(device.keys.toSet(), {'settings', 'wifiAdd', 'wifiRemove'});
    expect(device['settings'], {'fontSize': 2, 'mysteryKey': 7});
    expect(device['wifiAdd'], [
      {'ssid': 'VanPhong', 'password': 'matkhau123'},
    ]);
    expect(device['wifiRemove'], ['MangCu']);
  });

  test('mergeForPush overlays edits onto the freshly pulled settings', () {
    const pending = BizDeviceSection(settings: {'fontSize': 3});
    const remote = BizDeviceSection(
      settings: {'fontSize': 1, 'uiTheme': 2, 'mysteryKey': 'x'},
    );

    final merged = BizDeviceSection.mergeForPush(pending, remote)!;

    expect(merged.settings, {'fontSize': 3, 'uiTheme': 2, 'mysteryKey': 'x'});
    expect(
      BizDeviceSection.mergeForPush(const BizDeviceSection(), remote),
      isNull,
    );
    expect(BizDeviceSection.mergeForPush(null, remote), isNull);
  });

  test('reconcile clears confirmed wifi adds and removals', () {
    const state = BizDeviceState(
      wifiSsids: ['Z', 'W'],
      pendingWifiAdd: [
        BizWifiCredential(ssid: 'X', password: 'matkhau123'),
        BizWifiCredential(ssid: 'Y', password: 'matkhau456'),
      ],
      pendingWifiRemove: ['Z', 'W'],
    );
    // Echo: X đã được thêm, W đã bị xóa; Y chưa vào máy, Z vẫn còn.
    const echo = BizDeviceSection(wifiSsids: ['X', 'Z']);

    final next = state.reconcile(echo);

    expect(next.pendingWifiAdd.map((c) => c.ssid), ['Y']);
    expect(next.pendingWifiRemove, ['Z']);
    expect(next.wifiSsids, ['X', 'Z']);
  });

  test('reconcile moves a rejected pushed add to the failed list', () {
    const state = BizDeviceState(
      pendingWifiAdd: [
        BizWifiCredential(ssid: 'X', password: 'matkhau123'),
        BizWifiCredential(ssid: 'Y', password: 'matkhau456'),
        BizWifiCredential(ssid: 'Z', password: 'matkhau789'),
      ],
    );
    // Push X+Y; máy nhận X, từ chối Y; Z mới xếp hàng trong lúc đồng bộ.
    const echo = BizDeviceSection(wifiSsids: ['X']);

    final next = state.reconcile(echo, pushedWifiAdds: {'X', 'Y'});

    expect(next.pendingWifiAdd.map((c) => c.ssid), ['Z']);
    expect(next.failedWifiAdds.single.ssid, 'Y');
    expect(next.failedWifiAdds.single.password, 'matkhau456');
  });

  test('reconcile drops a failed add that later shows up on the device', () {
    const state = BizDeviceState(
      failedWifiAdds: [BizWifiCredential(ssid: 'Y', password: 'matkhau456')],
    );
    const echo = BizDeviceSection(wifiSsids: ['Y']);

    expect(state.reconcile(echo).failedWifiAdds, isEmpty);
  });

  test('reconcile adopts echo settings as base and clears pushed edits', () {
    const state = BizDeviceState(
      settings: {'fontSize': 1},
      pendingSettings: {'fontSize': 3},
    );
    const echo = BizDeviceSection(
      settings: {'fontSize': 3, 'uiTheme': 2, 'mysteryKey': 'x'},
      wifiSsids: [],
    );

    final next = state.reconcile(echo, pushedSettings: {'fontSize': 3});

    expect(next.settings, {'fontSize': 3, 'uiTheme': 2, 'mysteryKey': 'x'});
    expect(next.pendingSettings, isEmpty);
    expect(next.hasPendingChanges, isFalse);
  });

  test('reconcile keeps an edit made while the sync was in flight', () {
    // Đã push fontSize=3, nhưng người dùng sửa tiếp thành 2 khi đang đồng bộ.
    const state = BizDeviceState(
      settings: {'fontSize': 1},
      pendingSettings: {'fontSize': 2, 'uiTheme': 1},
    );
    const echo = BizDeviceSection(settings: {'fontSize': 3, 'uiTheme': 1});

    final next = state.reconcile(
      echo,
      pushedSettings: {'fontSize': 3, 'uiTheme': 1},
    );

    expect(next.pendingSettings, {'fontSize': 2});
    expect(next.settings['fontSize'], 3);
  });

  test('device state survives a local storage roundtrip', () {
    const state = BizDeviceState(
      settings: {'fontSize': 1, 'language': 'VI'},
      wifiSsids: ['NhaRieng'],
      pendingSettings: {'uiTheme': 2},
      pendingWifiAdd: [BizWifiCredential(ssid: 'X', password: 'matkhau123')],
      pendingWifiRemove: ['NhaRieng'],
      failedWifiAdds: [BizWifiCredential(ssid: 'F', password: 'matkhau999')],
    );

    final restored = BizDeviceState.fromJson(state.toJson());

    expect(restored.settings, state.settings);
    expect(restored.wifiSsids, state.wifiSsids);
    expect(restored.pendingSettings, state.pendingSettings);
    expect(restored.pendingWifiAdd.single.ssid, 'X');
    expect(restored.pendingWifiAdd.single.password, 'matkhau123');
    expect(restored.pendingWifiRemove, state.pendingWifiRemove);
    expect(restored.failedWifiAdds.single.ssid, 'F');
    expect(restored.failedWifiAdds.single.password, 'matkhau999');
  });

  test('sync pushes pending device config and reconciles the echo', () async {
    SharedPreferences.setMockInitialValues({});
    final ble = _DeviceEchoBleClient();
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: _EmptyBookLibrary(),
      bleClient: ble,
    );
    await controller.load();
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );
    await controller.setDeviceSetting('fontSize', 2);
    await controller.queueWifiAdd('VanPhong', 'matkhau123');

    await controller.syncContentToDevice();

    final sent = ble.sent!.device!;
    expect(sent.settings, {'fontSize': 2});
    expect(sent.wifiAdd.single.ssid, 'VanPhong');
    expect(sent.wifiAdd.single.password, 'matkhau123');

    expect(controller.deviceState.pendingSettings, isEmpty);
    expect(controller.deviceState.pendingWifiAdd, isEmpty);
    expect(controller.deviceState.settings['fontSize'], 2);
    expect(controller.deviceState.settings['mysteryKey'], 'x');
    expect(controller.deviceState.wifiSsids, ['NhaRieng', 'VanPhong']);

    // Hàng đợi và bản gốc mới phải được lưu bền.
    final persisted = await DevicePreferences().loadDeviceState();
    expect(persisted.pendingWifiAdd, isEmpty);
    expect(persisted.settings['fontSize'], 2);
  });

  test('sync omits the device object when nothing is pending', () async {
    SharedPreferences.setMockInitialValues({});
    final ble = _DeviceEchoBleClient();
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: _EmptyBookLibrary(),
      bleClient: ble,
    );
    await controller.load();
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );

    await controller.syncContentToDevice();

    expect(ble.sent!.device, isNull);
    // Echo vẫn cập nhật bản gốc để màn hình cài đặt dùng được ngoại tuyến.
    expect(controller.deviceState.settings['fontSize'], 2);
  });

  test('an old-firmware echo without device keeps the queue intact', () async {
    SharedPreferences.setMockInitialValues({});
    final ble = _NoDeviceBleClient();
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: _EmptyBookLibrary(),
      bleClient: ble,
    );
    await controller.load();
    await controller.queueWifiAdd('VanPhong', 'matkhau123');
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );

    await controller.syncContentToDevice();

    expect(controller.deviceState.pendingWifiAdd.single.ssid, 'VanPhong');
  });

  test('sync marks a rejected wifi add as failed, not re-pushed', () async {
    SharedPreferences.setMockInitialValues({});
    final ble = _RejectingWifiBleClient();
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: _EmptyBookLibrary(),
      bleClient: ble,
    );
    await controller.load();
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );
    await controller.queueWifiAdd('VanPhong', 'matkhau123');

    await controller.syncContentToDevice();

    expect(controller.deviceState.pendingWifiAdd, isEmpty);
    expect(controller.deviceState.failedWifiAdds.single.ssid, 'VanPhong');
    // Danh sách từ chối phải sống sót qua khởi động lại app.
    final persisted = await DevicePreferences().loadDeviceState();
    expect(persisted.failedWifiAdds.single.ssid, 'VanPhong');

    // Không tự push lại: lần đồng bộ sau không gửi `device`.
    await controller.syncContentToDevice();
    expect(ble.sent!.device, isNull);

    // "Thử lại" đưa về hàng đợi với đúng mật khẩu cũ.
    await controller.retryWifiAdd('VanPhong');
    expect(controller.deviceState.failedWifiAdds, isEmpty);
    expect(controller.deviceState.pendingWifiAdd.single.password, 'matkhau123');
  });

  test('a remove queued while its add is in flight still runs', () async {
    SharedPreferences.setMockInitialValues({});
    final ble = _GatedEchoBleClient();
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: _EmptyBookLibrary(),
      bleClient: ble,
    );
    await controller.load();
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );
    await controller.queueWifiAdd('X', 'matkhau123');

    final gate = ble.gate = Completer<void>();
    final sync = controller.syncContentToDevice();
    while (ble.sent == null) {
      await Future<void>.delayed(Duration.zero);
    }
    // Người dùng đổi ý trong lúc lệnh thêm đang bay.
    await controller.queueWifiRemove('X');
    gate.complete();
    ble.gate = null;
    await sync;

    // Máy đã kịp thêm X; lệnh xóa phải sống sót qua reconcile.
    expect(controller.deviceState.wifiSsids, contains('X'));
    expect(controller.deviceState.pendingWifiAdd, isEmpty);
    expect(controller.deviceState.pendingWifiRemove, ['X']);

    await controller.syncContentToDevice();
    expect(ble.sent!.device!.wifiRemove, ['X']);
    expect(controller.deviceState.wifiSsids, isNot(contains('X')));
    expect(controller.deviceState.pendingWifiRemove, isEmpty);
  });

  test('sync and scan refuse to start while BLE is busy', () async {
    SharedPreferences.setMockInitialValues({});
    final ble = _GatedEchoBleClient();
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: _EmptyBookLibrary(),
      bleClient: ble,
    );
    await controller.load();
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );

    final gate = ble.gate = Completer<void>();
    final sync = controller.syncContentToDevice();
    await expectLater(
      controller.syncContentToDevice(),
      throwsA(isA<BizTransferException>()),
    );
    await expectLater(
      controller.scanDeviceWifi(),
      throwsA(isA<BizTransferException>()),
    );
    gate.complete();
    ble.gate = null;
    await sync;

    // Phiên truyền sách đang mở cũng chặn đồng bộ và quét.
    controller.transferSessionActive = true;
    await expectLater(
      controller.syncContentToDevice(),
      throwsA(isA<BizTransferException>()),
    );
    await expectLater(
      controller.scanDeviceWifi(),
      throwsA(isA<BizTransferException>()),
    );
    controller.transferSessionActive = false;
  });

  test('demo mode edits never touch the real device queue', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: _EmptyBookLibrary(),
      bleClient: _DeviceEchoBleClient(),
    );
    await controller.load();
    await controller.setDeviceSetting('fontSize', 2);

    controller.enterDemoMode();
    // Bản demo có dữ liệu riêng để màn hình cài đặt trình diễn được.
    expect(controller.deviceState.settings, isNotEmpty);
    await controller.queueWifiAdd('DemoNet', 'matkhau123');
    await controller.setDeviceSetting('uiTheme', 3);

    await controller.exitDemoMode();

    expect(controller.deviceState.pendingWifiAdd, isEmpty);
    expect(controller.deviceState.pendingSettings, {'fontSize': 2});
    // Hàng đợi demo cũng không được lưu bền.
    final persisted = await DevicePreferences().loadDeviceState();
    expect(persisted.pendingWifiAdd, isEmpty);
    expect(persisted.pendingSettings, {'fontSize': 2});
  });
}

class _EmptyBookLibrary extends BookLibraryService {
  @override
  Future<List<LocalBook>> load() async => const [];

  @override
  Future<void> save(List<LocalBook> books) async {}

  @override
  Future<LocalBook> importEpub(File source, String originalFilename) {
    throw UnimplementedError();
  }
}

/// Giả lập firmware mới: áp dụng phần device được push rồi echo lại
/// trạng thái sau khi áp dụng.
class _DeviceEchoBleClient extends BizTransferBleClient {
  BizSyncSnapshot? sent;

  @override
  Future<BizSyncSnapshot> synchronize({
    required String deviceId,
    required BizSyncSnapshot local,
  }) async {
    sent = local;
    return BizSyncSnapshot(
      content: local.content,
      progress: const [],
      device: BizDeviceSection(
        settings: {
          'fontSize': 2,
          'uiTheme': 1,
          'mysteryKey': 'x',
          ...?local.device?.settings,
        },
        wifiSsids: [
          'NhaRieng',
          ...?local.device?.wifiAdd.map((credential) => credential.ssid),
        ],
      ),
    );
  }
}

/// Giả lập firmware từ chối wifiAdd (vd đã đủ 8 mạng): echo không chứa
/// SSID vừa push.
class _RejectingWifiBleClient extends BizTransferBleClient {
  BizSyncSnapshot? sent;

  @override
  Future<BizSyncSnapshot> synchronize({
    required String deviceId,
    required BizSyncSnapshot local,
  }) async {
    sent = local;
    return BizSyncSnapshot(
      content: local.content,
      progress: const [],
      device: const BizDeviceSection(
        settings: {'fontSize': 2},
        wifiSsids: ['NhaRieng'],
      ),
    );
  }
}

/// Giả lập firmware áp dụng add/remove nhưng chỉ trả lời sau khi test mở
/// cổng, để chen thao tác vào giữa lúc đồng bộ.
class _GatedEchoBleClient extends BizTransferBleClient {
  BizSyncSnapshot? sent;
  Completer<void>? gate;
  List<String> deviceSsids = ['NhaRieng'];

  @override
  Future<BizSyncSnapshot> synchronize({
    required String deviceId,
    required BizSyncSnapshot local,
  }) async {
    sent = local;
    final pending = gate;
    if (pending != null) await pending.future;
    final next = <String>{
      ...deviceSsids,
      ...?local.device?.wifiAdd.map((credential) => credential.ssid),
    }..removeAll(local.device?.wifiRemove ?? const []);
    deviceSsids = next.toList();
    return BizSyncSnapshot(
      content: local.content,
      progress: const [],
      device: BizDeviceSection(
        settings: const {'fontSize': 2},
        wifiSsids: deviceSsids,
      ),
    );
  }
}

class _NoDeviceBleClient extends BizTransferBleClient {
  @override
  Future<BizSyncSnapshot> synchronize({
    required String deviceId,
    required BizSyncSnapshot local,
  }) async {
    return BizSyncSnapshot(content: local.content, progress: const []);
  }
}
