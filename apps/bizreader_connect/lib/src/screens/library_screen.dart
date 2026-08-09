import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/webdav_device_client.dart';

enum TransferStatus { waiting, preparing, uploading, done, failed }

class TransferItem {
  TransferItem(this.name);

  final String name;
  TransferStatus status = TransferStatus.waiting;
  String? message;
  double progress = 0;
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final List<TransferItem> _transfers = [];
  bool _busy = false;

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['epub', 'txt', 'xtc', 'xtch', 'bmp'],
    );
    if (result == null || result.files.isEmpty) return;

    final usable = result.files.where((file) => file.path != null).toList();
    if (!mounted) return;
    if (usable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được tệp đã chọn.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _transfers
        ..clear()
        ..addAll(usable.map((file) => TransferItem(file.name)));
    });

    WebDavDeviceClient? client;
    try {
      final device = await widget.controller.prepareTransfer();
      client = WebDavDeviceClient(device);
      await client.probe();
      await client.ensureDirectory('/Ebook');
      for (var index = 0; index < usable.length; index++) {
        final selected = usable[index];
        final item = _transfers[index];
        setState(() => item.status = TransferStatus.preparing);
        try {
          await client.uploadFile(
            remotePath: '/Ebook/${selected.name}',
            file: File(selected.path!),
            contentType: _contentType(selected.extension),
            onProgress: (sent, total) {
              if (!mounted) return;
              setState(() {
                item.status = TransferStatus.uploading;
                item.progress = total == 0 ? 0 : sent / total;
              });
            },
          );
          setState(() => item.status = TransferStatus.done);
        } on DeviceConnectionException catch (error) {
          setState(() {
            item.status = TransferStatus.failed;
            item.message = error.message;
          });
        }
      }
      if (mounted) {
        final success = _transfers
            .where((item) => item.status == TransferStatus.done)
            .length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã gửi $success/${_transfers.length} tệp.')),
        );
      }
    } on DeviceConnectionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      client?.close();
      if (widget.controller.device.usesBizTransfer) {
        await widget.controller.finishTransfer();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  String _contentType(String? extension) {
    return switch (extension?.toLowerCase()) {
      'epub' => 'application/epub+zip',
      'txt' => 'text/plain',
      'bmp' => 'image/bmp',
      _ => 'application/octet-stream',
    };
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(pinned: true, title: Text('Thư viện')),
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
                        const Row(
                          children: [
                            Icon(Icons.sd_card_outlined),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Thư mục /Ebook trên thẻ nhớ',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.controller.device.usesBizTransfer
                              ? 'Hỗ trợ EPUB, TXT, XTC, XTCH và BMP. App sẽ tự '
                                    'mở Wi-Fi trên BizReader trước khi gửi.'
                              : 'Hỗ trợ EPUB, TXT, XTC, XTCH và BMP. Máy đọc '
                                    'phải đang mở Truyền tệp và điện thoại ở cùng mạng.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _pickAndUpload,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(_busy ? 'Đang gửi' : 'Chọn sách để gửi'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_transfers.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'Lần truyền gần nhất',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < _transfers.length;
                          index++
                        ) ...[
                          _TransferRow(item: _transfers[index]),
                          if (index != _transfers.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (item.status) {
      TransferStatus.waiting => (
        Icons.schedule,
        const Color(0xFF68707B),
        'Đang chờ',
      ),
      TransferStatus.preparing => (
        Icons.fingerprint,
        const Color(0xFF356A8A),
        'Đang kiểm tra tệp',
      ),
      TransferStatus.uploading => (
        Icons.sync,
        const Color(0xFF8B651D),
        'Đang gửi ${(item.progress * 100).round()}%',
      ),
      TransferStatus.done => (
        Icons.check_circle,
        const Color(0xFF2F7D4C),
        'Hoàn tất',
      ),
      TransferStatus.failed => (
        Icons.error,
        const Color(0xFF9A3F35),
        item.message ?? 'Thất bại',
      ),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
