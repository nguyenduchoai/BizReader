import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/biz_content.dart';

class ContentHubScreen extends StatefulWidget {
  const ContentHubScreen({
    super.key,
    required this.controller,
    this.initialTab = 0,
  });

  final AppController controller;
  final int initialTab;

  @override
  State<ContentHubScreen> createState() => _ContentHubScreenState();
}

class _ContentHubScreenState extends State<ContentHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 5,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiện ích BizReader'),
        actions: [
          IconButton(
            onPressed: widget.controller.contentSyncing ? null : _sync,
            tooltip: 'Đồng bộ BLE hai chiều',
            icon: widget.controller.contentSyncing
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.note_alt_outlined), text: 'Ghi chú'),
            Tab(icon: Icon(Icons.checklist), text: 'Việc cần làm'),
            Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Lịch'),
            Tab(icon: Icon(Icons.cloud_outlined), text: 'Thời tiết'),
            Tab(icon: Icon(Icons.photo_outlined), text: 'Nền nghỉ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _NotesPage(controller: widget.controller),
          _TodosPage(controller: widget.controller),
          _CalendarPage(controller: widget.controller),
          _WeatherPage(controller: widget.controller),
          _SleepPage(controller: widget.controller),
        ],
      ),
    );
  }
}

class _NotesPage extends StatelessWidget {
  const _NotesPage({required this.controller});
  final AppController controller;

  Future<void> _edit(BuildContext context, [BizNote? note]) async {
    final title = TextEditingController(text: note?.title);
    final body = TextEditingController(text: note?.body);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? 'Thêm ghi chú' : 'Sửa ghi chú'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Tiêu đề'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Nội dung'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, title.text.trim().isNotEmpty),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await controller.saveNote(
        id: note?.id,
        title: title.text,
        body: body.text,
      );
    }
    title.dispose();
    body.dispose();
  }

  @override
  Widget build(BuildContext context) => _ModuleList(
    emptyIcon: Icons.note_alt_outlined,
    emptyText: 'Chưa có ghi chú',
    onAdd: () => _edit(context),
    children: [
      for (final note in controller.content.notes.reversed)
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(note.title),
          subtitle: note.body.isEmpty
              ? null
              : Text(note.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _edit(context, note),
          trailing: IconButton(
            tooltip: 'Xóa ghi chú',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => controller.deleteNote(note.id),
          ),
        ),
    ],
  );
}

class _TodosPage extends StatelessWidget {
  const _TodosPage({required this.controller});
  final AppController controller;

  Future<void> _add(BuildContext context) async {
    final title = TextEditingController();
    final due = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm việc cần làm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Công việc'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: due,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Hạn hoàn thành'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, title.text.trim().isNotEmpty),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
    if (saved == true) await controller.addTodo(title.text, due: due.text);
    title.dispose();
    due.dispose();
  }

  @override
  Widget build(BuildContext context) => _ModuleList(
    emptyIcon: Icons.checklist,
    emptyText: 'Chưa có việc cần làm',
    onAdd: () => _add(context),
    children: [
      for (final todo in controller.content.todos)
        CheckboxListTile(
          value: todo.done,
          onChanged: (_) => controller.toggleTodo(todo.id),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            todo.title,
            style: TextStyle(
              decoration: todo.done ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: todo.due.isEmpty ? null : Text(todo.due),
          secondary: IconButton(
            tooltip: 'Xóa công việc',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => controller.deleteTodo(todo.id),
          ),
        ),
    ],
  );
}

class _CalendarPage extends StatelessWidget {
  const _CalendarPage({required this.controller});
  final AppController controller;

