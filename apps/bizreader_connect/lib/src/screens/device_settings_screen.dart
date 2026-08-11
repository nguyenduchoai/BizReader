import 'package:flutter/material.dart';

import '../app_controller.dart';

class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
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
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.system_update_alt),
                        title: const Text('Cập nhật firmware'),
                        subtitle: const Text('Dùng chức năng OTA trên máy đọc'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showFirmwareHelp(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Giới thiệu'),
                        subtitle: const Text('BizReader • Hoài Nguyễn'),
                        trailing: const Text('0.6.0'),
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
    );
  }

  void _showFirmwareHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cập nhật firmware'),
        content: const Text(
          'Trên BizReader, mở Cài đặt > Hệ thống > Cập nhật OTA. '
          'Ứng dụng sẽ tích hợp kiểm tra và kích hoạt OTA sau khi BizSync '
          'được thêm vào firmware.',
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
}
