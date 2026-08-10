import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/book_library_service.dart';
import '../services/universal_file_viewer.dart';
import 'content_hub_screen.dart';
import 'reader_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.openLibrary,
    required this.openDevice,
  });

  final AppController controller;
  final VoidCallback openLibrary;
  final VoidCallback openDevice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(controller.device.name),
                const SizedBox(height: 2),
                _ConnectionLabel(
                  state: controller.connectionState,
                  configured: controller.device.isConfigured,
                ),
              ],
            ),
            actions: [
              if (controller.device.isConfigured)
                IconButton(
                  onPressed: controller.checkConnection,
                  tooltip: 'Kiểm tra kết nối',
                  icon: const Icon(Icons.sync),
                )
              else
                IconButton(
                  onPressed: openDevice,
                  tooltip: 'Thêm thiết bị',
                  icon: const Icon(Icons.add_link),
                ),
              const SizedBox(width: 8),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList.list(
              children: [
                _ScreenPreview(deviceName: controller.device.name),
                const SizedBox(height: 24),
                Text(
                  'Ứng dụng thiết bị',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 700 ? 3 : 2;
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.35,
                      children: [
                        _AppTile(
                          icon: Icons.menu_book_outlined,
                          title: 'Sách',
                          value: 'Đọc và đồng bộ',
                          tint: const Color(0xFFEAF2EE),
                          onTap: openLibrary,
                        ),
                        _AppTile(
                          icon: Icons.note_alt_outlined,
                          title: 'Ghi chú',
                          value: 'Đồng bộ nội dung',
                          tint: const Color(0xFFF2EDF7),
                          onTap: () => _openContent(context, 0),
                        ),
                        _AppTile(
                          icon: Icons.checklist,
                          title: 'Việc cần làm',
                          value: 'Đồng bộ xuống máy',
                          tint: const Color(0xFFF7F0E8),
                          onTap: () => _openContent(context, 1),
                        ),
                        _AppTile(
                          icon: Icons.calendar_month_outlined,
                          title: 'Lịch',
                          value: 'Lịch và nhắc việc',
                          tint: const Color(0xFFE8F1F7),
                          onTap: () => _openContent(context, 2),
                        ),
                        _AppTile(
                          icon: Icons.cloud_outlined,
                          title: 'Thời tiết',
                          value: 'Theo vị trí',
                          tint: const Color(0xFFEAF5F5),
                          onTap: () => _openContent(context, 3),
                        ),
                        _AppTile(
                          icon: Icons.photo_outlined,
                          title: 'Ảnh và nền nghỉ',
                          value: '960 x 540',
                          tint: const Color(0xFFF6ECEC),
                          onTap: () => _openContent(context, 4),
                        ),
                        _AppTile(
                          icon: Icons.folder_open_outlined,
                          title: 'Tệp đa định dạng',
                          value: 'PDF · Office · media',
                          tint: const Color(0xFFEEF0F3),
                          onTap: () => _pickAndOpenFile(context),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openContent(BuildContext context, int tab) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ContentHubScreen(controller: controller, initialTab: tab),
        ),
      );

  Future<void> _pickAndOpenFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;

    final selected = result.files.single;
    final file = File(selected.path!);
    final extension = (selected.extension ?? selected.name.split('.').last)
        .toLowerCase();
    try {
      if (extension == 'epub') {
        final book = await controller.importBook(file, selected.name);
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(controller: controller, book: book),
          ),
        );
      } else {
        await controller.openDocument(file);
      }
    } on BookImportException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on UniversalFileViewerException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ConnectionLabel extends StatelessWidget {
  const _ConnectionLabel({required this.state, required this.configured});

  final DeviceConnectionState state;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final (label, color) = !configured
        ? ('Chưa thêm thiết bị', const Color(0xFF68707B))
        : switch (state) {
            DeviceConnectionState.online => (
              'Đang kết nối',
              const Color(0xFF2F7D4C),
            ),
            DeviceConnectionState.offline => (
              'Ngoại tuyến',
              const Color(0xFF9A3F35),
            ),
            DeviceConnectionState.checking => (
              'Đang kiểm tra',
              const Color(0xFF8B651D),
            ),
            DeviceConnectionState.unknown => (
              'Chưa kiểm tra',
              const Color(0xFF68707B),
            ),
          };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ScreenPreview extends StatelessWidget {
  const _ScreenPreview({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const weekdays = [
      'Thứ hai',
      'Thứ ba',
      'Thứ tư',
      'Thứ năm',
      'Thứ sáu',
      'Thứ bảy',
      'Chủ nhật',
    ];
    final date =
        '${weekdays[now.weekday - 1]}, ${now.day}/${now.month}/${now.year}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Màn hình nghỉ',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: 960 / 540,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFBFBF8),
                  border: Border.all(color: const Color(0xFF17191C), width: 2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              deviceName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Icon(Icons.battery_5_bar, size: 18),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '${now.day}',
                        style: const TextStyle(
                          fontSize: 42,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const Divider(height: 1, color: Color(0xFF17191C)),
                      const SizedBox(height: 8),
                      const Text('Hoài Nguyễn', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: tint,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 23),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5C626B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
