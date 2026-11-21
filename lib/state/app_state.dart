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
  static const _kHomeWidgets = 'home_widgets_v2';
  static const _kDownloadTools = 'download_tools_v2';
  static const _kActiveTool = 'active_download_tool_v2';
  static const _kPhotoSource = 'photo_source_v2';
  static const _kAvatar = 'avatar_path_v2';
  static const _kCatalogCache = 'catalog_cache_v1';
  static const _kAccent = 'accent_color_v2';
  static const _kDockerMirror = 'docker_mirror_v1';

  BootPhase phase = BootPhase.booting;
  ThemeMode themeMode = ThemeMode.light;
  List<DsmServer> servers = [];
  DsmServer? server;
  DsmService? service;
  SystemInfo? systemInfo;
  StorageSnapshot? storage;
  Utilization? utilization;
  String? utilizationError;
  String? bootError;
  bool demo = false;

  /// 首页可编辑的卡片顺序。
  List<HomeWidgetType> homeWidgets = [
    HomeWidgetType.resource,
    HomeWidgetType.storage,
    HomeWidgetType.transfers,
  ];

  List<DownloadTool> downloadTools = [];
  String? activeToolId;
  PhotoSource photoSource = const PhotoSource();

  int? latencyMs;
  bool? online;
  String? customAvatarPath;
  List<CatalogPackage> catalogCache = [];
  Color accentColor = const Color(0xFF6F86A8);
  String dockerMirror = '';

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

    final rawWidgets = _prefs.getStringList(_kHomeWidgets);
    if (rawWidgets != null && rawWidgets.isNotEmpty) {
      final parsed = <HomeWidgetType>[];
      for (final name in rawWidgets) {
        final match = HomeWidgetType.values.where((e) => e.name == name);
        if (match.isNotEmpty && !parsed.contains(match.first)) parsed.add(match.first);
      }
      if (parsed.isNotEmpty) homeWidgets = parsed;
    }

    final rawTools = _prefs.getString(_kDownloadTools);
    if (rawTools != null && rawTools.isNotEmpty) {
      try {
        final list = jsonDecode(rawTools) as List;
        downloadTools = list.whereType<Map>().map((e) => DownloadTool.fromJson(e.cast<String, dynamic>())).where((t) => t.type == DownloadToolType.qbittorrent || t.type == DownloadToolType.aria2).toList();
      } catch (_) {
        downloadTools = [];
      }
    }
    customAvatarPath = _prefs.getString(_kAvatar);
    dockerMirror = _prefs.getString(_kDockerMirror) ?? '';
    final accentValue = _prefs.getInt(_kAccent);
    if (accentValue != null) accentColor = Color(accentValue);
    final rawCatalog = _prefs.getString(_kCatalogCache);
    if (rawCatalog != null && rawCatalog.isNotEmpty) {
      try {
        final list = jsonDecode(rawCatalog) as List;
        catalogCache = list.whereType<Map>().map((e) => CatalogPackage.fromJson(e.cast<String, dynamic>())).toList();
      } catch (_) {
        catalogCache = [];
      }
    }
    activeToolId = _prefs.getString(_kActiveTool);
    if (activeToolId != null && downloadTools.every((t) => t.id != activeToolId)) {
      activeToolId = null;
    }

    final rawPhoto = _prefs.getString(_kPhotoSource);
    if (rawPhoto != null && rawPhoto.isNotEmpty) {
      try {
        photoSource = PhotoSource.fromJson((jsonDecode(rawPhoto) as Map).cast<String, dynamic>());
        _trustPhotoHost();
      } catch (_) {}
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
    systemInfo = await _guard(() => s.systemInfo());
    storage = await _guard(() => s.storage());
    try {
      utilization = await s.utilization();
      utilizationError = null;
    } on DsmException catch (e) {
      utilization = null;
      utilizationError = e.message;
    } catch (e) {
      utilization = null;
      utilizationError = '$e';
    }
    if (notify) notifyListeners();
  }

  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (_) {
      return null;
    }
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
    await measureLatency();
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
    utilizationError = null;
    latencyMs = 4;
    online = true;
    if (downloadTools.isEmpty) {
      downloadTools = [DownloadTool(id: 'demo-qb', type: DownloadToolType.qbittorrent, name: '演示 qBittorrent', host: 'demo', port: '8080')];
      activeToolId = downloadTools.first.id;
    }
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
    utilizationError = null;
    demo = false;
    latencyMs = null;
    online = null;
    TrustedHttpOverrides.trustedHost = null;
    phase = BootPhase.needLogin;
    notifyListeners();
  }

  Future<void> refreshHome() async {
    final s = service;
    if (s == null) return;
    systemInfo = await _guard(() => s.systemInfo());
    storage = await _guard(() => s.storage());
    try {
      utilization = await s.utilization();
      utilizationError = null;
    } on DsmException catch (e) {
      utilization = null;
      utilizationError = e.message;
    } catch (e) {
      utilization = null;
      utilizationError = '$e';
    }
    await measureLatency(notify: false);
    notifyListeners();
  }

  Future<void> refreshUtilization() async {
    final s = service;
    if (s == null) return;
    try {
      utilization = await s.utilization();
      utilizationError = null;
    } on DsmException catch (e) {
      utilizationError = e.message;
    } catch (e) {
      utilizationError = '$e';
    }
    notifyListeners();
  }

  Future<void> measureLatency({bool notify = true}) async {
    final s = service;
    if (s == null) return;
    try {
      latencyMs = await s.ping();
      online = true;
    } catch (_) {
      online = false;
      latencyMs = null;
    }
    if (notify) notifyListeners();
  }

  Future<void> setDockerMirror(String mirror) async {
    dockerMirror = mirror.trim();
    await _prefs.setString(_kDockerMirror, dockerMirror);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    accentColor = color;
    await _prefs.setInt(_kAccent, color.toARGB32());
    notifyListeners();
  }

  Future<void> saveCatalogCache(List<CatalogPackage> packages) async {
    catalogCache = packages;
    await _prefs.setString(_kCatalogCache, jsonEncode(packages.map((e) => e.toJson()).toList()));
  }

  Future<void> setCustomAvatar(String? path) async {
    customAvatarPath = (path == null || path.isEmpty) ? null : path;
    if (customAvatarPath == null) {
      await _prefs.remove(_kAvatar);
    } else {
      await _prefs.setString(_kAvatar, customAvatarPath!);
    }
    notifyListeners();
  }
  Map<String, String> get imageHeaders => service?.imageHeaders ?? const {};

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

  // ---------- 首页组件 ----------

  Future<void> setHomeWidgets(List<HomeWidgetType> widgets) async {
    homeWidgets = List.unmodifiable(widgets);
    await _prefs.setStringList(_kHomeWidgets, homeWidgets.map((e) => e.name).toList());
    notifyListeners();
  }

  Future<void> toggleHomeWidget(HomeWidgetType type, bool enabled) async {
    final next = [...homeWidgets];
    if (enabled && !next.contains(type)) {
      next.add(type);
    } else if (!enabled) {
      next.remove(type);
    }
    await setHomeWidgets(next);
  }

  // ---------- 下载工具 ----------

  Future<void> addDownloadTool(DownloadTool tool) async {
    final index = downloadTools.indexWhere((t) => t.id == tool.id);
    if (index >= 0) {
      downloadTools[index] = tool;
    } else {
      downloadTools = [...downloadTools, tool];
    }
    activeToolId ??= tool.id;
    await _saveTools();
    notifyListeners();
  }

  Future<void> removeDownloadTool(String id) async {
    downloadTools = downloadTools.where((t) => t.id != id).toList();
    if (activeToolId == id) activeToolId = downloadTools.isEmpty ? null : downloadTools.first.id;
    await _saveTools();
    notifyListeners();
  }

  Future<void> setActiveTool(String id) async {
    activeToolId = id;
    await _prefs.setString(_kActiveTool, id);
    notifyListeners();
  }

  DownloadTool? get activeTool {
    if (downloadTools.isEmpty) return null;
    final id = activeToolId;
    if (id == null) return downloadTools.first;
    final matches = downloadTools.where((t) => t.id == id).toList();
    return matches.isEmpty ? downloadTools.first : matches.first;
  }

  Future<void> _saveTools() async {
    await _prefs.setString(_kDownloadTools, jsonEncode(downloadTools.map((e) => e.toJson()).toList()));
    if (activeToolId != null) await _prefs.setString(_kActiveTool, activeToolId!);
  }

  // ---------- 相册数据源 ----------

  Future<void> setPhotoSource(PhotoSource source) async {
    photoSource = source;
    await _prefs.setString(_kPhotoSource, jsonEncode(source.toJson()));
    _trustPhotoHost();
    notifyListeners();
  }

  void _trustPhotoHost() {
    if (photoSource.type != PhotoSourceType.immich || photoSource.immichUrl.isEmpty) return;
    final uri = Uri.tryParse(photoSource.immichUrl);
    if (uri != null && uri.host.isNotEmpty && photoSource.trustSelfSigned) {
      TrustedHttpOverrides.extraTrustedHosts.add(uri.host);
    }
  }

  String get accountInitial {
    final account = server?.account ?? '?';
    return account.isEmpty ? '?' : account.substring(0, 1).toUpperCase();
  }

  /// 首页标题：优先设备名，其次用户备注，最后账号。
  String get deviceTitle {
    final hostname = systemInfo?.hostname ?? '';
    if (hostname.isNotEmpty) return hostname;
    final note = server?.note ?? '';
    if (note.isNotEmpty) return note;
    return server?.account ?? '群晖设备';
  }
}
