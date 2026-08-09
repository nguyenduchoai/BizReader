import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/biz_transfer_status.dart';
import '../models/device_config.dart';
import '../services/biz_transfer_ble_client.dart';

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  final Map<String, BizReaderBleDevice> _devices = {};
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  StreamSubscription<BizReaderBleDevice>? _scanSubscription;
  Timer? _scanTimer;
  bool _scanning = false;
  bool _connecting = false;
  String? _message;

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
    _scanSubscription?.cancel();
    _scanTimer?.cancel();
    _nameController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    await _scanSubscription?.cancel();
    _scanTimer?.cancel();
    setState(() {
      _devices.clear();
      _scanning = true;
      _message = 'Đang tìm BizReader ở gần...';
    });

    _scanSubscription = widget.controller.scanBizReaders().listen(
      (device) {
        if (!mounted) return;
        setState(() {
          _devices[device.id] = device;
          _message = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _message = error is BizTransferException
              ? error.message
              : 'Không thể quét Bluetooth: $error';
        });
      },
    );
    _scanTimer = Timer(const Duration(seconds: 12), _stopScan);
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _selectDevice(BizReaderBleDevice device) async {
    await _stopScan();
    setState(() {
      _connecting = true;
      _message = 'Kiểm tra mã ghép đôi trên màn hình BizReader.';
    });
    try {
      await widget.controller.pairDevice(device);
    } on BizTransferException catch (error) {
      if (!mounted) return;
      final canRetryWifi =
          error.message == 'Chưa có Wi-Fi đã lưu' ||
          error.message == 'Không kết nối được Wi-Fi';
      if (!canRetryWifi) {
        setState(() {
          _connecting = false;
          _message = error.message;
        });
        return;
      }
      final credentials = await _askWifiCredentials();
      if (credentials == null) {
        setState(() {
          _connecting = false;
          _message = widget.controller.connectionMessage;
        });
        return;
      }
      try {
        await widget.controller.pairDevice(
          device,
          ssid: credentials.$1,
          password: credentials.$2,
        );
      } on BizTransferException catch (error) {
        if (mounted) {
          setState(() {
            _connecting = false;
            _message = error.message;
          });
        }
      }
    }
  }

  Future<(String, String)?> _askWifiCredentials() async {
    final ssidController = TextEditingController();
    final passwordController = TextEditingController();
    var obscurePassword = true;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kết nối Wi-Fi lần đầu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nhập Wi-Fi 2.4 GHz mà điện thoại và BizReader sẽ cùng sử dụng.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ssidController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Tên Wi-Fi (SSID)',
                  prefixIcon: Icon(Icons.wifi),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                onSubmitted: (_) {
                  final ssid = ssidController.text.trim();
                  if (ssid.isNotEmpty) {
                    Navigator.pop(context, (ssid, passwordController.text));
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: () => setDialogState(
                      () => obscurePassword = !obscurePassword,
                    ),
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final ssid = ssidController.text.trim();
                if (ssid.isNotEmpty) {
                  Navigator.pop(context, (ssid, passwordController.text));
                }
              },
              child: const Text('Kết nối'),
            ),
          ],
        ),
      ),
    );
    ssidController.dispose();
    passwordController.dispose();
    return result;
  }

  Future<void> _connectManual() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      setState(() => _message = 'Nhập địa chỉ WebDAV của BizReader.');
      return;
    }
    setState(() => _connecting = true);
    final connected = await widget.controller.configure(
      DeviceConfig(
        name: _nameController.text.trim().isEmpty
            ? 'BizReader'
            : _nameController.text.trim(),
        host: host,
      ),
    );
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _message = connected ? null : widget.controller.connectionMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm thiết bị')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const _DeviceIllustration(),
            const SizedBox(height: 22),
            Text(
              'Kết nối BizReader',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Để máy đọc đang thức. App sẽ ghép đôi bằng Bluetooth, mở Wi-Fi '
              'tạm thời và gửi sách thẳng vào thẻ nhớ.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _connecting
                  ? null
                  : _scanning
                  ? _stopScan
                  : _startScan,
              icon: _connecting || _scanning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Dừng tìm kiếm' : 'Tìm BizReader'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_devices.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Thiết bị tìm thấy',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final (index, device) in _devices.values.indexed) ...[
                      ListTile(
                        leading: const Icon(Icons.auto_stories_outlined),
                        title: Text(device.name),
                        subtitle: Text(
                          device.rssi >= -65
                              ? 'Tín hiệu tốt'
                              : device.rssi >= -80
                              ? 'Tín hiệu trung bình'
                              : 'Tín hiệu yếu',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _connecting ? null : () => _selectDevice(device),
                      ),
                      if (index != _devices.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.lan_outlined),
              title: const Text('Kết nối WebDAV thủ công'),
              subtitle: const Text('Phương án dự phòng'),
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Tên thiết bị'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hostController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ',
                    hintText: 'http://192.168.4.1',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _connecting ? null : _connectManual,
                  icon: const Icon(Icons.link),
                  label: const Text('Kết nối WebDAV'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceIllustration extends StatelessWidget {
  const _DeviceIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 230,
        height: 155,
        child: CustomPaint(painter: _EpaperPainter()),
      ),
    );
  }
}

class _EpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xFF17191C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final device = RRect.fromRectAndRadius(
      Rect.fromLTWH(15, 10, size.width - 30, size.height - 24),
      const Radius.circular(8),
    );
    canvas.drawRRect(device, ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(30, 25, size.width - 60, size.height - 54),
        const Radius.circular(2),
      ),
      ink..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(size.width - 14, 48),
      Offset(size.width - 14, 80),
      ink..strokeWidth = 4,
    );
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'BizReader',
        style: TextStyle(
          color: Color(0xFF17191C),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2 - 5,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
