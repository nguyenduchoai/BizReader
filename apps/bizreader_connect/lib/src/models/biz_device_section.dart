/// Mật khẩu Wi-Fi gửi xuống máy đọc. Máy không bao giờ trả mật khẩu về app.
class BizWifiCredential {
  const BizWifiCredential({required this.ssid, this.password = ''});

  final String ssid;
  final String password;

  Map<String, Object?> toJson() => {'ssid': ssid, 'password': password};

  factory BizWifiCredential.fromJson(Map<String, Object?> json) =>
      BizWifiCredential(
        ssid: json['ssid'] as String? ?? '',
        password: json['password'] as String? ?? '',
      );
}

/// Một mạng Wi-Fi máy đọc quét được (op `wifi_scan`). Chỉ có chiều pull;
/// firmware trả tối đa 15 mục, mạnh nhất trước.
class BizWifiScanResult {
  const BizWifiScanResult({
    required this.ssid,
    this.rssi = 0,
    this.secured = false,
  });

  final String ssid;
  final int rssi;

  /// `sec` trong JSON: mạng có mật khẩu.
  final bool secured;

  factory BizWifiScanResult.fromJson(Map<String, Object?> json) {
    final sec = json['sec'];
    return BizWifiScanResult(
      ssid: json['ssid'] as String? ?? '',
      rssi: (json['rssi'] as num?)?.toInt() ?? 0,
      secured: sec == true || (sec is num && sec != 0),
    );
  }
}

/// Phần `device` trong snapshot đồng bộ BLE (protocol 2).
///
/// Chiều pull (máy -> app): `settings` + `wifiSsids` (+ `wifiScan` khi vừa
/// quét xong).
/// Chiều push (app -> máy): `settings` + `wifiAdd` + `wifiRemove`,
/// key nào rỗng thì bỏ hẳn khỏi JSON.
///
/// `settings` là object phẳng do JsonSettingsIO của firmware định nghĩa —
/// app chỉ sửa các key nó hiểu, mọi key lạ được giữ nguyên khi push.
class BizDeviceSection {
  const BizDeviceSection({
    this.settings = const {},
    this.wifiSsids = const [],
    this.wifiScan = const [],
    this.wifiAdd = const [],
    this.wifiRemove = const [],
  });

  final Map<String, Object?> settings;
  final List<String> wifiSsids;

  /// Kết quả quét Wi-Fi gần nhất — chỉ có ở chiều pull, không bao giờ push.
  final List<BizWifiScanResult> wifiScan;
  final List<BizWifiCredential> wifiAdd;
  final List<String> wifiRemove;

  int? settingInt(String key) => (settings[key] as num?)?.toInt();
  String? settingString(String key) => settings[key] as String?;

  bool get hasPushPayload =>
      settings.isNotEmpty || wifiAdd.isNotEmpty || wifiRemove.isNotEmpty;

  /// Dạng push (app -> máy).
  Map<String, Object?> toJson() => {
    if (settings.isNotEmpty) 'settings': settings,
    if (wifiAdd.isNotEmpty)
      'wifiAdd': [for (final credential in wifiAdd) credential.toJson()],
    if (wifiRemove.isNotEmpty) 'wifiRemove': wifiRemove,
  };

