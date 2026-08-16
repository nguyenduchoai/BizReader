import 'dart:convert';
import 'dart:io';

import 'package:bizreader_connect/src/app.dart';
import 'package:bizreader_connect/src/app_controller.dart';
import 'package:bizreader_connect/src/models/local_book.dart';
import 'package:bizreader_connect/src/models/device_config.dart';
import 'package:bizreader_connect/src/screens/device_settings_screen.dart';
import 'package:bizreader_connect/src/services/biz_transfer_ble_client.dart';
import 'package:bizreader_connect/src/services/book_library_service.dart';
import 'package:bizreader_connect/src/services/device_preferences.dart';
import 'package:bizreader_connect/src/services/legal_licenses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('demo reading does not overwrite the real library', () async {
    SharedPreferences.setMockInitialValues({});
    final library = _FakeBookLibrary();
    final controller = AppController(DevicePreferences(), bookLibrary: library);
    await controller.load();

    controller.enterDemoMode();
    await controller.updateBookProgress(
      'demo-thinking',
      progress: 0.6,
      chapterNumber: 2,
      chapterProgress: 20,
    );
    await controller.exitDemoMode();

    expect(library.saveCalls, 0);
    expect(controller.books.single.title, 'Sách thật');
  });

  test('reimporting the same EPUB preserves reading position', () async {
    SharedPreferences.setMockInitialValues({});
    final library = _FakeBookLibrary();
    final controller = AppController(DevicePreferences(), bookLibrary: library);
    await controller.load();

    final imported = await controller.importBook(
      File('/tmp/reimport.epub'),
      'renamed.epub',
    );

    expect(imported.progress, 0.42);
    expect(imported.epubCfi, 'epubcfi(/6/4)');
    expect(imported.chapterNumber, 3);
    expect(imported.chapterProgress, 35);
    expect(imported.updatedAt, 1234);
    expect(imported.remoteFilename, 'real.epub');
    expect(library.saveCalls, 1);
  });

  test(
    'finishing a transfer closes BLE and clears the session token',
    () async {
      SharedPreferences.setMockInitialValues({});
      final ble = _FakeBleClient();
      final controller = AppController(DevicePreferences(), bleClient: ble)
        ..device = const DeviceConfig(
          name: 'BizReader',
          host: 'http://192.168.1.10:8080',
          bleId: 'reader-id',
          transferToken: 'expired-session',
        );

      await controller.finishTransfer();

      expect(ble.stopCalls, 1);
      expect(controller.device.transferToken, isEmpty);
      expect(controller.connectionState, DeviceConnectionState.unknown);
    },
  );

  test(
    'different EPUBs with the same filename get unique device names',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = AppController(
        DevicePreferences(),
        bookLibrary: _CollisionBookLibrary(),
      );
      await controller.load();

      final imported = await controller.importBook(
        File('/tmp/second.epub'),
        'same.epub',
      );

      expect(imported.remoteFilename, 'same-abcdef01.epub');
      expect(
        controller.books.map((book) => book.remoteFilename).toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'collision suffix keeps a max-length device name within the byte budget',
    () async {
      SharedPreferences.setMockInitialValues({});
      // A Vietnamese title clamped to the cap: appending any suffix would
      // overflow the firmware budget unless the stem is trimmed to make room.
      final longFilename = BookLibraryService.clampRemoteFilename(
        '${'ế' * 100}.epub',
      );
      final controller = AppController(
        DevicePreferences(),
        bookLibrary: _CollisionBookLibrary(longFilename),
      );
      await controller.load();

      final imported = await controller.importBook(
        File('/tmp/second.epub'),
        'same.epub',
      );

      expect(imported.remoteFilename, endsWith('-abcdef01.epub'));
      expect(imported.remoteFilename, isNot(longFilename));
      expect(
        utf8.encode(imported.remoteFilename).length,
        lessThanOrEqualTo(BookLibraryService.maxRemoteFilenameBytes),
      );
      expect(
        controller.books.map((book) => book.remoteFilename).toSet(),
        hasLength(2),
      );
    },
  );

  testWidgets('opens dashboard before device setup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(DevicePreferences());
    await controller.load();

    await tester.pumpWidget(BizReaderApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Tổng quan'), findsOneWidget);
    expect(find.text('Chưa thêm thiết bị'), findsOneWidget);
    expect(find.text('Kết nối BizReader'), findsNothing);

    await tester.tap(find.text('Thiết bị'));
    await tester.pumpAndSettle();
    expect(find.text('Kết nối BizReader'), findsOneWidget);
    expect(find.text('Tìm BizReader'), findsOneWidget);
  });

  testWidgets('demo mode opens a populated library and reader', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(DevicePreferences());
    await controller.load();

    await tester.pumpWidget(BizReaderApp(controller: controller));
    await tester.tap(find.text('Thiết bị'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem bản demo'));
    await tester.pumpAndSettle();

    expect(find.text('BizReader Demo'), findsWidgets);
    await tester.tap(find.text('Thư viện'));
    await tester.pumpAndSettle();
    expect(find.text('Thay đổi tư duy'), findsOneWidget);

    await tester.ensureVisible(find.text('Thay đổi tư duy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thay đổi tư duy'));
    await tester.pumpAndSettle();
    expect(find.text('Thay đổi tư duy'), findsWidgets);
    expect(find.textContaining('CHƯƠNG'), findsOneWidget);

    final pageViewFinder = find.byKey(const Key('bizreader-demo-page-view'));
    final pageView = tester.widget<PageView>(pageViewFinder);
    expect(pageView.scrollDirection, Axis.horizontal);
    expect(find.byType(SingleChildScrollView), findsNothing);

    await tester.tap(find.byTooltip('Tùy chỉnh đọc'));
    await tester.pumpAndSettle();
    expect(find.text('Tùy chỉnh đọc'), findsOneWidget);
    expect(find.byTooltip('Sáng'), findsOneWidget);
    expect(find.byTooltip('Giấy'), findsOneWidget);
    expect(find.byTooltip('Xanh'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();

    final startPage = pageView.controller!.page;
    await tester.fling(pageViewFinder, const Offset(-320, 0), 900);
    await tester.pumpAndSettle();
    expect(pageView.controller!.page, startPage! + 1);
  });

  testWidgets('dashboard fits a compact Android viewport', (tester) async {
    SharedPreferences.setMockInitialValues({
      'device_name': 'BizReader',
      'device_host': '192.168.4.1',
    });
    final controller = AppController(DevicePreferences());
    await controller.load();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(BizReaderApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Ứng dụng thiết bị'), findsOneWidget);
    expect(find.text('Tệp đa định dạng'), findsOneWidget);
    expect(find.text('Hoài Nguyễn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard opens working notes module', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(DevicePreferences());
    await controller.load();
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(BizReaderApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ghi chú').first);
    await tester.tap(find.text('Ghi chú').first);
    await tester.pumpAndSettle();

    expect(find.text('Tiện ích BizReader'), findsOneWidget);
    expect(find.text('Chưa có ghi chú'), findsOneWidget);
    await tester.tap(find.byTooltip('Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm ghi chú'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Ghi chú mới');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Ghi chú mới'), findsOneWidget);
  });

  testWidgets('device About exposes BizReader legal notices', (tester) async {
    SharedPreferences.setMockInitialValues({
      'device_name': 'BizReader',
      'device_host': '192.168.4.1',
    });
    registerBizReaderLicenses();
    final controller = AppController(DevicePreferences());
    await controller.load();

    await tester.pumpWidget(BizReaderApp(controller: controller));
    await tester.tap(find.text('Thiết bị'));
    await tester.pumpAndSettle();
    // Các thẻ Wi-Fi/cài đặt máy đọc đẩy mục Giới thiệu xuống dưới màn hình.
    await tester.scrollUntilVisible(
      find.text('Giới thiệu'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(DeviceSettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Giới thiệu'));
    await tester.pumpAndSettle();

    expect(find.text('BizReader'), findsWidgets);
    expect(find.text('0.8.0'), findsWidgets);
    expect(find.text('Hoài Nguyễn'), findsWidgets);

    await tester.tap(find.textContaining('giấy phép'));
    await tester.pumpAndSettle();
    expect(find.text('Gander'), findsOneWidget);
    expect(find.text('BizReader vendored viewers'), findsOneWidget);
  });
}

class _FakeBookLibrary extends BookLibraryService {
  int saveCalls = 0;
  final List<LocalBook> stored = const [
    LocalBook(
      id: 'real-book',
      title: 'Sách thật',
      author: 'Tác giả',
      filePath: '/tmp/real.epub',
      remoteFilename: 'real.epub',
      progress: 0.42,
      epubCfi: 'epubcfi(/6/4)',
      chapterNumber: 3,
      chapterProgress: 35,
      updatedAt: 1234,
    ),
  ];

  @override
  Future<List<LocalBook>> load() async => stored;

  @override
  Future<void> save(List<LocalBook> books) async {
    saveCalls++;
  }

  @override
  Future<LocalBook> importEpub(File source, String originalFilename) async =>
      const LocalBook(
        id: 'real-book',
        title: 'Sách thật',
        author: 'Tác giả',
        filePath: '/tmp/real.epub',
        remoteFilename: 'renamed.epub',
      );
}

class _FakeBleClient extends BizTransferBleClient {
  int stopCalls = 0;

  @override
  Future<void> stopTransfer() async {
    stopCalls++;
  }
}

class _CollisionBookLibrary extends BookLibraryService {
  _CollisionBookLibrary([this.existingFilename = 'same.epub']);

  final String existingFilename;

  @override
  Future<List<LocalBook>> load() async => [
    LocalBook(
      id: 'existing-id',
      title: 'Sách đầu',
      author: '',
      filePath: '/tmp/first.epub',
      remoteFilename: existingFilename,
    ),
  ];

  @override
  Future<LocalBook> importEpub(File source, String originalFilename) async =>
      LocalBook(
        id: 'abcdef0123456789',
        title: 'Sách sau',
        author: '',
        filePath: '/tmp/second.epub',
        remoteFilename: existingFilename,
      );

  @override
  Future<void> save(List<LocalBook> books) async {}
}
