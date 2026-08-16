import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'models/biz_transfer_status.dart';
import 'models/biz_sync_snapshot.dart';
import 'models/biz_content.dart';
import 'models/biz_device_section.dart';
import 'models/device_config.dart';
import 'models/device_reading_progress.dart';
import 'models/local_book.dart';
import 'services/book_library_service.dart';
import 'services/biz_transfer_ble_client.dart';
import 'services/content_preferences.dart';
import 'services/device_preferences.dart';
import 'services/universal_file_viewer.dart';
import 'services/webdav_device_client.dart';
import 'services/weather_service.dart';

enum DeviceConnectionState { unknown, checking, online, offline }

class AppController extends ChangeNotifier {
  AppController(
    this._preferences, {
    BizTransferBleClient? bleClient,
    BookLibraryService? bookLibrary,
    ContentPreferences? contentPreferences,
    FileViewer? fileViewer,
    WeatherService? weatherService,
  }) : _bleClient = bleClient ?? BizTransferBleClient(),
       _bookLibrary = bookLibrary ?? BookLibraryService(),
       _contentPreferences = contentPreferences ?? ContentPreferences(),
       _fileViewer = fileViewer ?? UniversalFileViewer(),
       _weatherService = weatherService ?? WeatherService();

  final DevicePreferences _preferences;
  final BizTransferBleClient _bleClient;
  final BookLibraryService _bookLibrary;
  final ContentPreferences _contentPreferences;
  final FileViewer _fileViewer;
  final WeatherService _weatherService;

  DeviceConfig device = const DeviceConfig(name: 'BizReader', host: '');
  DeviceConnectionState connectionState = DeviceConnectionState.unknown;
  String? connectionMessage;
  List<LocalBook> books = const [];
  BizContent content = const BizContent();
  BizDeviceState deviceState = const BizDeviceState();
  bool demoMode = false;
  bool contentSyncing = false;
  String? contentSyncMessage;
  bool wifiScanning = false;

  /// Phiên truyền sách (prepareTransfer..finishTransfer) đang mở — client BLE
  /// dùng chung, thao tác khác chen vào sẽ ngắt kết nối giữa chừng.
  bool transferSessionActive = false;

  /// Trạng thái máy đọc thật, cất tạm trong lúc xem bản demo.
  BizDeviceState? _preDemoDeviceState;

  /// Các luồng BLE (đồng bộ, quét Wi-Fi, truyền sách) dùng chung một client
  /// với `finally { disconnect() }` theo từng thao tác — chạy chồng sẽ ngắt
  /// kết nối của nhau giữa chừng, nên chặn ngay tại cửa.
  void _ensureBleIdle() {
    if (contentSyncing || wifiScanning || transferSessionActive) {
      throw const BizTransferException(
        'Đang bận thao tác BLE khác, hãy thử lại sau.',
      );
    }
  }

  Future<void> load() async {
    device = await _preferences.load();
    books = await _bookLibrary.load();
    content = await _contentPreferences.load();
    deviceState = await _preferences.loadDeviceState();
  }