  /// Dạng pull (máy -> app).
  factory BizDeviceSection.fromJson(Map<String, Object?> json) {
    final settings = json['settings'];
    final ssids = json['wifiSsids'];
    final scan = json['wifiScan'];
    return BizDeviceSection(
      settings: settings is Map ? settings.cast<String, Object?>() : const {},
      wifiSsids: ssids is List
          ? ssids.whereType<String>().toList(growable: false)
          : const [],
      wifiScan: scan is List
          ? scan
                .whereType<Map>()
                .map(
                  (item) =>
                      BizWifiScanResult.fromJson(item.cast<String, Object?>()),
                )
                .where((result) => result.ssid.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }

  /// Ghép phần push: phủ các key người dùng đã sửa lên object settings vừa
  /// pull được từ máy, để không làm mất key lạ và không ghi đè thay đổi
  /// thực hiện trực tiếp trên máy với giá trị cũ. Trả về null (bỏ `device`
  /// khỏi snapshot) khi không có gì chờ đồng bộ.
  static BizDeviceSection? mergeForPush(
    BizDeviceSection? pending,
    BizDeviceSection? remote,
  ) {
    if (pending == null || !pending.hasPushPayload) return null;
    return BizDeviceSection(
      settings: pending.settings.isEmpty
          ? const {}
          : {...?remote?.settings, ...pending.settings},
      wifiAdd: pending.wifiAdd,
      wifiRemove: pending.wifiRemove,
    );
  }
}

/// Trạng thái cấu hình máy đọc phía app: bản pull gần nhất + hàng đợi
/// thay đổi chưa đồng bộ (sống sót qua khởi động lại app).
class BizDeviceState {
  const BizDeviceState({
    this.settings = const {},
    this.wifiSsids = const [],
    this.pendingSettings = const {},
    this.pendingWifiAdd = const [],
    this.pendingWifiRemove = const [],
    this.failedWifiAdds = const [],
  });

  /// Settings phẳng từ lần pull gần nhất (passthrough).
  final Map<String, Object?> settings;
  final List<String> wifiSsids;

  /// Chỉ chứa các key người dùng đã sửa trong app.
  final Map<String, Object?> pendingSettings;
  final List<BizWifiCredential> pendingWifiAdd;
  final List<String> pendingWifiRemove;

  /// Mạng đã push nhưng máy từ chối (vd đã đủ 8 mạng). Không tự push lại;
  /// người dùng "Thử lại" (về hàng đợi) hoặc "Xoá".
  final List<BizWifiCredential> failedWifiAdds;

  bool get hasPendingChanges =>
      pendingSettings.isNotEmpty ||
      pendingWifiAdd.isNotEmpty ||
      pendingWifiRemove.isNotEmpty;

  int get pendingCount =>
      pendingSettings.length + pendingWifiAdd.length + pendingWifiRemove.length;

  /// Giá trị hiển thị: bản sửa đang chờ nếu có, không thì giá trị máy.
  Object? effectiveSetting(String key) =>
      pendingSettings.containsKey(key) ? pendingSettings[key] : settings[key];

  /// Phần `device` để đưa vào snapshot push; null khi không có gì chờ.
  BizDeviceSection? toPushSection() => hasPendingChanges
      ? BizDeviceSection(
          settings: pendingSettings,
          wifiAdd: pendingWifiAdd,
          wifiRemove: pendingWifiRemove,
        )
      : null;

  /// Đối chiếu echo sau sync_commit:
  /// - SSID chờ thêm đã xuất hiện trong echo -> bỏ khỏi hàng đợi.
  /// - SSID chờ thêm đã push nhưng vắng mặt trong echo -> máy từ chối
  ///   (vd đã đủ 8 mạng), chuyển sang [failedWifiAdds] chờ người dùng xử lý.
  ///   SSID chưa kịp push (xếp hàng trong lúc đồng bộ) vẫn chờ tiếp.
  /// - SSID chờ xóa đã biến mất khỏi echo -> bỏ khỏi hàng đợi.
  /// - Settings trong echo trở thành bản gốc mới; key đã push xong được xóa
  ///   khỏi hàng đợi, trừ khi người dùng sửa tiếp trong lúc đang đồng bộ
  ///   (giá trị chờ khác giá trị đã push thì giữ lại).
  BizDeviceState reconcile(
    BizDeviceSection echo, {
    Map<String, Object?> pushedSettings = const {},
    Set<String> pushedWifiAdds = const {},
  }) {
    final echoSsids = echo.wifiSsids.toSet();
    final nextPendingSettings = Map<String, Object?>.of(pendingSettings);
    if (echo.settings.isNotEmpty) {
      nextPendingSettings.removeWhere(
        (key, value) =>
            pushedSettings.containsKey(key) && pushedSettings[key] == value,
      );
    }
    final rejected = pendingWifiAdd
        .where(
          (credential) =>
              !echoSsids.contains(credential.ssid) &&
              pushedWifiAdds.contains(credential.ssid),
        )
        .toList(growable: false);
    final rejectedSsids = {for (final credential in rejected) credential.ssid};
    return BizDeviceState(
      settings: echo.settings.isNotEmpty ? echo.settings : settings,
      wifiSsids: echo.wifiSsids,
      pendingSettings: nextPendingSettings,
      pendingWifiAdd: pendingWifiAdd
          .where(
            (credential) =>
                !echoSsids.contains(credential.ssid) &&
                !rejectedSsids.contains(credential.ssid),
          )
          .toList(growable: false),
      pendingWifiRemove: pendingWifiRemove
          .where(echoSsids.contains)
          .toList(growable: false),
      failedWifiAdds: [
        // Mạng từng bị từ chối nay đã có trên máy (thêm tay trên máy) hoặc
        // vừa bị từ chối lại với thông tin mới hơn -> thay bằng bản mới.
        ...failedWifiAdds.where(
          (credential) =>
              !echoSsids.contains(credential.ssid) &&
              !rejectedSsids.contains(credential.ssid),
        ),
        ...rejected,
      ],
    );
  }

  BizDeviceState copyWith({
    Map<String, Object?>? settings,
    List<String>? wifiSsids,
    Map<String, Object?>? pendingSettings,
    List<BizWifiCredential>? pendingWifiAdd,
    List<String>? pendingWifiRemove,
    List<BizWifiCredential>? failedWifiAdds,
  }) {
    return BizDeviceState(
      settings: settings ?? this.settings,
      wifiSsids: wifiSsids ?? this.wifiSsids,
      pendingSettings: pendingSettings ?? this.pendingSettings,
      pendingWifiAdd: pendingWifiAdd ?? this.pendingWifiAdd,
      pendingWifiRemove: pendingWifiRemove ?? this.pendingWifiRemove,
      failedWifiAdds: failedWifiAdds ?? this.failedWifiAdds,
    );
  }

  /// Lưu trữ cục bộ (shared_preferences), không phải dạng gửi qua BLE.
  Map<String, Object?> toJson() => {
    'settings': settings,
    'wifiSsids': wifiSsids,
    'pendingSettings': pendingSettings,
    'pendingWifiAdd': [
      for (final credential in pendingWifiAdd) credential.toJson(),
    ],
    'pendingWifiRemove': pendingWifiRemove,
    'failedWifiAdds': [
      for (final credential in failedWifiAdds) credential.toJson(),
    ],
  };

  factory BizDeviceState.fromJson(Map<String, Object?> json) {
    Map<String, Object?> mapOf(Object? value) =>
        value is Map ? value.cast<String, Object?>() : const {};
    List<String> stringsOf(Object? value) => value is List
        ? value.whereType<String>().toList(growable: false)
        : const [];
    List<BizWifiCredential> credentialsOf(Object? value) => value is List
        ? value
              .whereType<Map>()
              .map(
                (item) =>
                    BizWifiCredential.fromJson(item.cast<String, Object?>()),
              )
              .where((credential) => credential.ssid.isNotEmpty)
              .toList(growable: false)
        : const [];
    return BizDeviceState(
      settings: mapOf(json['settings']),
      wifiSsids: stringsOf(json['wifiSsids']),
      pendingSettings: mapOf(json['pendingSettings']),
      pendingWifiAdd: credentialsOf(json['pendingWifiAdd']),
      pendingWifiRemove: stringsOf(json['pendingWifiRemove']),
      failedWifiAdds: credentialsOf(json['failedWifiAdds']),
    );
  }
}
