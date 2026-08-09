import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models/biz_transfer_status.dart';
import 'models/device_config.dart';
import 'models/device_reading_progress.dart';
import 'models/local_book.dart';
import 'services/book_library_service.dart';
import 'services/biz_transfer_ble_client.dart';
import 'services/device_preferences.dart';
import 'services/webdav_device_client.dart';

enum DeviceConnectionState { unknown, checking, online, offline }

class AppController extends ChangeNotifier {
  AppController(
    this._preferences, {
    BizTransferBleClient? bleClient,
    BookLibraryService? bookLibrary,
  }) : _bleClient = bleClient ?? BizTransferBleClient(),
       _bookLibrary = bookLibrary ?? BookLibraryService();

  final DevicePreferences _preferences;
  final BizTransferBleClient _bleClient;
  final BookLibraryService _bookLibrary;

  DeviceConfig device = const DeviceConfig(name: 'BizReader', host: '');
  DeviceConnectionState connectionState = DeviceConnectionState.unknown;
  String? connectionMessage;
  List<LocalBook> books = const [];
  bool demoMode = false;

  Future<void> load() async {
    device = await _preferences.load();
    books = await _bookLibrary.load();
  }

  void enterDemoMode() {
    demoMode = true;
    device = const DeviceConfig(
      name: 'BizReader Demo',
      host: 'demo.bizreader.local',
    );
    books = LocalBook.demoLibrary();
    connectionState = DeviceConnectionState.online;
    connectionMessage = 'Đang dùng dữ liệu trình diễn';
    notifyListeners();
  }

  Future<void> exitDemoMode() async {
    demoMode = false;
    device = await _preferences.load();
    books = await _bookLibrary.load();
    connectionState = DeviceConnectionState.unknown;
    connectionMessage = null;
    notifyListeners();
  }

  Future<LocalBook> importBook(File file, String originalFilename) async {
    final imported = await _bookLibrary.importEpub(file, originalFilename);
    final updated = [
      ...books.where((book) => book.id != imported.id),
      imported,
    ];
    books = updated;
    await _bookLibrary.save(books);
    notifyListeners();
    return imported;
  }

  Future<void> updateBookProgress(
    String bookId, {
    required double progress,
    required int chapterNumber,
    required double chapterProgress,
    String? epubCfi,
    bool clearEpubCfi = false,
    int? updatedAt,
  }) async {
    books = [
      for (final book in books)
        if (book.id == bookId)
          book.copyWith(
            progress: progress.clamp(0, 1),
            epubCfi: epubCfi,
            clearEpubCfi: clearEpubCfi,
            chapterNumber: chapterNumber,
            chapterProgress: chapterProgress.clamp(0, 100),
            updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
          )
        else
          book,
    ];
    if (!demoMode) await _bookLibrary.save(books);
    notifyListeners();
  }

  Future<DeviceReadingProgress?> fetchDeviceProgress(LocalBook book) async {
    if (demoMode) {
      return DeviceReadingProgress(
        filename: book.remoteFilename,
        percentage: (book.progress + 0.09).clamp(0, 1),
        spineIndex: book.chapterNumber,
      );
    }
    return _withTransferClient(
      (client) => client.fetchReadingProgress(book.remoteFilename),
    );
  }

  Future<void> pushProgressToDevice(LocalBook book) async {
    if (demoMode) return;
    await _withTransferClient(
      (client) => client.pushReadingProgress(
        filename: book.remoteFilename,
        percentage: book.progress,
      ),
    );
  }

  Future<void> useDeviceProgress(
    LocalBook book,
    DeviceReadingProgress progress,
  ) {
    return updateBookProgress(
      book.id,
      progress: progress.percentage,
      chapterNumber: progress.spineIndex + 1,
      chapterProgress: 0,
      clearEpubCfi: true,
    );
  }

  Future<T> _withTransferClient<T>(
    Future<T> Function(WebDavDeviceClient client) action,
  ) async {
    WebDavDeviceClient? client;
    try {
      final activeDevice = await prepareTransfer();
      if (activeDevice.transferToken.isEmpty) {
        throw const DeviceConnectionException(
          'Đồng bộ tiến độ cần kết nối BizReader qua Bluetooth.',
        );
      }
      client = WebDavDeviceClient(activeDevice);
      await client.probe();
      return await action(client);
    } finally {
      client?.close();
      if (device.usesBizTransfer) await finishTransfer();
    }
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

  Future<void> saveBleDevice(BizReaderBleDevice discovered) async {
    device = DeviceConfig(
      name: discovered.name,
      host: '',
      bleId: discovered.id,
    );
    await _preferences.save(device);
    connectionState = DeviceConnectionState.unknown;
    connectionMessage = 'Đã lưu BizReader';
    notifyListeners();
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
