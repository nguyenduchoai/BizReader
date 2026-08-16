import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

import '../app_controller.dart';
import '../models/local_book.dart';
import '../models/reader_preferences.dart';
import '../services/epub_archive_guard.dart';
import '../services/reader_preferences_store.dart';
import '../services/reader_progress.dart';
import 'reader_settings_sheet.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.controller, required this.book});

  final AppController controller;
  final LocalBook book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final EpubController _epubController = EpubController();
  final ReaderPreferencesStore _preferencesStore = ReaderPreferencesStore();
  late final PageController _demoPageController;

  ReaderPreferences _preferences = const ReaderPreferences();
  List<ReaderBookmark> _bookmarks = const [];
  List<EpubChapter> _chapters = const [];
  Timer? _saveTimer;
  Timer? _chromeTimer;
  Timer? _loadTimer;
  Future<void> _saveChain = Future.value();

  double _progress = 0;
  int _chapterNumber = 1;
  double _chapterProgress = 0;
  int _chapterCount = 1;
  int _pageNumber = 0;
  int _pageCount = 0;
  int _demoIndex = 0;
  String _chapterTitle = '';
  String? _currentCfi;
  String _currentHref = '';
  int _activeTocIndex = -1;
  Offset? _touchDown;
  DateTime? _touchDownAt;
  Offset? _demoPointerDown;
  DateTime? _demoPointerDownAt;
  int _lastTapAt = 0;
  bool _showChrome = true;
  bool _epubReady = false;
  bool _epubValidated = false;
  bool _rendererCrashed = false;
  bool _closing = false;
  bool _clearRejectedCfi = false;
  String? _readerError;
  late ReaderResumeCoordinator _resumeCoordinator;

  static const _rendererCrashedMessage = 'Trình đọc gặp sự cố. Nhấn để tải lại.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumeCoordinator = ReaderResumeCoordinator(
      initialCfi: _validCfi(widget.book.epubCfi),
      initialProgress: widget.book.progress,
    );
    _progress = _resumeCoordinator.initialProgress;
    _chapterNumber = widget.book.chapterNumber > 0
        ? widget.book.chapterNumber
        : 1;
    _chapterProgress = widget.book.chapterProgress.clamp(0, 100);
    _pageNumber = widget.book.pageNumber;
    _pageCount = widget.book.pageCount;
    _currentCfi = _resumeCoordinator.initialCfi;

    _demoIndex = (_progress * (_demoPages.length - 1)).round().clamp(
      0,
      _demoPages.length - 1,
    );
    _demoPageController = PageController(initialPage: _demoIndex);
    if (widget.book.demo) _applyDemoPosition(_demoIndex, notify: false);

    unawaited(_loadReaderState());
    _scheduleChromeHide();
    if (!widget.book.demo) {
      unawaited(_prepareEpubSource());
      _armLoadTimer();
    }
  }

  void _armLoadTimer() {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 35), () {
      if (!mounted || _epubReady) return;
      setState(() {
        _readerError = 'Sách mất quá nhiều thời gian để phân trang.';
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushProgressBestEffort());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _chromeTimer?.cancel();
    _loadTimer?.cancel();
    if (!_closing) unawaited(_persistProgressBestEffort());
    _demoPageController.dispose();
    super.dispose();
  }

  Future<void> _loadReaderState() async {
    final values = await Future.wait<Object>([
      _preferencesStore.load(),
      _preferencesStore.loadBookmarks(widget.book.id),
    ]);
    if (!mounted) return;
    setState(() {
      _preferences = values[0] as ReaderPreferences;
      _bookmarks = values[1] as List<ReaderBookmark>;
    });
    if (_epubReady) _applyPreferencesToEpub();
  }

  Future<void> _prepareEpubSource() async {
    try {
      // Validate the archive (zip-bomb / truncation guard) before handing the
      // file to the WebView. inspect() reads only the ZIP directory, headers
      // and mimetype, so no whole-book buffer ever lands on the Dart heap;
      // the viewer re-reads the file lazily.
      await EpubArchiveGuard().inspect(File(widget.book.filePath));
      if (!mounted) return;
      setState(() => _epubValidated = true);
    } on EpubArchiveGuardException catch (error) {
      if (!mounted) return;
      _loadTimer?.cancel();
      setState(() => _readerError = error.message);
    } on Object {
      if (!mounted) return;
      _loadTimer?.cancel();
      setState(() {
        _readerError = 'Không thể đọc tệp EPUB này.';
      });
    }
  }

  String? _validCfi(String? value) {
    if (value == null || !value.startsWith('epubcfi(')) return null;
    return value;
  }

  void _onEpubLoaded() {
    // epub.js emits `displayed` for every page. Reader initialization must only
    // run for the first display; reapplying CSS here would reflow every turn.
    if (_epubReady) return;
    _loadTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _epubReady = true;
      _readerError = null;
      _rendererCrashed = false;
    });
    _applyPreferencesToEpub();
  }

  void _onLocationsLoaded() {
    // The first `relocated` event is emitted before epub.js finishes generating
    // its locations and therefore reports 0%. Re-display the durable resume
    // target now so the next event contains a valid global percentage.
    final target = _resumeCoordinator.locationsLoaded(currentCfi: _currentCfi);
    if (target == null) return;
    _displayResumeTarget(target);
  }

  void _displayResumeTarget(ReaderResumeTarget target) {
    if (target.cfi case final cfi?) {
      _epubController.display(cfi: cfi);
    } else if (target.progress case final progress?) {
      _epubController.toProgressPercentage(progress);
    }
  }

  void _onEpubDisplayError(String _) {
    final recovery = _resumeCoordinator.displayFailed();
    if (recovery.handled) {
      _currentCfi = null;
      _clearRejectedCfi = true;
      if (recovery.target case final target?) {
        _displayResumeTarget(target);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _readerError = 'Không thể hiển thị trang EPUB này.';
    });
  }

  void _onRendererCrashed() {
    // The WebView renderer process died (typically OOM on a huge EPUB). The
    // platform view is unusable; tear it down and offer a manual reload.
    if (!mounted) return;
    _loadTimer?.cancel();
    setState(() {
      _epubReady = false;
      _epubValidated = false;
      _rendererCrashed = true;
      _readerError = _rendererCrashedMessage;
    });
  }

  void _restartReader() {
    // Resume from the position we had when the renderer died, exactly like a
    // fresh open: reset the resume coordinator, re-validate the file and let a
    // brand-new platform view run the readyToLoad -> loadBook flow.
    _resumeCoordinator = ReaderResumeCoordinator(
      initialCfi: _validCfi(_currentCfi),
      initialProgress: _progress,
    );
    setState(() {
      _readerError = null;
      _rendererCrashed = false;
      _epubReady = false;
      _epubValidated = false;
    });
    unawaited(_prepareEpubSource());
    _armLoadTimer();
  }

  void _onChaptersLoaded(List<EpubChapter> chapters) {
    final flat = _flattenChapters(chapters);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _chapterCount = flat.isEmpty ? 1 : flat.length;
      _updateChapterTitle();
    });
  }

  void _onRelocated(EpubLocation location) {
    if (!_resumeCoordinator.acceptsRelocations) {
      // Preserve the synced percentage/CFI until the generated location table
      // can map this page accurately. Saving this early event would overwrite a
      // device-supplied resume position with the EPUB's first-page 0% value.
      if (!_resumeCoordinator.hasDurablePosition && mounted) {
        setState(() {
          _currentCfi = location.startCfi;
          _currentHref = location.href;
          _pageNumber = location.pageNumber;
          _pageCount = location.pageCount;
          _updateChapterTitle();
        });
      }
      return;
    }
    final mapped = ReaderProgress.fromLocation(
      overall: location.progress,
      spineIndex: location.spineIndex,
      pageNumber: location.pageNumber,
      pageCount: location.pageCount,
    );
    if (!mounted) return;
    _resumeCoordinator.relocationAccepted();
    setState(() {
      _progress = mapped.overall;
      _chapterNumber = mapped.chapterNumber;
      _chapterProgress = mapped.chapterProgress;
      _pageNumber = mapped.pageNumber;
      _pageCount = mapped.pageCount;
      _currentCfi = location.startCfi;
      _currentHref = location.href;
      _clearRejectedCfi = false;
      if (_chapterNumber > _chapterCount) _chapterCount = _chapterNumber;
      _updateChapterTitle();
      _showChrome = false;
    });
    _queueSave();
  }

  void _updateChapterTitle() {
    final flat = _flattenChapters(_chapters);
    final index = readerTocIndexForHref(
      _currentHref,
      flat.map((entry) => entry.chapter.href),
    );
    _activeTocIndex = index;
    if (index >= 0 && index < flat.length) {
      _chapterTitle = flat[index].chapter.title.trim();
    } else {
      _chapterTitle = '';
    }
  }

  void _applyDemoPosition(int index, {bool notify = true}) {
    final page = _demoPages[index];
    final chapterPages = _demoPages
        .where((item) => item.chapter == page.chapter)
        .toList(growable: false);
    final pageInChapter = chapterPages.indexOf(page);
    void update() {
      _demoIndex = index;
      _chapterCount = _demoChapterTitles.length;
      _chapterNumber = page.chapter;
      _chapterTitle = page.title;
      _pageNumber = pageInChapter;
      _pageCount = chapterPages.length;
      _chapterProgress = chapterPages.length > 1
          ? pageInChapter * 100 / (chapterPages.length - 1)
          : 0;
      _progress = _demoPages.length > 1 ? index / (_demoPages.length - 1) : 0;
      _currentCfi = 'demo:$index';
      if (notify) _showChrome = false;
    }

    if (notify) {
      setState(update);
      _queueSave();
    } else {
      update();
    }
  }

  void _queueSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _persistProgress);
  }

  Future<void> _persistProgress() {
    final progress = _progress;
    final chapterNumber = _chapterNumber;
    final chapterProgress = _chapterProgress;
    final pageNumber = _pageNumber;
    final pageCount = _pageCount;
    final cfi = widget.book.demo ? null : _currentCfi;
    final clearEpubCfi = !widget.book.demo && _clearRejectedCfi && cfi == null;
    final previous = _saveChain;
    _saveChain = () async {
      try {
        await previous;
      } on Object {
        // A later position should still be saved when an earlier write failed.
      }
      await widget.controller.updateBookProgress(
        widget.book.id,
        progress: progress,
        chapterNumber: chapterNumber,
        chapterProgress: chapterProgress,
        pageNumber: pageNumber,
        pageCount: pageCount,
        epubCfi: cfi,
        clearEpubCfi: clearEpubCfi,
      );
    }();
    return _saveChain;
  }

  /// Runs [save], logging failures under [label] instead of throwing: a full
  /// disk must never take down the reading session.
  Future<void> _persistBestEffort(
    Future<void> Function() save,
    String label,
  ) async {
    try {
      await save();
    } on Object catch (error, stackTrace) {
      debugPrint('$label: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _persistProgressBestEffort() =>
      _persistBestEffort(_persistProgress, 'Không lưu được tiến độ đọc');

  Future<void> _flushProgressBestEffort() async {
    _saveTimer?.cancel();
    await _persistProgressBestEffort();
  }

  Future<void> _closeReader() async {
    if (_closing) return;
    _closing = true;
    await _flushProgressBestEffort();
    if (mounted) Navigator.pop(context);
  }

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    if (!_showChrome) return;
    _chromeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showChrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    _scheduleChromeHide();
  }

  void _showChromeNow() {
    if (!_showChrome) setState(() => _showChrome = true);
    _scheduleChromeHide();
  }

  void _onTouchDown(double x, double y) {
    _touchDown = Offset(x, y);
    _touchDownAt = DateTime.now();
  }

  void _onTouchUp(double x, double y) {
    final now = DateTime.now();
    final start = _touchDown;
    final startedAt = _touchDownAt;
    _touchDown = null;
    _touchDownAt = null;
    if (start == null || startedAt == null) return;
    if (now.millisecondsSinceEpoch - _lastTapAt < 160) return;
    if (now.difference(startedAt) > const Duration(milliseconds: 500)) return;
    final delta = Offset(x, y) - start;
    if (delta.distance > 0.045) return;
    _lastTapAt = now.millisecondsSinceEpoch;
    if (x < 0.23) {
      _epubController.prev();
    } else if (x > 0.77) {
      _epubController.next();
    } else {
      _toggleChrome();
    }
  }

  void _turnDemoPage(int delta) {
    final target = (_demoIndex + delta).clamp(0, _demoPages.length - 1);
    if (target == _demoIndex) return;
    _demoPageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _onDemoPointerDown(PointerDownEvent event) {
    _demoPointerDown = event.localPosition;
    _demoPointerDownAt = DateTime.now();
  }

  void _onDemoPointerUp(PointerUpEvent event, double width) {
    final start = _demoPointerDown;
    final startedAt = _demoPointerDownAt;
    _demoPointerDown = null;
    _demoPointerDownAt = null;
    if (start == null || startedAt == null) return;
    if (DateTime.now().difference(startedAt) >
        const Duration(milliseconds: 500)) {
      return;
    }
    if ((event.localPosition - start).distance > 12) return;
    final x = event.localPosition.dx / width;
    if (x < 0.23) {
      _turnDemoPage(-1);
    } else if (x > 0.77) {
      _turnDemoPage(1);
    } else {
      _toggleChrome();
    }
  }

  void _updatePreferences(ReaderPreferences next) {
    setState(() => _preferences = next);
    unawaited(
      _persistBestEffort(
        () => _preferencesStore.save(next),
        'Không lưu được tùy chỉnh đọc',
      ),
    );
    if (_epubReady) _applyPreferencesToEpub();
  }

  void _applyPreferencesToEpub() {
    _epubController.setFontSize(fontSize: _preferences.fontSize);
    _epubController.updateTheme(theme: _epubTheme(_preferences));
  }

  EpubTheme _epubTheme(ReaderPreferences preferences) {
    final theme = preferences.theme;
    final background = _cssColor(theme.background);
    final foreground = _cssColor(theme.text);
    final secondary = _cssColor(theme.secondary);
    final font = preferences.cssFontFamily;
    final lineHeight = preferences.lineHeight.toStringAsFixed(2);
    final margin = preferences.margin.round();
    return EpubTheme.custom(
      backgroundDecoration: BoxDecoration(color: theme.background),
      foregroundColor: theme.text,
      customCss: {
        'html': {
          'background': '$background !important',
          'color': '$foreground !important',
        },
        'body': {
          'background': '$background !important',
          'color': '$foreground !important',
          'font-family': '$font !important',
          'font-size': '${preferences.fontSize}px !important',
          'line-height': '$lineHeight !important',
          'padding': '52px ${margin}px 62px !important',
          'box-sizing': 'border-box !important',
          'text-align': '${preferences.textAlign} !important',
          '-webkit-font-smoothing': 'antialiased',
        },
        'p, li, blockquote': {
          'font-family': '$font !important',
          'font-size': '${preferences.fontSize}px !important',
          'line-height': '$lineHeight !important',
          'color': '$foreground !important',
          'text-align': '${preferences.textAlign} !important',
        },
        'h1, h2, h3, h4, h5, h6': {
          'font-family': '$font !important',
          'color': '$foreground !important',
          'line-height': '1.28 !important',
        },
        'a, a:visited': {'color': '$secondary !important'},
        'img, svg, video': {
          'max-width': '100% !important',
          'max-height': '78vh !important',
          'object-fit': 'contain !important',
        },
      },
    );
  }

  String _cssColor(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }

  Future<void> _saveBookmarksBestEffort(List<ReaderBookmark> bookmarks) =>
      _persistBestEffort(
        () => _preferencesStore.saveBookmarks(widget.book.id, bookmarks),
        'Không lưu được dấu trang',
      );

  bool get _isBookmarked {
    final cfi = _currentCfi;
    return cfi != null && _bookmarks.any((item) => item.cfi == cfi);
  }

  Future<void> _toggleBookmark() async {
    final cfi = _currentCfi;
    if (cfi == null || cfi.isEmpty) return;
    final next = [..._bookmarks];
    final index = next.indexWhere((item) => item.cfi == cfi);
    final added = index < 0;
    if (added) {
      next.add(
        ReaderBookmark(
          cfi: cfi,
          progress: _progress,
          chapterTitle: _chapterTitle,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else {
      next.removeAt(index);
    }
    setState(() => _bookmarks = next);
    await _saveBookmarksBestEffort(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? 'Đã đánh dấu trang' : 'Đã bỏ đánh dấu'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _preferences.theme;
    final dark =
        ThemeData.estimateBrightnessForColor(theme.background) ==
        Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.background,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: theme.background,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_closeReader());
        },
        child: Scaffold(
          backgroundColor: theme.background,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: widget.book.demo
                      ? _buildDemoReader(theme)
                      : _buildEpubReader(theme),
                ),
                if (!widget.book.demo && !_epubReady && _readerError == null)
                  _ReaderLoading(theme: theme),
                if (_readerError case final message?)
                  _ReaderError(
                    theme: theme,
                    message: message,
                    onBack: _closeReader,
                    onRetry: _rendererCrashed ? _restartReader : null,
                  ),
                _buildTopChrome(theme),
                _buildBottomChrome(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpubReader(ReaderThemeSpec theme) {
    if (!_epubValidated) return ColoredBox(color: theme.background);
    return ColoredBox(
      color: theme.background,
      child: EpubViewer(
        epubController: _epubController,
        // Cheap lazy wrapper (no IO at construction); the viewer reads it once
        // per platform view, so rebuilding it here never reloads the book.
        epubSource: EpubSource.fromFilePath(widget.book.filePath),
        initialCfi: _currentCfi,
        displaySettings: EpubDisplaySettings(
          fontSize: _preferences.fontSize.round(),
          spread: EpubSpread.none,
          flow: EpubFlow.paginated,
          snap: true,
          useSnapAnimationAndroid: false,
          allowScriptedContent: false,
          theme: _epubTheme(_preferences),
        ),
        onEpubLoaded: _onEpubLoaded,
        onLocationLoaded: _onLocationsLoaded,
        onChaptersLoaded: _onChaptersLoaded,
        onRelocated: _onRelocated,
        onDisplayError: _onEpubDisplayError,
        onRendererCrashed: _onRendererCrashed,
        onTouchDown: _onTouchDown,
        onTouchUp: _onTouchUp,
      ),
    );
  }

  Widget _buildDemoReader(ReaderThemeSpec theme) {
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDemoPointerDown,
        onPointerUp: (event) => _onDemoPointerUp(event, constraints.maxWidth),
        child: PageView.builder(
          key: const Key('bizreader-demo-page-view'),
          controller: _demoPageController,
          scrollDirection: Axis.horizontal,
          itemCount: _demoPages.length,
          onPageChanged: _applyDemoPosition,
          itemBuilder: (context, index) {
            final page = _demoPages[index];
            return Padding(
              padding: EdgeInsets.fromLTRB(
                _preferences.margin,
                70,
                _preferences.margin,
                78,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CHƯƠNG ${page.chapter}',
                    style: TextStyle(
                      color: theme.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    page.title,
                    style: TextStyle(
                      color: theme.text,
                      fontFamily: _preferences.flutterFontFamily,
                      fontSize: 28,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        page.body,
                        textAlign: _preferences.textAlign == 'justify'
                            ? TextAlign.justify
                            : TextAlign.left,
                        style: TextStyle(
                          color: theme.text,
                          fontFamily: _preferences.flutterFontFamily,
                          fontSize: _preferences.fontSize,
                          height: _preferences.lineHeight,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopChrome(ReaderThemeSpec theme) {
    return _ChromeVisibility(
      visible: _showChrome,
      alignment: Alignment.topCenter,
      child: _ReaderSurface(
        color: theme.surface,
        border: Border(
          bottom: BorderSide(color: theme.text.withValues(alpha: 0.08)),
        ),
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Quay lại',
                onPressed: _closeReader,
                icon: Icon(Icons.arrow_back_ios_new, color: theme.text),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_chapterTitle.isNotEmpty)
                      Text(
                        _chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.secondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _isBookmarked ? 'Bỏ đánh dấu' : 'Đánh dấu trang',
                onPressed: _currentCfi == null ? null : _toggleBookmark,
                icon: Icon(
                  _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: _isBookmarked ? theme.accent : theme.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomChrome(ReaderThemeSpec theme) {
    final pageLabel = _pageCount > 0
        ? 'Trang ${_pageNumber + 1}/$_pageCount'
        : '${(_progress * 100).round()}%';
    return _ChromeVisibility(
      visible: _showChrome,
      alignment: Alignment.bottomCenter,
      child: _ReaderSurface(
        color: theme.surface,
        border: Border(
          top: BorderSide(color: theme.text.withValues(alpha: 0.08)),
        ),
        child: SizedBox(
          height: 70,
          child: Column(
            children: [
              LinearProgressIndicator(
                value: _progress,
                minHeight: 2,
                color: theme.accent,
                backgroundColor: theme.muted.withValues(alpha: 0.18),
              ),
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Mục lục và dấu trang',
                      onPressed: _showContents,
                      icon: Icon(Icons.menu_book_outlined, color: theme.text),
                    ),
                    Expanded(
                      child: Text(
                        '$pageLabel  •  ${(_progress * 100).round()}%',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          color: theme.secondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tùy chỉnh đọc',
                      onPressed: _showSettings,
                      icon: Icon(Icons.text_fields, color: theme.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    _chromeTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReaderSettingsSheet(
        preferences: _preferences,
        onChanged: _updatePreferences,
      ),
    );
    if (mounted) _showChromeNow();
  }

  Future<void> _showContents() async {
    _chromeTimer?.cancel();
    final theme = _preferences.theme;
    final entries = _flattenChapters(_chapters);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surface,
      builder: (context) => DefaultTabController(
        length: 2,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: theme.text),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  labelColor: theme.text,
                  unselectedLabelColor: theme.secondary,
                  indicatorColor: theme.accent,
                  tabs: const [
                    Tab(text: 'Mục lục'),
                    Tab(text: 'Dấu trang'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      widget.book.demo
                          ? _buildDemoContents(theme)
                          : _buildEpubContents(theme, entries),
                      _buildBookmarks(theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) _showChromeNow();
  }

  Widget _buildEpubContents(
    ReaderThemeSpec theme,
    List<_ChapterEntry> entries,
  ) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'EPUB này không có mục lục.',
          style: TextStyle(color: theme.secondary),
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: theme.text.withValues(alpha: 0.08)),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final active = index == _activeTocIndex;
        return ListTile(
          contentPadding: EdgeInsets.only(
            left: 18 + entry.depth * 18,
            right: 10,
          ),
          title: Text(
            entry.chapter.title.trim().isEmpty
                ? 'Phần ${index + 1}'
                : entry.chapter.title.trim(),
            style: TextStyle(
              color: active ? theme.accent : theme.text,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: theme.secondary),
          onTap: () {
            _epubController.display(cfi: entry.chapter.href);
            Navigator.pop(context);
          },
        );
      },
    );
  }

  Widget _buildDemoContents(ReaderThemeSpec theme) {
    return ListView.separated(
      itemCount: _demoChapterTitles.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: theme.text.withValues(alpha: 0.08)),
      itemBuilder: (context, index) => ListTile(
        title: Text(
          _demoChapterTitles[index],
          style: TextStyle(color: theme.text, fontWeight: FontWeight.w600),
        ),
        trailing: Icon(Icons.chevron_right, color: theme.secondary),
        onTap: () {
          final target = _demoPages.indexWhere(
            (page) => page.chapter == index + 1,
          );
          Navigator.pop(context);
          if (target >= 0) _demoPageController.jumpToPage(target);
        },
      ),
    );
  }

  Widget _buildBookmarks(ReaderThemeSpec theme) {
    if (_bookmarks.isEmpty) {
      return Center(
        child: Text(
          'Chưa có dấu trang.',
          style: TextStyle(color: theme.secondary),
        ),
      );
    }
    final items = [..._bookmarks]
      ..sort((a, b) => a.progress.compareTo(b.progress));
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: theme.text.withValues(alpha: 0.08)),
      itemBuilder: (context, index) {
        final bookmark = items[index];
        return ListTile(
          leading: Icon(Icons.bookmark, color: theme.accent),
          title: Text(
            bookmark.chapterTitle.isEmpty
                ? 'Trang ${(bookmark.progress * 100).round()}%'
                : bookmark.chapterTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.text, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${(bookmark.progress * 100).round()}%',
            style: TextStyle(color: theme.secondary),
          ),
          trailing: IconButton(
            tooltip: 'Xóa dấu trang',
            onPressed: () async {
              final next = [..._bookmarks]..remove(bookmark);
              setState(() => _bookmarks = next);
              await _saveBookmarksBestEffort(next);
            },
            icon: Icon(Icons.delete_outline, color: theme.secondary),
          ),
          onTap: () {
            Navigator.pop(context);
            if (bookmark.cfi.startsWith('demo:')) {
              final target = int.tryParse(bookmark.cfi.substring(5));
              if (target != null && target >= 0 && target < _demoPages.length) {
                _demoPageController.jumpToPage(target);
              }
            } else {
              _epubController.display(cfi: bookmark.cfi);
            }
          },
        );
      },
    );
  }

  List<_ChapterEntry> _flattenChapters(List<EpubChapter> source) {
    final result = <_ChapterEntry>[];
    void add(List<EpubChapter> chapters, int depth) {
      for (final chapter in chapters) {
        result.add(_ChapterEntry(chapter, depth));
        add(chapter.subitems, depth + 1);
      }
    }

    add(source, 0);
    return result;
  }
}

class _ChromeVisibility extends StatelessWidget {
  const _ChromeVisibility({
    required this.visible,
    required this.alignment,
    required this.child,
  });

  final bool visible;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = alignment == Alignment.topCenter;
    return Positioned(
      left: 0,
      right: 0,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : Offset(0, top ? -1.05 : 1.05),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ReaderSurface extends StatelessWidget {
  const _ReaderSurface({
    required this.color,
    required this.border,
    required this.child,
  });

  final Color color;
  final Border border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, border: border),
          child: child,
        ),
      ),
    );
  }
}

class _ReaderLoading extends StatelessWidget {
  const _ReaderLoading({required this.theme});

  final ReaderThemeSpec theme;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: theme.background,
        child: Center(
          child: CircularProgressIndicator(color: theme.accent, strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({
    required this.theme,
    required this.message,
    required this.onBack,
    this.onRetry,
  });

  final ReaderThemeSpec theme;
  final String message;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: theme.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 44,
                  color: theme.secondary,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.text, fontSize: 16),
                ),
                const SizedBox(height: 20),
                if (onRetry case final retry?) ...[
                  FilledButton.icon(
                    onPressed: retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tải lại'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Về thư viện'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Về thư viện'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterEntry {
  const _ChapterEntry(this.chapter, this.depth);

  final EpubChapter chapter;
  final int depth;
}

int readerTocIndexForHref(String currentHref, Iterable<String> tocHrefs) {
  final current = _NormalizedEpubHref.parse(currentHref);
  if (current.path.isEmpty) return -1;

  var firstDocumentMatch = -1;
  var index = 0;
  for (final href in tocHrefs) {
    final candidate = _NormalizedEpubHref.parse(href);
    if (candidate.path == current.path) {
      firstDocumentMatch = firstDocumentMatch < 0 ? index : firstDocumentMatch;
      if (current.fragment.isNotEmpty &&
          candidate.fragment == current.fragment) {
        return index;
      }
    }
    index++;
  }
  return firstDocumentMatch;
}

class _NormalizedEpubHref {
  const _NormalizedEpubHref(this.path, this.fragment);

  factory _NormalizedEpubHref.parse(String value) {
    var raw = value.trim().replaceAll('\\', '/');
    var fragment = '';
    final fragmentIndex = raw.indexOf('#');
    if (fragmentIndex >= 0) {
      fragment = _decodeHrefPart(raw.substring(fragmentIndex + 1));
      raw = raw.substring(0, fragmentIndex);
    }
    final queryIndex = raw.indexOf('?');
    if (queryIndex >= 0) raw = raw.substring(0, queryIndex);

    final segments = <String>[];
    for (final segment in raw.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(_decodeHrefPart(segment));
    }
    return _NormalizedEpubHref(segments.join('/'), fragment);
  }

  final String path;
  final String fragment;
}

String _decodeHrefPart(String value) {
  if (!value.contains('%')) return value;
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  } on ArgumentError {
    return value;
  }
}

class ReaderResumeCoordinator {
  ReaderResumeCoordinator({this.initialCfi, required double initialProgress})
    : initialProgress = initialProgress.clamp(0, 1);

  final String? initialCfi;
  final double initialProgress;
  bool _locationsReady = false;
  bool _initialCfiFailed = false;
  bool _fallbackIssued = false;
  bool _initialPositionSettled = false;

  bool get acceptsRelocations => _locationsReady;
  bool get hasDurablePosition => initialCfi != null || initialProgress > 0;

  ReaderResumeTarget? locationsLoaded({String? currentCfi}) {
    if (_locationsReady) return null;
    _locationsReady = true;
    if (_initialCfiFailed) return _issueProgressFallback();
    if (initialCfi case final cfi?) return ReaderResumeTarget.cfi(cfi);
    if (initialProgress > 0) {
      return ReaderResumeTarget.progress(initialProgress);
    }
    if (currentCfi case final cfi?) return ReaderResumeTarget.cfi(cfi);
    return null;
  }

  ReaderDisplayFailureAction displayFailed() {
    if (initialCfi == null || _initialPositionSettled || _fallbackIssued) {
      return const ReaderDisplayFailureAction.unhandled();
    }
    if (_initialCfiFailed) {
      return const ReaderDisplayFailureAction.handled();
    }
    _initialCfiFailed = true;
    return ReaderDisplayFailureAction.handled(
      target: _locationsReady ? _issueProgressFallback() : null,
    );
  }

  void relocationAccepted() {
    _initialPositionSettled = true;
  }

  ReaderResumeTarget _issueProgressFallback() {
    _fallbackIssued = true;
    return ReaderResumeTarget.progress(initialProgress);
  }
}

class ReaderDisplayFailureAction {
  const ReaderDisplayFailureAction.handled({this.target}) : handled = true;
  const ReaderDisplayFailureAction.unhandled() : handled = false, target = null;

  final bool handled;
  final ReaderResumeTarget? target;
}

class ReaderResumeTarget {
  const ReaderResumeTarget.cfi(this.cfi) : progress = null;
  const ReaderResumeTarget.progress(this.progress) : cfi = null;

  final String? cfi;
  final double? progress;
}

class _DemoPage {
  const _DemoPage({
    required this.chapter,
    required this.title,
    required this.body,
  });

  final int chapter;
  final String title;
  final String body;
}

const _demoChapterTitles = [
  'Thay đổi tư duy',
  'Tập trung vào điều quan trọng',
  'Biến kiến thức thành hành động',
];

const _demoPages = [
  _DemoPage(
    chapter: 1,
    title: 'Thay đổi tư duy',
    body:
        'Mỗi quyết định tốt bắt đầu từ một khoảng dừng đủ dài để nhìn vấn đề rõ hơn. Khi ta đọc chậm lại, những ý tưởng rời rạc dần kết nối thành một cách nhìn mới.',
  ),
  _DemoPage(
    chapter: 1,
    title: 'Một thay đổi nhỏ',
    body:
        'Tri thức chỉ tạo ra khác biệt khi được dùng. Chọn một ý tưởng vừa đọc, biến nó thành hành động nhỏ và lặp lại mỗi ngày. Cách làm mới sẽ dần trở thành năng lực thật.',
  ),
  _DemoPage(
    chapter: 2,
    title: 'Tập trung vào điều quan trọng',
    body:
        'Sự tập trung không phải là làm nhiều hơn. Đó là chủ động loại bỏ những việc không phục vụ mục tiêu chính, để thời gian và năng lượng đi đúng hướng.',
  ),
  _DemoPage(
    chapter: 2,
    title: 'Khoảng thời gian sâu',
    body:
        'Một giờ làm việc sâu có thể tạo ra kết quả lớn hơn nhiều giờ phản ứng liên tục. Hãy bảo vệ khoảng thời gian ấy như một cuộc hẹn quan trọng với chính mình.',
  ),
  _DemoPage(
    chapter: 3,
    title: 'Biến kiến thức thành hành động',
    body:
        'Hãy kết thúc mỗi chương bằng một câu hỏi cụ thể: ngày mai mình sẽ làm điều gì khác đi? Câu trả lời càng nhỏ và rõ, khả năng thực hiện càng cao.',
  ),
  _DemoPage(
    chapter: 3,
    title: 'Trang sách tiếp tục sống',
    body:
        'Đọc để hành động giúp cuốn sách tiếp tục sống trong những quyết định sau khi ta đã đóng trang cuối. Điều đáng nhớ nhất là thay đổi mà cuốn sách tạo ra.',
  ),
];
