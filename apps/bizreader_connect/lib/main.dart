import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/services/device_preferences.dart';
import 'src/services/legal_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBizReaderLicenses();
  final controller = AppController(DevicePreferences());
  await controller.load();
  runApp(BizReaderApp(controller: controller));
}
