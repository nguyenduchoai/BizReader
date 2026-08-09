import 'package:bizreader_connect/src/app.dart';
import 'package:bizreader_connect/src/app_controller.dart';
import 'package:bizreader_connect/src/services/device_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows device setup when no device is stored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(DevicePreferences());
    await controller.load();

    await tester.pumpWidget(BizReaderApp(controller: controller));

    expect(find.text('Kết nối BizReader'), findsOneWidget);
    expect(find.text('Tìm BizReader'), findsOneWidget);
    expect(
      find.textContaining('Truyền tệp > Kết nối App'),
      findsOneWidget,
    );
    expect(find.text('Hoài Nguyễn'), findsNothing);
  });

  testWidgets('dashboard fits a compact Android viewport', (tester) async {
    SharedPreferences.setMockInitialValues({
      'device_name': 'BizReader',
      'device_host': '192.168.4.1',
    });
    final controller = AppController(DevicePreferences());
    await controller.load();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(BizReaderApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Ứng dụng thiết bị'), findsOneWidget);
    expect(find.text('Hoài Nguyễn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
