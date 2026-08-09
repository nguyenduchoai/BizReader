import 'dart:io';
import 'dart:typed_data';

import 'package:bizreader_connect/src/models/device_config.dart';
import 'package:bizreader_connect/src/services/webdav_device_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('normalizes host without a scheme', () {
    const device = DeviceConfig(name: 'BizReader', host: '192.168.4.1');

    expect(device.baseUri.toString(), 'http://192.168.4.1');
  });

  test('encodes Vietnamese WebDAV file names as path segments', () {
    const device = DeviceConfig(name: 'BizReader', host: 'bizreader.local');
    final client = WebDavDeviceClient(device);

    final uri = client.pathUri('/Ebook/Muôn kiếp nhân sinh.epub');

    expect(uri.pathSegments, ['Ebook', 'Muôn kiếp nhân sinh.epub']);
    expect(uri.toString(), contains('Mu%C3%B4n%20ki%E1%BA%BFp'));
    client.close();
  });

  test('probes BizTransfer endpoint with session token', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response('{"state":"ready"}', 200);
    });
    const device = DeviceConfig(
      name: 'BizReader',
      host: 'http://192.168.1.25',
      transferToken: 'session-token',
    );
    final client = WebDavDeviceClient(device, client: mock);

    await client.probe();

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/bizreader/status');
    expect(captured.headers['X-BizReader-Token'], 'session-token');
    client.close();
  });

  test('uploads a book with token, size and SHA-256', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response('{"ok":true}', 201);
    });
    const device = DeviceConfig(
      name: 'BizReader',
      host: 'http://192.168.1.25',
      transferToken: 'session-token',
    );
    final directory = await Directory.systemTemp.createTemp('bizreader_test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/book.epub');
    await file.writeAsString('hello BizReader');
    final client = WebDavDeviceClient(device, client: mock);
    final progress = <int>[];

    await client.uploadFile(
      remotePath: '/Ebook/book.epub',
      file: file,
      contentType: 'application/epub+zip',
      onProgress: (sent, _) => progress.add(sent),
    );

    expect(captured.method, 'PUT');
    expect(captured.url.path, '/Ebook/book.epub');
    expect(captured.headers['X-BizReader-Token'], 'session-token');
    expect(
      captured.headers['X-Content-SHA256'],
      'e720dbe15d749e9d93d6bc8b6fea31f40b1fff59a5e5660a3b79c18827ac8ebc',
    );
    expect(captured.body, 'hello BizReader');
    expect(progress.last, await file.length());
    client.close();
  });

  test('streams a 30 MiB book without truncating it', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response('{"ok":true}', 201);
    });
    const device = DeviceConfig(
      name: 'BizReader',
      host: 'http://192.168.1.25',
      transferToken: 'session-token',
    );
    final directory = await Directory.systemTemp.createTemp('bizreader_30m');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/large-book.epub');
    const size = 30 * 1024 * 1024;
    await file.writeAsBytes(Uint8List(size), flush: true);
    final client = WebDavDeviceClient(device, client: mock);
    var lastProgress = 0;

    await client.uploadFile(
      remotePath: '/Ebook/large-book.epub',
      file: file,
      contentType: 'application/epub+zip',
      onProgress: (sent, total) {
        expect(sent, greaterThanOrEqualTo(lastProgress));
        expect(total, size);
        lastProgress = sent;
      },
    );

    expect(captured.bodyBytes.length, size);
    expect(lastProgress, size);
    expect(
      captured.headers['X-Content-SHA256'],
      '75c91b29d5522c8a97c779e50bc33f11e07ed37b2baa31c8c727016e92915c1d',
    );
    client.close();
  });
}
