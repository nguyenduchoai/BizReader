import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/device_config.dart';

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  bool _saveOffline = false;

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

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập địa chỉ hiển thị trên BizReader.')),
      );
      return;
    }

    final device = DeviceConfig(
      name: _nameController.text.trim().isEmpty
          ? 'BizReader'
          : _nameController.text.trim(),
      host: host,
    );
    final connected = await widget.controller.configure(
      device,
      probe: !_saveOffline,
    );
    if (!mounted || connected) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.controller.connectionMessage ?? 'Không thể kết nối thiết bị.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checking =
        widget.controller.connectionState == DeviceConnectionState.checking;
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm thiết bị')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DeviceIllustration(),
                  const SizedBox(height: 28),
                  Text(
                    'Kết nối BizReader',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Trên máy đọc, mở Truyền tệp, chọn Kết nối Wi-Fi hoặc '
                    'Tạo điểm phát rồi nhập địa chỉ đang hiển thị.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5C626B),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Tên thiết bị',
                      prefixIcon: Icon(Icons.tablet_android_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _hostController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    onSubmitted: checking ? null : (_) => _connect(),
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ thiết bị',
                      hintText: 'http://192.168.4.1',
                      prefixIcon: Icon(Icons.lan_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _saveOffline,
                    onChanged: checking
                        ? null
                        : (value) =>
                              setState(() => _saveOffline = value ?? false),
                    title: const Text('Lưu trước, kiểm tra sau'),
                    subtitle: const Text(
                      'Dùng khi máy đọc chưa bật chế độ Truyền tệp.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: checking ? null : _connect,
                    icon: checking
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                      checking ? 'Đang kiểm tra' : 'Kết nối thiết bị',
                    ),
                  ),
                ],
              ),
            ),
          ),
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
