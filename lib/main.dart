import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'pages/login_page.dart';
import 'pages/shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'util/http_overrides.dart';
import 'widgets/ui_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = TrustedHttpOverrides();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  final state = await AppState.load();
  runApp(ChangeNotifierProvider.value(value: state, child: const DsmHelperApp()));
}

class DsmHelperApp extends StatelessWidget {
  const DsmHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    AppColors.accentOverride = state.accentColor;
    return MaterialApp(
      title: '群晖助手',
      debugShowCheckedModeBanner: false,
      themeMode: state.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().boot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final Widget child = switch (state.phase) {
      BootPhase.booting => const SplashPage(),
      BootPhase.needLogin => const LoginPage(),
      BootPhase.ready => AppShell(key: ValueKey(state.server?.host ?? 'shell')),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: child,
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: c.background),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 84),
              const SizedBox(height: 22),
              Text('群晖助手', style: context.texts.headlineMedium),
              const SizedBox(height: 8),
              Text('正在连接你的私有云…', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
              const SizedBox(height: 28),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
