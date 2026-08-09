import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/local_book.dart';
import '../models/device_reading_progress.dart';
import '../services/book_library_service.dart';
import '../services/webdav_device_client.dart';
import 'reader_screen.dart';

enum TransferStatus { waiting, preparing, uploading, done, failed }

enum _SyncChoice { phone, device }

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
  bool _importing = false;
  String? _syncingBookId;

  Future<void> _pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['epub'],
    );
    if (result == null || result.files.isEmpty) return;
    final usable = result.files.where((file) => file.path != null).toList();
    if (!mounted || usable.isEmpty) return;

    setState(() => _importing = true);
    var imported = 0;
    String? errorMessage;
    for (final selected in usable) {
      try {
        await widget.controller.importBook(File(selected.path!), selected.name);
        imported++;
      } on BookImportException catch (error) {
        errorMessage = error.message;
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          imported > 0
              ? 'Đã thêm $imported sách vào thư viện.'
              : errorMessage ?? 'Không thể thêm sách.',
        ),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['epub', 'txt', 'xtc', 'xtch', 'bmp'],
    );
    if (result == null || result.files.isEmpty) return;
    final usable = result.files.where((file) => file.path != null).toList();
    await _uploadFiles([
      for (final selected in usable)
        (
          name: selected.name,
          file: File(selected.path!),
          extension: selected.extension,
        ),
    ]);
  }

  Future<void> _uploadBook(LocalBook book) async {
    if (book.demo) {
      _showMessage('Sách mẫu chỉ dùng để trình diễn giao diện.');
      return;
    }
    await _uploadFiles([
      (name: book.remoteFilename, file: File(book.filePath), extension: 'epub'),
    ]);
  }

  Future<void> _uploadFiles(
    List<({String name, File file, String? extension})> files,
  ) async {
    if (files.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _transfers
        ..clear()
        ..addAll(files.map((file) => TransferItem(file.name)));
    });

    WebDavDeviceClient? client;
    try {
      final device = await widget.controller.prepareTransfer();
      client = WebDavDeviceClient(device);
      await client.probe();
      await client.ensureDirectory('/Ebook');
      for (var index = 0; index < files.length; index++) {
        final selected = files[index];
        final item = _transfers[index];
        setState(() => item.status = TransferStatus.preparing);
        try {
          await client.uploadFile(
            remotePath: '/Ebook/${selected.name}',
            file: selected.file,
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
        _showMessage('Đã gửi $success/${_transfers.length} tệp.');
      }
    } on DeviceConnectionException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } finally {
      client?.close();
      if (widget.controller.device.usesBizTransfer) {
        await widget.controller.finishTransfer();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBook(LocalBook book) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(controller: widget.controller, book: book),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _syncBook(LocalBook book) async {
    if (_syncingBookId != null) return;
    setState(() => _syncingBookId = book.id);
    try {
      final deviceProgress = await widget.controller.fetchDeviceProgress(book);
      if (!mounted) return;
      if (deviceProgress == null) {
        final shouldPush = await _confirmFirstProgress(book);
        if (shouldPush == true) {
          await widget.controller.pushProgressToDevice(book);
          if (mounted) {
            _showMessage('Đã gửi vị trí đọc sang BizReader.');
          }
        }
        return;
      }

      if ((deviceProgress.percentage - book.progress).abs() < 0.005) {
        _showMessage('Vị trí đọc đã đồng bộ.');
        return;
      }

      final choice = await _chooseProgress(book, deviceProgress);
      if (choice == _SyncChoice.phone) {
        await widget.controller.pushProgressToDevice(book);
        if (mounted) _showMessage('BizReader sẽ mở tại vị trí điện thoại.');
      } else if (choice == _SyncChoice.device) {
        await widget.controller.useDeviceProgress(book, deviceProgress);
        if (mounted) _showMessage('Đã dùng vị trí đọc từ BizReader.');
      }
    } on DeviceConnectionException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _syncingBookId = null);
    }
  }

  Future<_SyncChoice?> _chooseProgress(
    LocalBook book,
    DeviceReadingProgress deviceProgress,
  ) {
    String percent(double value) => '${(value * 100).round()}%';
    return showDialog<_SyncChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chọn vị trí đọc'),
        content: const Text(
          'Hai thiết bị đang ở vị trí khác nhau. Chọn vị trí muốn giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, _SyncChoice.device),
            child: Text('BizReader • ${percent(deviceProgress.percentage)}'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _SyncChoice.phone),
            child: Text('Điện thoại • ${percent(book.progress)}'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmFirstProgress(LocalBook book) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chưa có vị trí trên BizReader'),
        content: Text(
          'Gửi vị trí ${(book.progress * 100).round()}% từ điện thoại sang máy đọc?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi sang BizReader'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.controller.books;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Thư viện'),
            actions: [
              IconButton(
                onPressed: _importing ? null : _pickAndImport,
                tooltip: 'Thêm EPUB',
                icon: _importing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
              IconButton(
                onPressed: books.isEmpty
                    ? null
                    : () =>
                          _showMessage('Chọn Đồng bộ trên sách cần cập nhật.'),
                tooltip: 'Đồng bộ tiến độ',
                icon: const Icon(Icons.sync),
              ),
              const SizedBox(width: 6),
            ],
          ),
          if (widget.controller.demoMode)
            const SliverToBoxAdapter(child: _DemoBanner()),
          if (books.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyLibrary(onImport: _pickAndImport),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Sách trên điện thoại',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${books.length} cuốn',
                      style: const TextStyle(color: Color(0xFF68707B)),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                itemCount: books.length,
                itemBuilder: (context, index) => _BookTile(
                  book: books[index],
                  index: index,
                  onOpen: () => _openBook(books[index]),
                  onUpload: _busy ? null : () => _uploadBook(books[index]),
                  syncing: _syncingBookId == books[index].id,
                  onSync: () => _syncBook(books[index]),
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverToBoxAdapter(
              child: _TransferPanel(
                busy: _busy,
                demoMode: widget.controller.demoMode,
                transfers: _transfers,
                onUpload: _pickAndUpload,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1ED),
        border: Border.all(color: const Color(0xFFB9D2C3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.slideshow_outlined, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text('Bản demo • Dữ liệu mẫu sẵn sàng để chụp ảnh')),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_outlined, size: 58),
            const SizedBox(height: 18),
            Text(
              'Chưa có sách',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thêm EPUB để đọc trên điện thoại và gửi sang BizReader.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('Thêm EPUB'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.index,
    required this.onOpen,
    required this.onUpload,
    required this.onSync,
    required this.syncing,
  });

  final LocalBook book;
  final int index;
  final VoidCallback onOpen;
  final VoidCallback? onUpload;
  final VoidCallback onSync;
  final bool syncing;

  static const _coverColors = [
    Color(0xFF18324A),
    Color(0xFF44624A),
    Color(0xFF713B35),
    Color(0xFF4B465F),
  ];

  @override
  Widget build(BuildContext context) {
    final progress = book.progress.clamp(0, 1).toDouble();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: _coverColors[index % _coverColors.length],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_stories,
                        color: Colors.white,
                        size: 24,
                      ),
                      const Spacer(),
                      Text(
                        book.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        book.author.isEmpty ? 'BizReader' : book.author,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFDDE3E8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 6, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: progress, minHeight: 3),
                        const SizedBox(height: 5),
                        Text(
                          progress > 0
                              ? 'Đã đọc ${(progress * 100).round()}%'
                              : 'Chưa đọc',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (syncing)
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Tùy chọn sách',
                      onSelected: (value) =>
                          value == 'sync' ? onSync() : onUpload?.call(),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'sync',
                          child: ListTile(
                            leading: Icon(Icons.sync),
                            title: Text('Đồng bộ'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'upload',
                          enabled: onUpload != null,
                          child: const ListTile(
                            leading: Icon(Icons.send_to_mobile),
                            title: Text('Gửi sang máy'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferPanel extends StatelessWidget {
  const _TransferPanel({
    required this.busy,
    required this.demoMode,
    required this.transfers,
    required this.onUpload,
  });

  final bool busy;
  final bool demoMode;
  final List<TransferItem> transfers;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Gửi sang BizReader',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
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
                        '/Ebook trên thẻ nhớ',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  demoMode
                      ? 'Thoát bản demo để gửi tệp thật qua Bluetooth + Wi-Fi.'
                      : 'Hỗ trợ EPUB, TXT, XTC, XTCH và BMP qua Bluetooth + Wi-Fi hoặc WebDAV.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy || demoMode ? null : onUpload,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(busy ? 'Đang gửi' : 'Chọn tệp để gửi'),
                ),
              ],
            ),
          ),
        ),
        if (transfers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < transfers.length; index++) ...[
                  _TransferRow(item: transfers[index]),
                  if (index != transfers.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ],
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