  void enterDemoMode() {
    demoMode = true;
    device = const DeviceConfig(
      name: 'BizReader Demo',
      host: 'demo.bizreader.local',
    );
    // Cất trạng thái thật; bản demo sửa trên bản sao, thoát demo trả lại
    // nguyên vẹn (không lọt hàng đợi demo vào lần đồng bộ thật).
    _preDemoDeviceState ??= deviceState;
    deviceState = const BizDeviceState(
      settings: {
        'sleepTimeoutMinutes': 5,
        'sleepScreen': 3,
        'uiTheme': 1,
        'language': 'VI',
        'fontSize': 1,
        'lineSpacing': 1,
        'screenMargin': 20,
        'refreshFrequency': 2,
        'sideButtonLayout': 0,
      },
      wifiSsids: ['NhaRieng', 'VanPhong'],
    );
    books = LocalBook.demoLibrary();
    content = BizContent(
      notes: [
        BizNote(
          id: 'demo-note',
          title: 'Ý tưởng kinh doanh',
          body: 'Hoàn thiện đề xuất và gửi trước 16:00.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      todos: const [
        BizTodo(id: 'demo-todo', title: 'Đọc 20 trang', due: 'Hôm nay'),
      ],
      events: [
        BizCalendarEvent(
          id: 'demo-event',
          title: 'Họp kế hoạch tuần',
          date: _dateOnly(DateTime.now()),
          time: '09:30',
        ),
      ],
      weather: BizWeather(
        location: 'Hà Nội',
        condition: 'Ít mây',
        temperature: 29,
        high: 32,
        low: 25,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    connectionState = DeviceConnectionState.online;
    connectionMessage = 'Đang dùng dữ liệu trình diễn';
    notifyListeners();
  }

  Future<void> exitDemoMode() async {
    demoMode = false;
    device = await _preferences.load();
    books = await _bookLibrary.load();
    content = await _contentPreferences.load();
    deviceState = _preDemoDeviceState ?? await _preferences.loadDeviceState();
    _preDemoDeviceState = null;
    connectionState = DeviceConnectionState.unknown;
    connectionMessage = null;
    notifyListeners();
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _saveContent(BizContent next) async {
    content = next.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);
    if (!demoMode) await _contentPreferences.save(content);
    notifyListeners();
  }

  Future<void> saveNote({
    String? id,
    required String title,
    required String body,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = BizNote(
      id: id ?? 'note-$now',
      title: title.trim(),
      body: body.trim(),
      updatedAt: now,
    );
    return _saveContent(
      content.copyWith(
        notes: [...content.notes.where((item) => item.id != note.id), note],
      ),
    );
  }

  Future<void> deleteNote(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _saveContent(
      content.copyWith(
        notes: content.notes.where((item) => item.id != id).toList(),
        deletedNotes: [
          ...content.deletedNotes.where((item) => item.id != id),
          BizDeletedItem(id: id, updatedAt: now),
        ],
      ),
    );
  }

  Future<void> addTodo(String title, {String due = ''}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _saveContent(
      content.copyWith(
        todos: [
          ...content.todos,
          BizTodo(
            id: 'todo-$now',
            title: title.trim(),
            due: due.trim(),
            updatedAt: now,
          ),
        ],
      ),
    );
  }

  Future<void> toggleTodo(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _saveContent(
      content.copyWith(
        todos: [
          for (final item in content.todos)
            if (item.id == id)
              item.copyWith(done: !item.done, updatedAt: now)
            else
              item,
        ],
      ),
    );
  }

  Future<void> deleteTodo(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _saveContent(
      content.copyWith(
        todos: content.todos.where((item) => item.id != id).toList(),
        deletedTodos: [
          ...content.deletedTodos.where((item) => item.id != id),
          BizDeletedItem(id: id, updatedAt: now),
        ],
      ),
    );
  }

  Future<void> addCalendarEvent({
    required String title,
    required DateTime date,
    String time = '',
    String location = '',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final events = [
      ...content.events,
      BizCalendarEvent(
        id: 'event-$now',
        title: title.trim(),
        date: _dateOnly(date),
        time: time.trim(),
        location: location.trim(),
      ),
    ]..sort((a, b) => '${a.date}${a.time}'.compareTo('${b.date}${b.time}'));
    return _saveContent(content.copyWith(events: events));
  }

  Future<void> deleteCalendarEvent(String id) => _saveContent(
    content.copyWith(
      events: content.events.where((item) => item.id != id).toList(),
    ),
  );

  Future<void> updateWeather(BizWeather weather) =>
      _saveContent(content.copyWith(weather: weather));

  Future<void> refreshWeather(String city) async {
    final weather = await _weatherService.fetch(city.trim());
    await updateWeather(weather);
  }

  Future<void> setSleepMode(BizSleepMode mode) =>
      _saveContent(content.copyWith(sleepMode: mode));

  // --- Cấu hình máy đọc (đồng bộ qua BLE, app quyết định — last edit wins) ---

  Future<void> _saveDeviceState(BizDeviceState next) async {
    deviceState = next;
    if (!demoMode) await _preferences.saveDeviceState(next);
    notifyListeners();
  }

  /// Sửa một cài đặt của máy đọc; xếp hàng chờ lần đồng bộ tới.
  /// Sửa về đúng giá trị máy đang có thì bỏ khỏi hàng đợi.
  Future<void> setDeviceSetting(String key, Object? value) {
    final pending = Map<String, Object?>.of(deviceState.pendingSettings);
    if (deviceState.settings.containsKey(key) &&
        deviceState.settings[key] == value) {
      pending.remove(key);
    } else {
      pending[key] = value;
    }
    return _saveDeviceState(deviceState.copyWith(pendingSettings: pending));
  }

  Future<void> queueWifiAdd(String ssid, String password) {
    return _saveDeviceState(
      deviceState.copyWith(
        pendingWifiAdd: [
          ...deviceState.pendingWifiAdd.where((c) => c.ssid != ssid),
          BizWifiCredential(ssid: ssid, password: password),
        ],
        // Thêm lại một mạng đang chờ xóa thì hủy lệnh xóa.
        pendingWifiRemove: deviceState.pendingWifiRemove
            .where((s) => s != ssid)
            .toList(),
        // Thêm lại một mạng từng bị từ chối thì bỏ khỏi danh sách từ chối.
        failedWifiAdds: deviceState.failedWifiAdds
            .where((c) => c.ssid != ssid)
            .toList(),
      ),
    );
  }

  Future<void> cancelWifiAdd(String ssid) => _saveDeviceState(
    deviceState.copyWith(
      pendingWifiAdd: deviceState.pendingWifiAdd
          .where((c) => c.ssid != ssid)
          .toList(),
    ),
  );

  Future<void> queueWifiRemove(String ssid) {
    return _saveDeviceState(
      deviceState.copyWith(
        pendingWifiAdd: deviceState.pendingWifiAdd
            .where((c) => c.ssid != ssid)
            .toList(),
        // Xếp hàng vô điều kiện: lệnh thêm có thể đang trên đường tới máy
        // (đã push, chưa reconcile) nên không thể chỉ dựa vào wifiSsids.
        // Xóa SSID máy không biết là no-op với firmware, và reconcile sẽ tự
        // rút lệnh xóa khi SSID không có trong echo.
        pendingWifiRemove: [
          ...deviceState.pendingWifiRemove.where((s) => s != ssid),
          ssid,
        ],
      ),
    );
  }

  /// Đưa một mạng bị máy từ chối trở lại hàng đợi thêm ("Thử lại").
  Future<void> retryWifiAdd(String ssid) {
    final matches = deviceState.failedWifiAdds.where((c) => c.ssid == ssid);
    if (matches.isEmpty) return Future.value();
    return queueWifiAdd(ssid, matches.first.password);
  }

  /// Bỏ hẳn một mạng bị máy từ chối ("Xoá").
  Future<void> dismissFailedWifiAdd(String ssid) => _saveDeviceState(
    deviceState.copyWith(
      failedWifiAdds: deviceState.failedWifiAdds
          .where((c) => c.ssid != ssid)
          .toList(),
    ),
  );

  Future<void> cancelWifiRemove(String ssid) => _saveDeviceState(
    deviceState.copyWith(
      pendingWifiRemove: deviceState.pendingWifiRemove
          .where((s) => s != ssid)
          .toList(),
    ),
  );

  /// Nhờ máy đọc quét Wi-Fi xung quanh nó (kết nối BLE theo từng lần gọi,
  /// như syncContentToDevice). Ném [BizWifiScanUnsupportedException] khi
  /// firmware cũ không phản hồi — UI quay về nhập thủ công.
  Future<List<BizWifiScanResult>> scanDeviceWifi() async {
    if (demoMode) {
      return const [
        BizWifiScanResult(ssid: 'NhaRieng', rssi: -48, secured: true),
        BizWifiScanResult(ssid: 'VanPhong', rssi: -66, secured: true),
        BizWifiScanResult(ssid: 'CafeSach', rssi: -82, secured: false),
      ];
    }
    if (device.bleId.isEmpty) {
      throw const BizTransferException(
        'Hãy chọn BizReader trong mục Thiết bị trước.',
      );
    }
    _ensureBleIdle();
    wifiScanning = true;
    notifyListeners();
    try {
      return await _bleClient.scanDeviceWifi(deviceId: device.bleId);
    } finally {
      wifiScanning = false;
      notifyListeners();
    }
  }

  Future<void> setWallpaper(File source) async {
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) throw const FormatException('Ảnh không hợp lệ.');
    final resized = img.copyResize(
      decoded,
      width: 960,
      height: 540,
      interpolation: img.Interpolation.average,
    );
    final grayscale = img.grayscale(resized);
    final directory = await getApplicationSupportDirectory();
    final output = File('${directory.path}/bizreader_sleep.bmp');
    await output.writeAsBytes(img.encodeBmp(grayscale), flush: true);
    await _saveContent(
      content.copyWith(
        sleepMode: BizSleepMode.photo,
        wallpaperPath: output.path,
      ),
    );
  }

  Future<void> clearWallpaper() async {
    final path = content.wallpaperPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await _saveContent(
      content.copyWith(sleepMode: BizSleepMode.calendar, clearWallpaper: true),
    );
  }

  Future<void> syncContentToDevice() async {
    if (demoMode) {
      contentSyncMessage = 'Bản demo không gửi dữ liệu ra thiết bị.';
      notifyListeners();
      return;
    }
    _ensureBleIdle();
    contentSyncing = true;
    contentSyncMessage = 'Đang đồng bộ hai chiều qua BLE';
    notifyListeners();
    try {
      if (device.bleId.isEmpty) {
        throw const BizTransferException(
          'Hãy chọn BizReader trong mục Thiết bị trước.',
        );
      }
      final pushedDevice = deviceState.toPushSection();
      final snapshot = await _bleClient.synchronize(
        deviceId: device.bleId,
        local: BizSyncSnapshot(
          content: content,
          progress: [
            for (final book in books)
              DeviceReadingProgress(
                filename: book.remoteFilename,
                percentage: book.progress,
                spineIndex: book.chapterNumber > 0 ? book.chapterNumber - 1 : 0,
                pageNumber: book.pageNumber,
                pageCount: book.pageCount,
                updatedAt: book.updatedAt,
              ),
          ],
          device: pushedDevice,
        ),
      );
      // `content` may have gained edits while the BLE exchange was in flight;
      // merge is per-item newest-wins with tombstones (and keeps the local
      // wallpaperPath, which the device echo never carries), so both the
      // mid-flight edit and the device's changes survive.
      content = BizContent.merge(content, snapshot.content);
      final progressByFilename = {
        for (final item in snapshot.progress) item.filename: item,
      };
      // `books` may have advanced while the BLE exchange was in flight (a page
      // turned mid-sync is newer than both merge inputs); apply the merged
      // entry per book only when it is not older than the in-memory one.
      books = [
        for (final book in books)
          if (progressByFilename[book.remoteFilename] case final progress?
              when progress.updatedAt >= book.updatedAt)
            book.copyWith(
              progress: progress.percentage,
              chapterNumber: progress.spineIndex + 1,
              chapterProgress: progress.chapterProgressPercent,
              pageNumber: progress.pageNumber,
              pageCount: progress.pageCount,
              clearEpubCfi: progress.updatedAt > book.updatedAt,
              updatedAt: progress.updatedAt,
            )
          else
            book,
      ];
      // Echo sau sync_commit là trạng thái máy sau khi áp dụng: settings echo
      // thành bản gốc mới, SSID được xác nhận thì rút khỏi hàng đợi. Đối chiếu
      // trên deviceState hiện tại nên bản sửa trong lúc đồng bộ vẫn giữ nguyên.
      // Firmware cũ không trả `device` -> giữ nguyên hàng đợi cho lần sau.
      if (snapshot.device case final echo?) {
        deviceState = deviceState.reconcile(
          echo,
          pushedSettings: pushedDevice?.settings ?? const {},
          pushedWifiAdds: {
            for (final credential in pushedDevice?.wifiAdd ?? const [])
              credential.ssid,
          },
        );
        await _preferences.saveDeviceState(deviceState);
      }
      await _contentPreferences.save(content);
      await _bookLibrary.save(books);
      contentSyncMessage = content.sleepMode == BizSleepMode.photo
          ? 'Đã đồng bộ BLE; ảnh nền mới vẫn gửi bằng Wi-Fi'
          : 'Đã đồng bộ hai chiều qua BLE';
    } on Object catch (error) {
      contentSyncMessage = error.toString();
      rethrow;
    } finally {
      contentSyncing = false;
      notifyListeners();
    }
  }

  Future<void> sendWallpaperToDevice() async {
    final wallpaper = content.wallpaperPath;
    if (wallpaper == null || content.sleepMode != BizSleepMode.photo) {
      throw const FormatException('Hãy chọn ảnh nền trước.');
    }
    await _withTransferClient(
      (client) => client.uploadFile(
        remotePath: '/sleep.bmp',
        file: File(wallpaper),
        contentType: 'image/bmp',
      ),
    );
  }

  Future<LocalBook> importBook(File file, String originalFilename) async {
    var imported = await _bookLibrary.importEpub(file, originalFilename);
    final previousIndex = books.indexWhere((book) => book.id == imported.id);
    if (previousIndex >= 0) {
      final previous = books[previousIndex];
      imported = imported.copyWith(
        remoteFilename: previous.remoteFilename,
        progress: previous.progress,
        epubCfi: previous.epubCfi,
        chapterNumber: previous.chapterNumber,
        chapterProgress: previous.chapterProgress,
        pageNumber: previous.pageNumber,
        pageCount: previous.pageCount,
        updatedAt: previous.updatedAt,
      );
    } else {
      imported = imported.copyWith(
        remoteFilename: _uniqueRemoteFilename(imported),
      );
    }
    final updated = [
      ...books.where((book) => book.id != imported.id),
      imported,
    ];
    books = updated;
    await _bookLibrary.save(books);
    notifyListeners();
    return imported;
  }

  String _uniqueRemoteFilename(LocalBook imported) {
    final used = {
      for (final book in books.where((book) => book.id != imported.id))
        book.remoteFilename.toLowerCase(),
    };
    final original = imported.remoteFilename;
    if (!used.contains(original.toLowerCase())) return original;

    final dot = original.lastIndexOf('.');
    final stem = dot > 0 ? original.substring(0, dot) : original;
    final extension = dot > 0 ? original.substring(dot) : '';
    // Trim the stem so every candidate stays within the firmware's filename
    // byte budget; the suffix is ASCII, so trimming the stem never costs the
    // candidate the uniqueness the suffix provides.
    String candidateWith(String suffix) {
      final tail = '-$suffix$extension';
      final budget =
          BookLibraryService.maxRemoteFilenameBytes - utf8.encode(tail).length;
      return '${BookLibraryService.truncateUtf8(stem, budget)}$tail';
    }

    for (final length in const [8, 12, 16, 24, 32, 64]) {
      final suffixLength = length < imported.id.length
          ? length
          : imported.id.length;
      final candidate = candidateWith(imported.id.substring(0, suffixLength));
      if (!used.contains(candidate.toLowerCase())) return candidate;
    }
    return candidateWith(imported.id);
  }

  Future<void> openDocument(File file) => _fileViewer.open(file);

  Future<void> updateBookProgress(
    String bookId, {
    required double progress,
    required int chapterNumber,
    required double chapterProgress,
    int? pageNumber,
    int? pageCount,
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
            pageNumber: pageNumber?.clamp(0, 1 << 31).toInt(),
            pageCount: pageCount?.clamp(0, 1 << 31).toInt(),
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
      final percentage = (book.progress + 0.09).clamp(0, 1).toDouble();
      final pageCount = book.pageCount > 1 ? book.pageCount : 101;
      return DeviceReadingProgress(
        filename: book.remoteFilename,
        percentage: percentage,
        spineIndex: book.chapterNumber,
        pageNumber: (percentage * (pageCount - 1)).round(),
        pageCount: pageCount,
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
      chapterProgress: progress.chapterProgressPercent,
      pageNumber: progress.pageNumber,
      pageCount: progress.pageCount,
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

    transferSessionActive = true;
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

  Future<void> finishTransfer() async {
    try {
      await _bleClient.stopTransfer();
    } finally {
      transferSessionActive = false;
      if (device.usesBizTransfer) {
        device = DeviceConfig(
          name: device.name,
          host: device.host,
          bleId: device.bleId,
        );
        connectionState = DeviceConnectionState.unknown;
        connectionMessage = 'Phiên truyền đã đóng.';
        notifyListeners();
      }
    }
  }

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
    await _bleClient.stopTransfer();
    transferSessionActive = false;
    await _preferences.clear();
    device = const DeviceConfig(name: 'BizReader', host: '');
    deviceState = const BizDeviceState();
    connectionState = DeviceConnectionState.unknown;
    connectionMessage = null;
    notifyListeners();
  }
}