  Future<void> _add(BuildContext context) async {
    final title = TextEditingController();
    final time = TextEditingController();
    final location = TextEditingController();
    var date = DateTime.now();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Thêm lịch'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Tên sự kiện'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text('${date.day}/${date.month}/${date.year}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      initialDate: date,
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                TextField(
                  controller: time,
                  maxLength: 5,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Giờ (HH:mm)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: location,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Địa điểm'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, title.text.trim().isNotEmpty),
              child: const Text('Thêm'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await controller.addCalendarEvent(
        title: title.text,
        date: date,
        time: time.text,
        location: location.text,
      );
    }
    title.dispose();
    time.dispose();
    location.dispose();
  }

  @override
  Widget build(BuildContext context) => _ModuleList(
    emptyIcon: Icons.calendar_month_outlined,
    emptyText: 'Chưa có sự kiện',
    onAdd: () => _add(context),
    children: [
      for (final event in controller.content.events)
        ListTile(
          leading: _DateBadge(date: event.date),
          title: Text(event.title),
          subtitle: Text(
            [
              event.time,
              event.location,
            ].where((item) => item.isNotEmpty).join(' · '),
          ),
          trailing: IconButton(
            tooltip: 'Xóa sự kiện',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => controller.deleteCalendarEvent(event.id),
          ),
        ),
    ],
  );
}

class _WeatherPage extends StatelessWidget {
  const _WeatherPage({required this.controller});
  final AppController controller;

  Future<void> _edit(BuildContext context) async {
    final current = controller.content.weather;
    final location = TextEditingController(text: current.location);
    final condition = TextEditingController(text: current.condition);
    final temperature = TextEditingController(text: '${current.temperature}');
    final high = TextEditingController(text: '${current.high}');
    final low = TextEditingController(text: '${current.low}');
    final action = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cập nhật thời tiết'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: location,
                decoration: const InputDecoration(labelText: 'Địa điểm'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: condition,
                decoration: const InputDecoration(labelText: 'Trạng thái'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: temperature,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Hiện tại °C',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: high,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cao °C'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: low,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Thấp °C'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: const Text('Hủy'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 2),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Lấy tự động'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, location.text.trim().isNotEmpty ? 1 : 0),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    try {
      if (action == 2) {
        await controller.refreshWeather(location.text);
      } else if (action == 1) {
        await controller.updateWeather(
          BizWeather(
            location: location.text.trim(),
            condition: condition.text.trim(),
            temperature: int.tryParse(temperature.text) ?? 0,
            high: int.tryParse(high.text) ?? 0,
            low: int.tryParse(low.text) ?? 0,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
    location.dispose();
    condition.dispose();
    temperature.dispose();
    high.dispose();
    low.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weather = controller.content.weather;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.cloud_outlined, size: 48),
                const SizedBox(height: 12),
                Text(
                  weather.location,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${weather.temperature}°',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${weather.condition} · ${weather.low}° / ${weather.high}°',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Cập nhật'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Cập nhật tự động theo tên thành phố hoặc nhập tay, sau đó đồng bộ BLE với BizReader.',
        ),
      ],
    );
  }
}

class _SleepPage extends StatelessWidget {
  const _SleepPage({required this.controller});
  final AppController controller;

  Future<void> _pickImage(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      await controller.setWallpaper(File(path));
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = controller.content;
    final imagePath = content.wallpaperPath;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<BizSleepMode>(
          segments: const [
            ButtonSegment(
              value: BizSleepMode.calendar,
              icon: Icon(Icons.calendar_month_outlined),
              label: Text('Lịch'),
            ),
            ButtonSegment(
              value: BizSleepMode.photo,
              icon: Icon(Icons.photo_outlined),
              label: Text('Ảnh'),
            ),
          ],
          selected: {content.sleepMode},
          onSelectionChanged: (value) => controller.setSleepMode(value.single),
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            clipBehavior: Clip.antiAlias,
            child: content.sleepMode == BizSleepMode.photo && imagePath != null
                ? Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  )
                : _CalendarPreview(content: content),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _pickImage(context),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Chọn ảnh từ máy'),
        ),
        if (imagePath != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              try {
                await controller.sendWallpaperToDevice();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã gửi ảnh nền qua Wi-Fi')),
                );
              } on Object catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },
            icon: const Icon(Icons.wifi_outlined),
            label: const Text('Gửi ảnh nền qua Wi-Fi'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.clearWallpaper,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xóa ảnh và dùng lịch'),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Ảnh được chuyển sang BMP 960 × 540 trước khi gửi xuống thiết bị.',
        ),
      ],
    );
  }
}

class _CalendarPreview extends StatelessWidget {
  const _CalendarPreview({required this.content});
  final BizContent content;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = content.events.isEmpty
        ? 'Không có lịch sắp tới'
        : content.events.first.title;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${now.day}',
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            'Tháng ${now.month} · ${content.weather.temperature}° ${content.weather.condition}',
          ),
          const Divider(height: 28),
          Text(next, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _ModuleList extends StatelessWidget {
  const _ModuleList({
    required this.emptyIcon,
    required this.emptyText,
    required this.onAdd,
    required this.children,
  });
  final IconData emptyIcon;
  final String emptyText;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (children.isEmpty)
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, size: 48),
              const SizedBox(height: 12),
              Text(emptyText),
            ],
          ),
        )
      else
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          itemCount: children.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) => children[index],
        ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          onPressed: onAdd,
          tooltip: 'Thêm',
          child: const Icon(Icons.add),
        ),
      ),
    ],
  );
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});
  final String date;

  @override
  Widget build(BuildContext context) {
    final parts = date.split('-');
    return SizedBox(
      width: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            parts.length == 3 ? parts[2] : date,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            parts.length == 3 ? 'T${int.tryParse(parts[1]) ?? parts[1]}' : '',
          ),
        ],
      ),
    );
  }
}
