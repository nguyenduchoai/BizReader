import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/services/device_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(DevicePreferences());
  await controller.load();
  runApp(BizReaderApp(controller: controller));
}
