import 'package:flutter/material.dart';

import '../widgets/nav_bar.dart';
import 'apps_page.dart';
import 'downloads_page.dart';
import 'files_page.dart';
import 'home_page.dart';
import 'settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _switchTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            IndexedStack(
              index: _index,
              children: [
                HomePage(onOpenTab: _switchTab),
                FilesPage(active: _index == 1),
                DownloadsPage(active: _index == 2),
                AppsPage(active: _index == 3),
                const SettingsPage(),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: AppBottomNav(index: _index, onChanged: _switchTab),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
