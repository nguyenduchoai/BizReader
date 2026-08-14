import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EpubLocation round-trips through JSON', () {
    final json = {
      'startCfi': 'a',
      'endCfi': 'b',
      'startXpath': '/x',
      'endXpath': '/y',
      'progress': 0.5,
      'href': 'OPS/Text/chapter-01.xhtml',
      'spineIndex': 3,
      'pageNumber': 4,
      'pageCount': 9,
    };
    final loc = EpubLocation.fromJson(json);
    expect(loc.startCfi, 'a');
    expect(loc.progress, 0.5);
    expect(loc.href, 'OPS/Text/chapter-01.xhtml');
    expect(loc.spineIndex, 3);
    expect(loc.pageNumber, 4);
    expect(loc.pageCount, 9);
    expect(loc.toJson()['endXpath'], '/y');
  });

  test('EpubLocation defaults page fields for older payloads', () {
    final loc = EpubLocation.fromJson({
      'startCfi': 'a',
      'endCfi': 'b',
      'progress': 0.1,
    });

    expect(loc.spineIndex, 0);
    expect(loc.href, isEmpty);
    expect(loc.pageNumber, 0);
    expect(loc.pageCount, 1);
  });

  test('EpubChapter parses nested subitems', () {
    final chapters = parseChapterList([
      {
        'title': 'One',
        'href': 'ch1.xhtml',
        'id': 'c1',
        'subitems': [
          {'title': 'One.A', 'href': 'ch1a.xhtml', 'id': 'c1a', 'subitems': []},
        ],
      },
    ]);
    expect(chapters, hasLength(1));
    expect(chapters.single.title, 'One');
    expect(chapters.single.subitems.single.href, 'ch1a.xhtml');
  });

  test('parseChapterList tolerates non-string keys (web dartify output)', () {
    // dartify can yield Map<Object?, Object?>; parseChapterList must cope.
    final chapters = parseChapterList(<Object?, Object?>{
      'title': 'T',
      'href': 'h',
      'id': 'i',
      'subitems': <Object?>[],
    });
    expect(chapters.single.title, 'T');
  });

  test('EpubSearchResult parses', () {
    final r = EpubSearchResult.fromJson({
      'cfi': 'c',
      'excerpt': 'e',
      'xpath': '/p',
    });
    expect(r.cfi, 'c');
    expect(r.excerpt, 'e');
  });

  test('EpubTextExtractRes parses', () {
    final r = EpubTextExtractRes.fromJson({
      'text': 'hello',
      'cfiRange': 'r',
      'xpathRange': null,
    });
    expect(r.text, 'hello');
    expect(r.cfiRange, 'r');
    expect(r.xpathRange, isNull);
  });

  test('EpubDisplaySettings serializes with defaults', () {
    final s = EpubDisplaySettings();
    final json = s.toJson();
    expect(json['flow'], 'paginated');
    expect(json['manager'], 'continuous');
    expect(EpubDisplaySettings.fromJson(json).spread, EpubSpread.auto);
  });
}
