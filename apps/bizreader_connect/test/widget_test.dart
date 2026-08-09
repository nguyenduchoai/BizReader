import 'dart:io';

import 'package:bizreader_connect/src/app.dart';
import 'package:bizreader_connect/src/app_controller.dart';
import 'package:bizreader_connect/src/models/local_book.dart';
import 'package:bizreader_connect/src/services/book_library_service.dart';
import 'package:bizreader_connect/src/services/device_preferences.dart';
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

  testWidgets('shows device setup when no device is stored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(DevicePreferences());
    await controller.load();

    await tester.pumpWidget(BizReaderApp(controller: controller));

    expect(find.text('Kết nối BizReader'), findsOneWidget);
    expect(find.text('Tìm BizReader'), findsOneWidget);
    expect(find.textContaining('Truyền tệp > Kết nối App'), findsOneWidget);
    expect(find.text('Hoài Nguyễn'), findsNothing);
  });

  testWidgets('demo mode opens a populated library and reader', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(DevicePreferences());
    await controller.load();

    await tester.pumpWidget(BizReaderApp(controller: controller));
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
    expect(find.text('Hoài Nguyễn'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    ),
  ];

  @override
  Future<List<LocalBook>> load() async => stored;

  @override
  Future<void> save(List<LocalBook> books) async {
    saveCalls++;
  }

  @override
  Future<LocalBook> importEpub(File source, String originalFilename) {
    throw UnimplementedError();
  }
}
