import 'package:bizreader_connect/src/models/biz_transfer_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses ready BizTransfer status', () {
    final status = BizTransferStatus.fromJson({
      'state': 'ready',
      'message': 'Sẵn sàng nhận sách',
      'request': 'a1b2c3',
      'device': 'BizReader-A1B2',
      'ip': '192.168.1.25',
      'port': 80,
      'token': 'abc123',
    });

    expect(status.isReady, isTrue);
    expect(status.isError, isFalse);
    expect(status.requestId, 'a1b2c3');
    expect(status.deviceName, 'BizReader-A1B2');
    expect(status.ip, '192.168.1.25');
    expect(status.token, 'abc123');
  });

  test('recognizes firmware error state', () {
    final status = BizTransferStatus.fromJson({
      'state': 'error',
      'message': 'Chưa có Wi-Fi đã lưu',
    });

    expect(status.isReady, isFalse);
    expect(status.isError, isTrue);
  });
}
