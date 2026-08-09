import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'dashboard_screen.dart';
import 'device_settings_screen.dart';
import 'device_setup_screen.dart';
import 'library_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        controller: widget.controller,
        openLibrary: () => setState(() => _index = 1),
        openDevice: () => setState(() => _index = 2),
      ),
      LibraryScreen(controller: widget.controller),
      if (widget.controller.device.isConfigured)
        DeviceSettingsScreen(controller: widget.controller)
      else
        DeviceSetupScreen(controller: widget.controller),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Thư viện',
          ),
          NavigationDestination(
            icon: Icon(Icons.tablet_android_outlined),
            selectedIcon: Icon(Icons.tablet_android),
            label: 'Thiết bị',
          ),
        ],
      ),
    );
  }
}
