import 'package:flutter_epub_viewer/src/platform/epub_navigation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EPUB WebView navigation policy', () {
    test('blocks network subresources except for the macOS asset server', () {
      expect(shouldBlockEpubNetworkLoads(isMacOS: false), isTrue);
      expect(shouldBlockEpubNetworkLoads(isMacOS: true), isFalse);
    });

    test('allows the package renderer and its file assets', () {
      expect(
        isAllowedEpubNavigation(
          Uri.parse(
            'file:///data/user/0/app/flutter_assets/packages/'
            'flutter_epub_viewer/lib/assets/webpage/html/swipe.html',
          ),
          isMacOS: false,
        ),
        isTrue,
      );
      expect(
        isAllowedEpubNavigation(
          Uri.parse(
            'file:///private/app/flutter_assets/packages/'
            'flutter_epub_viewer/lib/assets/webpage/dist/epub.js',
          ),
          isMacOS: false,
        ),
        isTrue,
      );
    });

    test('allows only the expected macOS localhost asset server', () {
      expect(
        isAllowedEpubNavigation(
          Uri.parse(
            'http://localhost:8181/packages/flutter_epub_viewer/'
            'lib/assets/webpage/html/swipe.html',
          ),
          isMacOS: true,
          localhostPort: 8181,
        ),
        isTrue,
      );
      expect(
        isAllowedEpubNavigation(
          Uri.parse(
            'http://127.0.0.1:8181/packages/flutter_epub_viewer/'
            'lib/assets/webpage/html/swipe.html',
          ),
          isMacOS: true,
          localhostPort: 8181,
        ),
        isFalse,
      );
      expect(
        isAllowedEpubNavigation(
          Uri.parse(
            'http://localhost:9999/packages/flutter_epub_viewer/'
            'lib/assets/webpage/html/swipe.html',
          ),
          isMacOS: true,
          localhostPort: 8181,
        ),
        isFalse,
      );
    });

    test('allows internal subframe documents', () {
      expect(
        isAllowedEpubNavigation(Uri.parse('about:blank'), isMacOS: false),
        isTrue,
      );
      expect(
        isAllowedEpubNavigation(
          Uri.parse('blob:file:///2eaa74bf-1234'),
          isMacOS: false,
          isMainFrame: false,
        ),
        isTrue,
      );
      expect(
        isAllowedEpubNavigation(
          Uri.parse('data:text/html,chapter'),
          isMacOS: false,
          isMainFrame: false,
        ),
        isTrue,
      );
    });

    test('blocks external, arbitrary file, and main-frame document URLs', () {
      for (final url in <String>[
        'https://example.com',
        'http://example.com',
        'file:///sdcard/private.txt',
        'file:///sdcard/x/flutter_assets/packages/flutter_epub_viewer/lib/'
            'assets/webpage/html/swipe.html',
        'file:///data/flutter_assets/packages/flutter_epub_viewer/lib/'
            'assets/webpage/../../../../private.txt',
        'content://com.example/private',
        'javascript:alert(1)',
      ]) {
        expect(
          isAllowedEpubNavigation(Uri.parse(url), isMacOS: false),
          isFalse,
          reason: url,
        );
      }
      expect(
        isAllowedEpubNavigation(
          Uri.parse('blob:file:///2eaa74bf-1234'),
          isMacOS: false,
        ),
        isFalse,
      );
      expect(
        isAllowedEpubNavigation(
          Uri.parse('data:text/html,chapter'),
          isMacOS: false,
        ),
        isFalse,
      );
    });
  });
}
