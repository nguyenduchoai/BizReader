import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:epub_view/epub_view.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/local_book.dart';
import '../services/epub_resume_position.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.controller, required this.book});

  final AppController controller;
  final LocalBook book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  EpubController? _epubController;
  late final PageController _demoPageController;
  Timer? _saveTimer;
  double _progress = 0;
  int _chapterNumber = 0;
  double _chapterProgress = 0;
  int _chapterCount = 1;
  String _chapterTitle = '';

  @override
  void initState() {
    super.initState();
    _progress = widget.book.progress;
    _chapterNumber = widget.book.chapterNumber;
    _chapterProgress = widget.book.chapterProgress;
    if (widget.book.demo) {
      final initialPage = (widget.book.chapterNumber - 1).clamp(
        0,
        _demoChapters.length - 1,
      );
      _demoPageController = PageController(initialPage: initialPage);
      _chapterCount = _demoChapters.length;
      _chapterNumber = initialPage + 1;
      _chapterTitle = _demoChapters[initialPage].title;
    } else {
      _demoPageController = PageController();
      _epubController = EpubController(
        document: EpubDocument.openFile(File(widget.book.filePath)),
        epubCfi: widget.book.epubCfi,
      );
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _persistProgress();
    _epubController?.dispose();
    _demoPageController.dispose();
    super.dispose();
  }

  void _onChapterChanged(dynamic value) {
    if (value == null) return;
    final controller = _epubController!;
    final count = math.max(1, controller.tableOfContents().length);
    final chapterIndex = math.max(0, value.chapterNumber - 1);
    final chapterProgress = value.progress.clamp(0, 100).toDouble();
    final progress = ((chapterIndex + chapterProgress / 100) / count)
        .clamp(0, 1)
        .toDouble();
    if (mounted) {
      setState(() {
        _chapterCount = count;
        _chapterNumber = value.chapterNumber;
        _chapterProgress = chapterProgress;
        _chapterTitle =
            value.chapter?.Title?.replaceAll('\n', ' ').trim() ?? '';
        _progress = progress;
      });
    }
    _queueSave();
  }

  void _onDocumentLoaded(EpubBook _) {
    final controller = _epubController!;
    final chapters = controller.tableOfContents();
    _chapterCount = math.max(1, chapters.length);
    if (widget.book.epubCfi == null &&
        (widget.book.progress > 0 ||
            widget.book.chapterNumber > 0 ||
            widget.book.chapterProgress > 0) &&
        chapters.isNotEmpty) {
      final target = epubResumeIndex(
        chapterStartIndexes: [
          for (final chapter in chapters) chapter.startIndex,
        ],
        chapterNumber: widget.book.chapterNumber,
        chapterProgress: widget.book.chapterProgress,
        bookProgress: widget.book.progress,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.scrollTo(index: target);
      });
    }
  }

  void _onDemoPageChanged(int index) {
    setState(() {
      _chapterCount = _demoChapters.length;
      _chapterNumber = index + 1;
      _chapterProgress = 0;
      _chapterTitle = _demoChapters[index].title;
      _progress = (index + 1) / _demoChapters.length;
    });
    _queueSave();
  }

  void _queueSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _persistProgress);
  }

  Future<void> _persistProgress() async {
    await widget.controller.updateBookProgress(
      widget.book.id,
      progress: _progress,
      chapterNumber: _chapterNumber,
      chapterProgress: _chapterProgress,
      epubCfi: _epubController?.generateEpubCfi(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFCF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCFCF8),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_chapterTitle.isNotEmpty)
              Text(
                _chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          if (!widget.book.demo)
            IconButton(
              tooltip: 'Mục lục',
              onPressed: () => _showTableOfContents(context),
              icon: const Icon(Icons.toc),
            ),
        ],
      ),
      body: widget.book.demo ? _buildDemoReader() : _buildEpubReader(),
      bottomNavigationBar: _ReaderProgressBar(
        progress: _progress,
        chapterNumber: _chapterNumber,
        chapterCount: _chapterCount,
      ),
    );
  }

  Widget _buildEpubReader() {
    return EpubView(
      controller: _epubController!,
      onDocumentLoaded: _onDocumentLoaded,
      onChapterChanged: _onChapterChanged,
      onDocumentError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở nội dung EPUB này.')),
        );
      },
      builders: EpubViewBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(
          chapterPadding: EdgeInsets.fromLTRB(18, 22, 18, 8),
          paragraphPadding: EdgeInsets.symmetric(horizontal: 18),
          textStyle: TextStyle(
            fontSize: 18,
            height: 1.55,
            color: Color(0xFF17191C),
          ),
        ),
        loaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildDemoReader() {
    return PageView.builder(
      controller: _demoPageController,
      itemCount: _demoChapters.length,
      onPageChanged: _onDemoPageChanged,
      itemBuilder: (context, index) {
        final chapter = _demoChapters[index];
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 28, 26, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHƯƠNG ${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                chapter.title,
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              for (final paragraph in chapter.paragraphs) ...[
                Text(
                  paragraph,
                  textAlign: TextAlign.justify,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.62,
                    color: Color(0xFF202225),
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showTableOfContents(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mục lục',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              Expanded(
                child: EpubViewTableOfContents(
                  controller: _epubController!,
                  itemBuilder: (context, index, chapter, itemCount) => ListTile(
                    title: Text(
                      chapter.title?.trim().isNotEmpty == true
                          ? chapter.title!.trim()
                          : 'Phần ${index + 1}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      _epubController!.scrollTo(index: chapter.startIndex);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderProgressBar extends StatelessWidget {
  const _ReaderProgressBar({
    required this.progress,
    required this.chapterNumber,
    required this.chapterCount,
  });

  final double progress;
  final int chapterNumber;
  final int chapterCount;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: const Color(0xFFFCFCF8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
          child: Row(
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LinearProgressIndicator(value: progress, minHeight: 3),
              ),
              const SizedBox(width: 12),
              Text(chapterNumber > 0 ? '$chapterNumber/$chapterCount' : '—'),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoChapter {
  const _DemoChapter(this.title, this.paragraphs);

  final String title;
  final List<String> paragraphs;
}

const _demoChapters = [
  _DemoChapter('Thay đổi tư duy', [
    'Mỗi quyết định tốt bắt đầu từ một khoảng dừng đủ dài để nhìn vấn đề rõ hơn. Khi ta đọc, những ý tưởng rời rạc dần kết nối thành một cách nhìn mới.',
    'Tri thức không tạo ra khác biệt nếu chỉ nằm trên trang sách. Giá trị xuất hiện khi một điều nhỏ được áp dụng đều đặn vào công việc và cuộc sống mỗi ngày.',
  ]),
  _DemoChapter('Tập trung vào điều quan trọng', [
    'Sự tập trung không phải là làm nhiều hơn. Đó là chủ động loại bỏ những việc không phục vụ mục tiêu chính, để thời gian và năng lượng đi đúng hướng.',
    'Một giờ làm việc sâu có thể tạo ra kết quả lớn hơn nhiều giờ phản ứng liên tục với thông báo và những yêu cầu vụn vặt.',
  ]),
  _DemoChapter('Biến kiến thức thành hành động', [
    'Hãy kết thúc mỗi chương bằng một câu hỏi cụ thể: ngày mai mình sẽ làm điều gì khác đi? Câu trả lời càng nhỏ và rõ, khả năng thực hiện càng cao.',
    'Đọc để hành động giúp cuốn sách tiếp tục sống trong những quyết định sau khi ta đã đóng trang cuối cùng.',
  ]),
];
