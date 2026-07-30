import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'screens/device_setup_screen.dart';
import 'screens/home_shell.dart';

class BizReaderApp extends StatelessWidget {
  const BizReaderApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF17191C);
    const paper = Color(0xFFF4F5F7);
    const green = Color(0xFF3D7A57);
    const blue = Color(0xFF356A8A);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.light,
          surface: Colors.white,
        ).copyWith(
          primary: ink,
          secondary: green,
          tertiary: blue,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: paper,
          outline: const Color(0xFFD6D9DE),
        );

    return MaterialApp(
      title: 'BizReader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: paper,
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFD6D9DE)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: Color(0xFFC8CCD2)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.device.isConfigured) {
            return DeviceSetupScreen(controller: controller);
          }
          return HomeShell(controller: controller);
        },
      ),
    );
  }
}
