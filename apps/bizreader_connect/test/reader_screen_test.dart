import 'dart:convert';
import 'dart:io';

import 'package:bizreader_connect/src/app_controller.dart';
import 'package:bizreader_connect/src/models/local_book.dart';
import 'package:bizreader_connect/src/models/reader_preferences.dart';
import 'package:bizreader_connect/src/screens/reader_screen.dart';
import 'package:bizreader_connect/src/services/device_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('reader stays horizontally paginated on a compact phone', (
    tester,
  ) async {
    const largeType = ReaderPreferences(
      themeId: 'paper',
      fontSize: 24,
      lineHeight: 2.05,
      margin: 40,
    );
    SharedPreferences.setMockInitialValues({
      'bizreader_reader_preferences_v1': jsonEncode(largeType.toJson()),
    });
    final controller = AppController(DevicePreferences());
    await controller.load();
    controller.enterDemoMode();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          controller: controller,
          book: LocalBook.demoLibrary().first,
        ),
      ),
    );
    await tester.pump();

    final finder = find.byKey(const Key('bizreader-demo-page-view'));
    final pageView = tester.widget<PageView>(finder);
    expect(pageView.scrollDirection, Axis.horizontal);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Tùy chỉnh đọc'));
    await tester.pumpAndSettle();
    expect(find.text('Tùy chỉnh đọc'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();

    await tester.fling(finder, const Offset(-260, 0), 900);
    await tester.pumpAndSettle();
    expect(pageView.controller!.page, 3);
    expect(tester.takeException(), isNull);

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byTooltip('Tùy chỉnh đọc')).dy, lessThan(800));
  });

  test('resume coordinator blocks early 0% and restores synced progress', () {
    final coordinator = ReaderResumeCoordinator(
      initialCfi: null,
      initialProgress: 0.62,
    );

    expect(coordinator.acceptsRelocations, isFalse);
    expect(coordinator.hasDurablePosition, isTrue);

    final target = coordinator.locationsLoaded(currentCfi: 'epubcfi(/6/2)');
    expect(target?.cfi, isNull);
    expect(target?.progress, 0.62);
    expect(coordinator.acceptsRelocations, isTrue);
    expect(coordinator.locationsLoaded(currentCfi: null), isNull);
  });

  test('resume coordinator gives a saved CFI priority over percentage', () {
    final coordinator = ReaderResumeCoordinator(
      initialCfi: 'epubcfi(/6/8)',
      initialProgress: 0.62,
    );

    final target = coordinator.locationsLoaded(currentCfi: null);

    expect(target?.cfi, 'epubcfi(/6/8)');
    expect(target?.progress, isNull);
  });

  test('invalid saved CFI falls back to durable progress exactly once', () {
    final coordinator = ReaderResumeCoordinator(
      initialCfi: 'epubcfi(/6/8)',
      initialProgress: 0.62,
    );

    final pending = coordinator.displayFailed();
    expect(pending.handled, isTrue);
    expect(pending.target, isNull);

    final duplicateBeforeLocations = coordinator.displayFailed();
    expect(duplicateBeforeLocations.handled, isTrue);
    expect(duplicateBeforeLocations.target, isNull);

    final fallback = coordinator.locationsLoaded(currentCfi: null);
    expect(fallback?.cfi, isNull);
    expect(fallback?.progress, 0.62);

    final fallbackFailure = coordinator.displayFailed();
    expect(fallbackFailure.handled, isFalse);
    expect(fallbackFailure.target, isNull);
  });

  test('TOC follows normalized href across cover pages and nested entries', () {
    const hrefs = [
      'OPS/Text/cover.xhtml',
      'OPS/Text/front-matter.xhtml',
      'OPS/Text/Chương 1.xhtml',
      'OPS/Text/Chương 1.xhtml#section-1',
      'OPS/Text/chapter-02.xhtml',
    ];

    expect(
      readerTocIndexForHref(
        '/OPS/Text/Ch%C6%B0%C6%A1ng%201.xhtml?layout=page',
        hrefs,
      ),
      2,
    );
    expect(
      readerTocIndexForHref(
        r'.\OPS\Text\Ch%C6%B0%C6%A1ng%201.xhtml#section-1',
        hrefs,
      ),
      3,
    );
    expect(
      readerTocIndexForHref(
        'OPS/Text/bad%ZZ.xhtml',
        const ['OPS/Text/bad%ZZ.xhtml'],
      ),
      0,
    );
  });

  testWidgets('reader Back still closes when progress persistence fails', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = _FailingProgressController();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Thư viện')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          controller: controller,
          book: LocalBook.demoLibrary().first,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.text('Thư viện'), findsOneWidget);
  });
}

class _FailingProgressController extends AppController {
  _FailingProgressController() : super(DevicePreferences());

  @override
  Future<void> updateBookProgress(
    String id, {
    required double progress,
    required int chapterNumber,
    required double chapterProgress,
    int? pageNumber,
    int? pageCount,
    String? epubCfi,
    bool clearEpubCfi = false,
    int? updatedAt,
  }) {
    return Future<void>.error(const FileSystemException('save failed'));
  }
}
