import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dsm/dsm_client.dart';
import '../dsm/dsm_service.dart';
import '../dsm/models.dart';
import '../util/http_overrides.dart';

enum BootPhase { booting, needLogin, ready }

class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;

  AppState._(this._prefs);

  static const _kServers = 'servers_v2';
  static const _kThemeMode = 'theme_mode_v2';
  static const _kCurrent = 'current_server_v2';

  BootPhase phase = BootPhase.booting;
  ThemeMode themeMode = ThemeMode.light;
  List<DsmServer> servers = [];
  DsmServer? server;
  DsmService? service;
  SystemInfo? systemInfo;
  StorageSnapshot? storage;
  Utilization? utilization;
  String? bootError;
  bool demo = false;

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final state = AppState._(prefs);
    state._restore();
    return state;
  }

  void _restore() {
    final theme = _prefs.getInt(_kThemeMode) ?? 0;
    themeMode = switch (theme) {
      1 => ThemeMode.dark,
      2 => ThemeMode.system,
      _ => ThemeMode.light,
    };
    final rawServers = _prefs.getString(_kServers);
    if (rawServers != null && rawServers.isNotEmpty) {
      try {
        final list = jsonDecode(rawServers) as List;
        servers = list.whereType<Map>().map((e) => DsmServer.fromJson(e.cast<String, dynamic>())).toList();
      } catch (_) {
        servers = [];
      }
    }
    final current = _prefs.getString(_kCurrent);
    if (current != null) {
      final matches = servers.where((s) => '${s.host}:${s.port}:${s.account}' == current).toList();
      if (matches.isNotEmpty) server = matches.first;
    }
  }

  Future<void> boot() async {
    if (const bool.fromEnvironment('DSM_DEMO')) {
      await enterDemo();
      return;
    }
    phase = BootPhase.booting;
    notifyListeners();
    final candidate = server;
    if (candidate != null && candidate.autoLogin && (candidate.password?.isNotEmpty ?? false)) {
      try {
        await _connect(candidate, candidate.password!);
        phase = BootPhase.ready;
        notifyListeners();
        return;
      } on DsmException catch (e) {
        bootError = e.message;
      } catch (e) {
        bootError = '$e';
      }
    }
    phase = BootPhase.needLogin;
    notifyListeners();
  }

  Future<void> _connect(DsmServer target, String password, {String otp = '', bool rememberDevice = false}) async {
    final s = await DsmService.connect(target, password: password, otpCode: otp, rememberDevice: rememberDevice);
    s.client.onAuthExpired = _handleAuthExpired;
    TrustedHttpOverrides.trustedHost = target.trustSelfSigned ? target.host : null;
    service = s;
    server = target;
    await _refreshCore(notify: false);
  }

  void _handleAuthExpired() {
    if (phase != BootPhase.ready) return;
    bootError = '登录会话已过期，请重新登录';
    signOut(forgetPassword: false);
  }

  Future<void> _refreshCore({bool notify = true}) async {
    final s = service;
    if (s == null) return;
    try {
      systemInfo = await s.systemInfo();
    } catch (_) {
      systemInfo = null;
    }
    try {
      storage = await s.storage();
    } catch (_) {
      storage = null;
    }
    try {
      utilization = await s.utilization();
    } catch (_) {
      utilization = null;
    }
    if (notify) notifyListeners();
  }

  Future<void> signIn(
    DsmServer target, {
    required String password,
    String otp = '',
    bool rememberDevice = false,
    bool savePassword = true,
  }) async {
    final normalized = target.copyWith(password: savePassword ? password : null);
    await _connect(normalized, password, otp: otp, rememberDevice: rememberDevice);
    demo = false;
    bootError = null;
    server = normalized;
    final key = '${normalized.host}:${normalized.port}:${normalized.account}';
    final index = servers.indexWhere((s) => '${s.host}:${s.port}:${s.account}' == key);
    if (index >= 0) {
      servers[index] = normalized;
    } else {
      servers.insert(0, normalized);
    }
    if (!normalized.autoLogin) {
      servers = servers.map((s) => s == normalized ? normalized : s.copyWith(autoLogin: false)).toList();
    }
    await _prefs.setString(_kServers, jsonEncode(servers.map((e) => e.toJson()).toList()));
    await _prefs.setString(_kCurrent, key);
    phase = BootPhase.ready;
    notifyListeners();
  }

  Future<void> enterDemo() async {
    demo = true;
    TrustedHttpOverrides.trustedHost = null;
    server = const DsmServer(host: '192.168.1.10', port: '5000', account: 'keduoli', note: '演示 · 我的黑群晖');
    service = DsmService.demoMode();
    systemInfo = null;
    storage = null;
    utilization = null;
    await _refreshCore(notify: false);
    phase = BootPhase.ready;
    notifyListeners();
  }

  Future<void> signOut({bool forgetPassword = false}) async {
    if (service != null && !demo) {
      service!.client.onAuthExpired = null;
      try {
        await service!.client.logout();
      } catch (_) {}
    }
    if (forgetPassword && server != null) {
      final key = '${server!.host}:${server!.port}:${server!.account}';
      final index = servers.indexWhere((s) => '${s.host}:${s.port}:${s.account}' == key);
      if (index >= 0) {
        servers[index] = servers[index].copyWith(password: null, autoLogin: false);
        await _prefs.setString(_kServers, jsonEncode(servers.map((e) => e.toJson()).toList()));
      }
    }
    service = null;
    server = null;
    systemInfo = null;
    storage = null;
    utilization = null;
    demo = false;
    TrustedHttpOverrides.trustedHost = null;
    phase = BootPhase.needLogin;
    notifyListeners();
  }

  Future<void> refreshHome() async {
    final s = service;
    if (s == null) return;
    try {
      systemInfo = await s.systemInfo();
    } catch (_) {}
    try {
      storage = await s.storage();
    } catch (_) {}
    try {
      utilization = await s.utilization();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshUtilization() async {
    final s = service;
    if (s == null) return;
    utilization = await s.utilization();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _prefs.setInt(_kThemeMode, switch (mode) { ThemeMode.light => 0, ThemeMode.dark => 1, ThemeMode.system => 2 });
    notifyListeners();
  }

  Future<void> saveServerNote(String note) async {
    if (server == null) return;
    server = server!.copyWith(note: note);
    final key = '${server!.host}:${server!.port}:${server!.account}';
    final index = servers.indexWhere((s) => '${s.host}:${s.port}:${s.account}' == key);
    if (index >= 0) {
      servers[index] = server!;
      await _prefs.setString(_kServers, jsonEncode(servers.map((e) => e.toJson()).toList()));
    }
    notifyListeners();
  }

  String get accountInitial {
    final account = server?.account ?? '?';
    return account.isEmpty ? '?' : account.substring(0, 1).toUpperCase();
  }
}
