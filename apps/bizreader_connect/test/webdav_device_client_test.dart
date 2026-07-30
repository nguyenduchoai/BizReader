import 'package:bizreader_connect/src/models/device_config.dart';
import 'package:bizreader_connect/src/services/webdav_device_client.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
