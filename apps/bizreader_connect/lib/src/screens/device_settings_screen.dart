import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/biz_device_section.dart';
import '../services/biz_transfer_ble_client.dart';

class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  // Giới hạn của firmware (WifiCredentialStore::MAX_NETWORKS).
  static const _maxWifiNetworks = 8;

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.controller.device.name,
    );
    _hostController = TextEditingController(
      text: widget.controller.device.host,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    var success = await widget.controller.configure(
      widget.controller.device.copyWith(
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
      ),
      probe: !widget.controller.device.usesBizTransfer,
    );
    if (success && widget.controller.device.usesBizTransfer) {
      try {
        await widget.controller.prepareTransfer();
      } catch (_) {
        success = false;
      } finally {
        await widget.controller.finishTransfer();
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Đã cập nhật thiết bị.'
              : widget.controller.connectionMessage ??
                    'Không thể cập nhật thiết bị.',
        ),
      ),
    );
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa thiết bị?'),
        content: const Text(
          'Ứng dụng sẽ quên địa chỉ hiện tại. Dữ liệu trên thẻ nhớ không bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.forgetDevice();
    }
  }

  Future<void> _syncDeviceConfig() async {
    try {
      await widget.controller.syncContentToDevice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.controller.contentSyncMessage ?? 'Đã đồng bộ'),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => CustomScrollView(
          slivers: [
            const SliverAppBar(pinned: true, title: Text('Thiết bị')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.list(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.controller.device.usesBizTransfer
                                ? 'Bluetooth + Wi-Fi'
                                : 'Kết nối LAN / WebDAV',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 16),
                          if (widget.controller.device.usesBizTransfer) ...[
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.bluetooth_connected),
                              title: const Text('Đã lưu BizReader'),
                              subtitle: Text(
                                widget.controller.device.bleId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Tên thiết bị',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _hostController,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Địa chỉ',
                              hintText: 'http://192.168.4.1',
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Lưu và kiểm tra'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._deviceConfigSections(context),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.system_update_alt),
                          title: const Text('Cập nhật firmware'),
                          subtitle: const Text(
                            'Dùng chức năng OTA trên máy đọc',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showFirmwareHelp(context),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: const Text('Giới thiệu'),
                          subtitle: const Text('BizReader • Hoài Nguyễn'),
                          trailing: const Text('0.8.0'),
                          onTap: () => _showAbout(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!widget.controller.demoMode) ...[
                    OutlinedButton.icon(
                      onPressed: widget.controller.enterDemoMode,
                      icon: const Icon(Icons.slideshow_outlined),
                      label: const Text('Xem bản demo'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (widget.controller.demoMode)
                    OutlinedButton.icon(
                      onPressed: widget.controller.exitDemoMode,
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Thoát bản demo'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _forget,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Xóa liên kết thiết bị'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Cấu hình máy đọc qua BLE ---

  List<Widget> _deviceConfigSections(BuildContext context) {
    final state = widget.controller.deviceState;
    return [
      if (state.hasPendingChanges) ...[
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.sync_problem),
            title: Text('Chưa đồng bộ ${state.pendingCount} thay đổi'),
            subtitle: const Text('Kết nối máy để áp dụng'),
            trailing: widget.controller.contentSyncing
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: _syncDeviceConfig,
                    child: const Text('Đồng bộ'),
                  ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      _wifiCard(context, state),
      const SizedBox(height: 14),
      _deviceSettingsCard(context, state),
      const SizedBox(height: 14),
    ];
  }

  Widget _wifiCard(BuildContext context, BizDeviceState state) {
    final pendingAddSsids = {
      for (final credential in state.pendingWifiAdd) credential.ssid,
    };
    final deviceSsids = state.wifiSsids
        .where((ssid) => !pendingAddSsids.contains(ssid))
        .toList();
    final projectedCount =
        deviceSsids.where((s) => !state.pendingWifiRemove.contains(s)).length +
        state.pendingWifiAdd.length;
    final canAdd = projectedCount < _maxWifiNetworks;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            leading: Icon(Icons.wifi),
            title: Text(
              'Wi-Fi của máy đọc',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Tối đa $_maxWifiNetworks mạng • mật khẩu chỉ gửi '
              'xuống máy, không đọc lại được',
            ),
          ),
          if (deviceSsids.isEmpty && state.pendingWifiAdd.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Đồng bộ với máy đọc để xem danh sách Wi-Fi đã lưu.'),
            ),
          for (final ssid in deviceSsids)
            if (state.pendingWifiRemove.contains(ssid))
              ListTile(
                leading: const Icon(Icons.wifi_off),
                title: Text(
                  ssid,
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                subtitle: const Text('Chờ đồng bộ để xóa'),
                trailing: IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: 'Hủy xóa',
                  onPressed: () => widget.controller.cancelWifiRemove(ssid),
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.wifi),
                title: Text(ssid),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Xóa mạng này',
                  onPressed: () => widget.controller.queueWifiRemove(ssid),
                ),
              ),
          for (final credential in state.pendingWifiAdd)
            ListTile(
              leading: const Icon(Icons.wifi_find),
              title: Text(credential.ssid),
              subtitle: const Text('Chờ đồng bộ'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Hủy thêm',
                onPressed: () =>
                    widget.controller.cancelWifiAdd(credential.ssid),
              ),
            ),
          for (final credential in state.failedWifiAdds)
            ListTile(
              leading: Icon(
                Icons.wifi_tethering_error,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(credential.ssid),
              subtitle: const Text(
                'Máy từ chối — có thể đã đủ $_maxWifiNetworks mạng',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Thử lại',
                    onPressed: () =>
                        widget.controller.retryWifiAdd(credential.ssid),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Xoá',
                    onPressed: () =>
                        widget.controller.dismissFailedWifiAdd(credential.ssid),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          TextButton.icon(
            onPressed:
                canAdd &&
                    !widget.controller.contentSyncing &&
                    !widget.controller.wifiScanning
                ? _showWifiPicker
                : null,
            icon: const Icon(Icons.add),
            label: Text(
              canAdd
                  ? 'Thêm mạng Wi-Fi'
                  : 'Đã đạt tối đa $_maxWifiNetworks mạng',
            ),
          ),
        ],
      ),
    );
  }

  /// Mở bảng chọn mạng: máy đọc quét Wi-Fi quanh nó, người dùng chạm chọn.
  /// Quét lỗi/quá hạn (firmware cũ) thì tự quay về nhập thủ công kèm thông
  /// báo. Bảng chỉ trả kết quả; mọi bước sau chạy ở đây để giữ mounted-check
  /// một chỗ.
  Future<void> _showWifiPicker() async {
    final controller = widget.controller;
    final outcome = await showModalBottomSheet<_WifiPickOutcome>(
      context: context,
      showDragHandle: true,
      builder: (context) => _WifiPickerSheet(
        controller: controller,
        savedSsids: controller.deviceState.wifiSsids.toSet(),
      ),
    );
    if (!mounted || outcome == null) return;
    if (outcome.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(outcome.error!)));
      _showManualWifiDialog();
      return;
    }
    final network = outcome.network;
    if (network == null) {
      // Người dùng chọn "Nhập thủ công" (SSID ẩn).
      _showManualWifiDialog();
      return;
    }
    final saved = controller.deviceState.wifiSsids.contains(network.ssid);
    if (!network.secured && !saved) {
      // Mạng mở: không cần mật khẩu, xếp hàng chờ luôn.
      controller.queueWifiAdd(network.ssid, '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thêm mạng mở "${network.ssid}". Đồng bộ để áp dụng.',
          ),
        ),
      );
      return;
    }
    // Mạng có mật khẩu, hoặc mạng đã lưu trên máy -> hỏi (cập nhật) mật khẩu.
    showDialog<void>(
      context: context,
      builder: (context) => _AddWifiDialog(
        controller: controller,
        fixedSsid: network.ssid,
        updating: saved,
      ),
    );
  }

  void _showManualWifiDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _AddWifiDialog(controller: widget.controller),
    );
  }

  Widget _deviceSettingsCard(BuildContext context, BizDeviceState state) {
    final hasBase = state.settings.isNotEmpty;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            leading: Icon(Icons.tune),
            title: Text(
              'Cài đặt máy đọc',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('Thay đổi được áp dụng ở lần đồng bộ tới'),
          ),
          if (!hasBase)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Chưa có dữ liệu. Đồng bộ với máy đọc để tải cài đặt hiện tại.',
              ),
            )
          else ...[
            _settingDropdown(
              state: state,
              key: 'sleepTimeoutMinutes',
              title: 'Tự động ngủ sau',
              options: const [
                (1, '1 phút'),
                (2, '2 phút'),
                (3, '3 phút'),
                (5, '5 phút'),
                (10, '10 phút'),
                (15, '15 phút'),
                (20, '20 phút'),
                (30, '30 phút'),
                (31, 'Không bao giờ'),
              ],
            ),
            _settingDropdown(
              state: state,
              key: 'sleepScreen',
              title: 'Màn hình ngủ',
              options: const [
                (0, 'Tối'),
                (1, 'Sáng'),
                (2, 'Tùy chỉnh'),
                (3, 'Bìa sách'),
                (4, 'Bìa + tùy chỉnh'),
                (5, 'Trống'),
                (6, 'Tiếp tục nhanh'),
              ],
            ),
            _settingDropdown(
              state: state,
              key: 'uiTheme',
              title: 'Giao diện máy đọc',
              options: const [
                (0, 'Classic'),
                (1, 'Lyra'),
                (2, 'Lyra mở rộng'),
                (3, 'RoundedRaff'),
              ],
            ),
            _languageDropdown(state),
            _settingDropdown(
              state: state,
              key: 'fontSize',
              title: 'Cỡ chữ đọc sách',
              options: const [
                (0, 'Nhỏ'),
                (1, 'Vừa'),
                (2, 'Lớn'),
                (3, 'Rất lớn'),
              ],
            ),
            _settingDropdown(
              state: state,
              key: 'lineSpacing',
              title: 'Giãn dòng',
              options: const [(0, 'Sát'), (1, 'Thường'), (2, 'Rộng')],
            ),
            _settingDropdown(
              state: state,
              key: 'screenMargin',
              title: 'Lề trang sách',
              options: const [
                (5, '5'),
                (10, '10'),
                (15, '15'),
                (20, '20'),
                (25, '25'),
                (30, '30'),
                (35, '35'),
                (40, '40'),
              ],
            ),
            _settingDropdown(
              state: state,
              key: 'refreshFrequency',
              title: 'Làm mới màn hình e-ink',
              options: const [
                (0, 'Mỗi trang'),
                (1, 'Mỗi 5 trang'),
                (2, 'Mỗi 10 trang'),
                (3, 'Mỗi 15 trang'),
                (4, 'Mỗi 30 trang'),
              ],
            ),
            _settingDropdown(
              state: state,
              key: 'sideButtonLayout',
              title: 'Nút lật trang bên hông',
              options: const [
                (0, 'Trước / Sau'),
                (1, 'Sau / Trước'),
                (2, 'Tắt'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Một dòng cài đặt kiểu số (enum hoặc giá trị) với dropdown. Ẩn khi máy
  /// chưa gửi key này (khác đời firmware). Giá trị lạ ngoài danh sách vẫn
  /// hiển thị được để không tự ý đổi cài đặt trên máy.
  Widget _settingDropdown({
    required BizDeviceState state,
    required String key,
    required String title,
    required List<(int, String)> options,
  }) {
    if (!state.settings.containsKey(key)) return const SizedBox.shrink();
    // Không cast cứng: firmware trả sai kiểu thì ẩn dòng thay vì crash.
    final effective = state.effectiveSetting(key);
    final current = effective is num ? effective.toInt() : null;
    if (current == null) return const SizedBox.shrink();
    final known = options.any((option) => option.$1 == current);
    return ListTile(
      title: Text(title),
      subtitle: state.pendingSettings.containsKey(key)
          ? const Text('Chờ đồng bộ')
          : null,
      trailing: DropdownButton<int>(
        value: current,
        underline: const SizedBox.shrink(),
        alignment: AlignmentDirectional.centerEnd,
        items: [
          if (!known) DropdownMenuItem(value: current, child: Text('$current')),
          for (final (value, label) in options)
            DropdownMenuItem(value: value, child: Text(label)),
        ],
        onChanged: (value) {
          if (value != null) widget.controller.setDeviceSetting(key, value);
        },
      ),
    );
  }

  // Mã ngôn ngữ theo lib/I18n/translations (_language_code).
  static const _languages = [
    ('VI', 'Tiếng Việt'),
    ('EN', 'English'),
    ('BE', 'BE'),
    ('CA', 'CA'),
    ('CAV', 'CAV'),
    ('CS', 'CS'),
    ('DA', 'DA'),
    ('DE', 'DE'),
    ('ES', 'ES'),
    ('FI', 'FI'),
    ('FR', 'FR'),
    ('HE', 'HE'),
    ('HU', 'HU'),
    ('IT', 'IT'),
    ('KK', 'KK'),
    ('LT', 'LT'),
    ('NL', 'NL'),
    ('PL', 'PL'),
    ('PT', 'PT'),
    ('RO', 'RO'),
    ('RU', 'RU'),
    ('SI', 'SI'),
    ('SK', 'SK'),
    ('SV', 'SV'),
    ('TR', 'TR'),
    ('UK', 'UK'),
  ];

  Widget _languageDropdown(BizDeviceState state) {
    if (!state.settings.containsKey('language')) {
      return const SizedBox.shrink();
    }
    // Không cast cứng: firmware trả sai kiểu thì ẩn dòng thay vì crash.
    final effective = state.effectiveSetting('language');
    final current = effective is String ? effective : null;
    if (current == null) return const SizedBox.shrink();
    final known = _languages.any((language) => language.$1 == current);
    return ListTile(
      title: const Text('Ngôn ngữ máy đọc'),
      subtitle: state.pendingSettings.containsKey('language')
          ? const Text('Chờ đồng bộ')
          : null,
      trailing: DropdownButton<String>(
        value: current,
        underline: const SizedBox.shrink(),
        alignment: AlignmentDirectional.centerEnd,
        items: [
          if (!known) DropdownMenuItem(value: current, child: Text(current)),
          for (final (code, label) in _languages)
            DropdownMenuItem(value: code, child: Text(label)),
        ],
        onChanged: (value) {
          if (value != null) {
            widget.controller.setDeviceSetting('language', value);
          }
        },
      ),
    );
  }

  void _showFirmwareHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cập nhật firmware'),
        content: const Text(
          'Trên BizReader, mở Cài đặt > Hệ thống > Cập nhật OTA và làm theo '
          'hướng dẫn trên thiết bị.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'BizReader',
      applicationVersion: '0.8.0',
      applicationLegalese: 'Hoài Nguyễn',
      applicationIcon: Image.asset(
        'assets/branding/bizreader_logo.png',
        width: 52,
        height: 52,
      ),
    );
  }
}

/// Kết quả bảng chọn Wi-Fi: người dùng chọn một mạng, xin nhập thủ công,
/// hoặc quét thất bại (kèm thông báo). Đóng bảng không chọn gì -> null.
class _WifiPickOutcome {
  const _WifiPickOutcome.manual() : network = null, error = null;
  const _WifiPickOutcome.failed(this.error) : network = null;
  const _WifiPickOutcome.picked(BizWifiScanResult this.network) : error = null;

  final BizWifiScanResult? network;
  final String? error;
}

class _WifiPickerSheet extends StatefulWidget {
  const _WifiPickerSheet({required this.controller, required this.savedSsids});

  final AppController controller;
  final Set<String> savedSsids;

  @override
  State<_WifiPickerSheet> createState() => _WifiPickerSheetState();
}

class _WifiPickerSheetState extends State<_WifiPickerSheet> {
  List<BizWifiScanResult>? _results;

  @override
  void initState() {
    super.initState();
    // Sau khung hình đầu: scanDeviceWifi notifyListeners ngay (cờ bận),
    // gọi thẳng trong initState sẽ markNeedsBuild giữa lúc đang build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    try {
      final results = await widget.controller.scanDeviceWifi();
      if (!mounted) return;
      setState(() => _results = results);
    } on BizWifiScanUnsupportedException {
      if (!mounted) return;
      Navigator.pop(
        context,
        const _WifiPickOutcome.failed(
          'Máy không phản hồi quét Wi-Fi (firmware cũ hoặc quét thất bại) '
          '— nhập thủ công bên dưới.',
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      Navigator.pop(context, _WifiPickOutcome.failed(error.toString()));
    }
  }

  // Ngưỡng theo hợp đồng giao thức: >= -60 mạnh, >= -75 vừa, còn lại yếu.
  static IconData _signalIcon(int rssi) => rssi >= -60
      ? Icons.network_wifi
      : rssi >= -75
      ? Icons.network_wifi_2_bar
      : Icons.network_wifi_1_bar;

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            leading: Icon(Icons.wifi_find),
            title: Text(
              'Chọn mạng Wi-Fi',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('Danh sách do máy đọc quét quanh nó'),
          ),
          if (results == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Đang quét Wi-Fi quanh máy đọc…'),
                ],
              ),
            )
          else if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text('Máy đọc không tìm thấy mạng Wi-Fi nào gần nó.'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final network in results)
                    ListTile(
                      leading: Icon(_signalIcon(network.rssi)),
                      title: Text(
                        network.ssid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: widget.savedSsids.contains(network.ssid)
                          ? const Text('Đã lưu') // chạm để cập nhật mật khẩu
                          : null,
                      trailing: network.secured
                          ? const Icon(Icons.lock_outline, size: 18)
                          : null,
                      onTap: () => Navigator.pop(
                        context,
                        _WifiPickOutcome.picked(network),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          TextButton.icon(
            onPressed: () =>
                Navigator.pop(context, const _WifiPickOutcome.manual()),
            icon: const Icon(Icons.keyboard_outlined),
            label: const Text('Nhập thủ công'),
          ),
        ],
      ),
    );
  }
}

class _AddWifiDialog extends StatefulWidget {
  const _AddWifiDialog({
    required this.controller,
    this.fixedSsid,
    this.updating = false,
  });

  final AppController controller;

  /// SSID đã chọn từ bảng quét: khóa lại, chỉ hỏi mật khẩu.
  final String? fixedSsid;

  /// Mạng đã lưu trên máy đọc -> tiêu đề "cập nhật mật khẩu".
  final bool updating;

  @override
  State<_AddWifiDialog> createState() => _AddWifiDialogState();
}

class _AddWifiDialogState extends State<_AddWifiDialog> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = widget.fixedSsid ?? _ssidController.text.trim();
    final password = _passwordController.text;
    final ssidBytes = utf8.encode(ssid).length;
    if (ssidBytes < 1 || ssidBytes > 32) {
      setState(() => _error = 'Tên mạng (SSID) phải dài 1–32 byte.');
      return;
    }
    // Giới hạn WPA tính theo byte UTF-8, không phải ký tự.
    final passwordBytes = utf8.encode(password).length;
    if (passwordBytes != 0 && (passwordBytes < 8 || passwordBytes > 63)) {
      setState(
        () => _error =
            'Mật khẩu để trống (mạng mở) hoặc dài 8–63 byte '
            '(ký tự có dấu tính 2–3 byte).',
      );
      return;
    }
    // Không await trước khi pop để không dùng context sau await;
    // hàng đợi được lưu nền ngay sau đó.
    widget.controller.queueWifiAdd(ssid, password);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fixedSsid = widget.fixedSsid;
    return AlertDialog(
      title: Text(
        fixedSsid == null
            ? 'Thêm mạng Wi-Fi'
            : widget.updating
            ? 'Cập nhật mật khẩu "$fixedSsid"'
            : 'Kết nối "$fixedSsid"',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fixedSsid == null) ...[
            TextField(
              controller: _ssidController,
              autofocus: true,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Tên mạng (SSID)'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _passwordController,
            autofocus: fixedSsid != null,
            obscureText: !_showPassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Mật khẩu (trống nếu mạng mở)',
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.updating ? 'Cập nhật' : 'Thêm'),
        ),
      ],
    );
  }
}
