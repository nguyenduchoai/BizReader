import 'dart:io';

import 'package:bizreader_connect/src/app_controller.dart';
import 'package:bizreader_connect/src/models/biz_sync_snapshot.dart';
import 'package:bizreader_connect/src/models/device_config.dart';
import 'package:bizreader_connect/src/models/device_reading_progress.dart';
import 'package:bizreader_connect/src/models/local_book.dart';
import 'package:bizreader_connect/src/services/biz_transfer_ble_client.dart';
import 'package:bizreader_connect/src/services/book_library_service.dart';
import 'package:bizreader_connect/src/services/content_preferences.dart';
import 'package:bizreader_connect/src/services/device_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'controller saves pages and preserves them for legacy callers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final library = _ProgressBookLibrary();
      final controller = AppController(
        DevicePreferences(),
        bookLibrary: library,
      );
      await controller.load();

      await controller.updateBookProgress(
        'book',
        progress: 0.42,
        chapterNumber: 2,
        chapterProgress: 35,
        pageNumber: 84,
        pageCount: 201,
        updatedAt: 2000,
      );
      await controller.updateBookProgress(
        'book',
        progress: 0.43,
        chapterNumber: 2,
        chapterProgress: 36,
        updatedAt: 2001,
      );

      final book = controller.books.single;
      expect(book.pageNumber, 84);
      expect(book.pageCount, 201);
      expect(library.lastSaved.single.pageNumber, 84);
      expect(library.lastSaved.single.pageCount, 201);
    },
  );

  test('BLE Sync v2 sends and applies the paginated position', () async {
    SharedPreferences.setMockInitialValues({});
    final library = _ProgressBookLibrary();
    final ble = _SyncBleClient();
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: library,
      bleClient: ble,
    );
    await controller.load();
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );

    await controller.syncContentToDevice();

    final sent = ble.sent!.progress.single;
    expect(sent.pageNumber, 4);
    expect(sent.pageCount, 20);

    final merged = controller.books.single;
    expect(merged.pageNumber, 10);
    expect(merged.pageCount, 81);
    expect(merged.chapterNumber, 3);
    expect(merged.chapterProgress, 12.5);
    expect(library.lastSaved.single.pageNumber, 10);
    expect(library.lastSaved.single.pageCount, 81);
  });

  test('a page turned during the BLE exchange is not clobbered', () async {
    SharedPreferences.setMockInitialValues({});
    final library = _ProgressBookLibrary();
    late AppController controller;
    // The merged result carries updatedAt 200 (device newer than the local
    // snapshot taken at 100), but while the exchange is in flight the reader
    // advances to updatedAt 300. The stale merge must not be applied.
    final ble = _RacingBleClient(
      onDuringSync: () => controller.updateBookProgress(
        'book',
        progress: 0.9,
        chapterNumber: 7,
        chapterProgress: 80,
        pageNumber: 18,
        pageCount: 20,
        epubCfi: 'epubcfi(/6/14!/4/2/1:0)',
        updatedAt: 300,
      ),
    );
    controller = AppController(
      DevicePreferences(),
      bookLibrary: library,
      bleClient: ble,
    );
    await controller.load();
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );

    await controller.syncContentToDevice();

    final book = controller.books.single;
    expect(book.progress, 0.9);
    expect(book.chapterNumber, 7);
    expect(book.pageNumber, 18);
    expect(book.updatedAt, 300);
    expect(book.epubCfi, 'epubcfi(/6/14!/4/2/1:0)');
    expect(library.lastSaved.single.progress, 0.9);
    expect(library.lastSaved.single.updatedAt, 300);
  });

  test('a note saved and a todo deleted mid-exchange survive the merge', () async {
    SharedPreferences.setMockInitialValues({});
    final library = _ProgressBookLibrary();
    late AppController controller;
    late String staleTodoId;
    // The device echoes back the content snapshot taken at sync start. Edits
    // landing while the exchange is in flight exist only locally; the merge
    // must keep them instead of adopting the echo wholesale.
    final ble = _RacingBleClient(
      onDuringSync: () async {
        await controller.saveNote(title: 'Ghi chú mới', body: 'Nội dung');
        await controller.deleteTodo(staleTodoId);
      },
    );
    controller = AppController(
      DevicePreferences(),
      bookLibrary: library,
      bleClient: ble,
    );
    await controller.load();
    controller.device = const DeviceConfig(
      name: 'BizReader',
      host: '',
      bleId: 'reader',
    );
    await controller.addTodo('Việc cần xóa');
    staleTodoId = controller.content.todos.single.id;

    await controller.syncContentToDevice();

    expect(controller.content.notes.single.title, 'Ghi chú mới');
    expect(controller.content.todos, isEmpty);
    final persisted = await ContentPreferences().load();
    expect(persisted.notes.single.title, 'Ghi chú mới');
    expect(persisted.todos, isEmpty);
  });

  test('direct device progress keeps page fields when adopted', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(
      DevicePreferences(),
      bookLibrary: _ProgressBookLibrary(),
    );
    await controller.load();

    await controller.useDeviceProgress(
      controller.books.single,
      const DeviceReadingProgress(
        filename: 'book.epub',
        percentage: 0.6,
        spineIndex: 4,
        pageNumber: 18,
        pageCount: 61,
      ),
    );

    expect(controller.books.single.pageNumber, 18);
    expect(controller.books.single.pageCount, 61);
  });
}

class _ProgressBookLibrary extends BookLibraryService {
  List<LocalBook> lastSaved = const [];

  @override
  Future<List<LocalBook>> load() async => const [
    LocalBook(
      id: 'book',
      title: 'Sách',
      author: 'Tác giả',
      filePath: '/tmp/book.epub',
      remoteFilename: 'book.epub',
      progress: 0.2,
      chapterNumber: 1,
      chapterProgress: 20,
      pageNumber: 4,
      pageCount: 20,
      updatedAt: 100,
    ),
  ];

  @override
  Future<void> save(List<LocalBook> books) async {
    lastSaved = List<LocalBook>.from(books);
  }

  @override
  Future<LocalBook> importEpub(File source, String originalFilename) {
    throw UnimplementedError();
  }
}

class _RacingBleClient extends BizTransferBleClient {
  _RacingBleClient({required this.onDuringSync});

  final Future<void> Function() onDuringSync;

  @override
  Future<BizSyncSnapshot> synchronize({
    required String deviceId,
    required BizSyncSnapshot local,
  }) async {
    // Simulates a page turn landing while the BLE exchange is in flight.
    await onDuringSync();
    return BizSyncSnapshot(
      content: local.content,
      progress: const [
        DeviceReadingProgress(
          filename: 'book.epub',
          percentage: 0.5,
          spineIndex: 2,
          pageNumber: 10,
          pageCount: 81,
          updatedAt: 200,
        ),
      ],
    );
  }
}

class _SyncBleClient extends BizTransferBleClient {
  BizSyncSnapshot? sent;

  @override
  Future<BizSyncSnapshot> synchronize({
    required String deviceId,
    required BizSyncSnapshot local,
  }) async {
    sent = local;
    return BizSyncSnapshot(
      content: local.content,
      progress: const [
        DeviceReadingProgress(
          filename: 'book.epub',
          percentage: 0.5,
          spineIndex: 2,
          pageNumber: 10,
          pageCount: 81,
          updatedAt: 200,
        ),
      ],
    );
  }
}
