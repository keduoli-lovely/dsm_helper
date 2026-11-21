import '../demo/demo_store.dart';
import 'dsm_client.dart';
import 'models.dart';

/// 面向页面的 DSM 业务接口：真实设备走 WebAPI，演示模式走本地数据。
class DsmService {
  final DsmServer server;
  final bool demo;
  final DsmClient? _client;

  DsmService._({required this.server, required this.demo, DsmClient? client}) : _client = client;

  DsmClient get client {
    final c = _client;
    if (c == null) throw const DsmException(-10, '当前为演示模式，未连接设备');
    return c;
  }

  bool get connected => demo || (client.connected);

  /// 登录并建立会话。
  static Future<DsmService> connect(
    DsmServer server, {
    required String password,
    String otpCode = '',
    bool rememberDevice = false,
    String? sid,
    String? cookie,
  }) async {
    final client = DsmClient(server: server, sid: sid ?? '', cookie: cookie ?? '');
    await client.login(
      account: server.account,
      password: password,
      otpCode: otpCode,
      rememberDevice: rememberDevice,
    );
    await client.loadApiInfo();
    return DsmService._(server: server, demo: false, client: client);
  }

  static DsmService demoMode() => DsmService._(
        server: const DsmServer(host: '192.168.1.10', port: '5000', account: 'keduoli', note: '我的黑群晖'),
        demo: true,
      );

  Future<SystemInfo> systemInfo() async {
    if (demo) return DemoStore.instance.systemInfo;
    final data = await client.callMap(api: 'SYNO.Core.System', method: 'info', version: 1);
    return SystemInfo.fromJson(data);
  }

  Future<Utilization> utilization() async {
    if (demo) return DemoStore.instance.nextUtilization();
    DsmException? lastError;
    final attempts = <Map<String, Object?>>[
      {'version': 2, 'type': 'current', 'resource': ['cpu', 'memory', 'network', 'disk', 'space']},
      {'version': 1, 'type': 'current', 'resource': ['cpu', 'memory', 'network', 'disk', 'space']},
      {'version': 1, 'type': 'current', 'resource': 'cpu,memory,network,disk'},
    ];
    for (final attempt in attempts) {
      try {
        final data = await client.callMap(
          api: 'SYNO.Core.System.Utilization',
          method: 'get',
          version: attempt['version'] as int,
          params: {'type': attempt['type'], 'resource': attempt['resource']},
        );
        if (data.containsKey('cpu') || data.containsKey('memory') || data.containsKey('network') || data.containsKey('disk')) {
          return Utilization.fromJson(data);
        }
      } on DsmException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const DsmException(-1, '设备没有返回资源监控数据');
  }

  /// 网络往返延迟（毫秒），用于首页连接状态。
  Future<int> ping() async {
    if (demo) return 4;
    try {
      return await client.ping();
    } on DsmException {
      rethrow;
    }
  }

  Future<StorageSnapshot> storage() async {
    if (demo) return DemoStore.instance.storage;
    final data = await client.callMap(api: 'SYNO.Storage.CGI.Storage', method: 'load_info', version: 1);
    final volumes = <VolumeInfo>[];
    final rawVolumes = data['volumes'] ?? data['volume'];
    if (rawVolumes is List) {
      for (final item in rawVolumes) {
        if (item is Map) volumes.add(VolumeInfo.fromJson(item.cast<String, dynamic>()));
      }
    }
    final disks = <DiskInfo>[];
    final rawDisks = data['disks'];
    if (rawDisks is List) {
      for (final item in rawDisks) {
        if (item is Map) disks.add(DiskInfo.fromJson(item.cast<String, dynamic>()));
      }
    }
    return StorageSnapshot(volumes: volumes, disks: disks);
  }

  Future<List<ShareInfo>> shares() async {
    if (demo) return DemoStore.instance.shares();
    final data = await client.callMap(
      api: 'SYNO.FileStation.List',
      method: 'list_share',
      version: 2,
      params: {
        'additional': ['size', 'owner', 'time', 'perm'],
        'offset': 0,
        'limit': 1000,
        'sort_by': 'name',
        'sort_direction': 'asc',
      },
    );
    final list = (data['shares'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => ShareInfo.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<List<FileEntry>> files(String path) async {
    if (demo) return DemoStore.instance.list(path);
    final data = await client.callMap(
      api: 'SYNO.FileStation.List',
      method: 'list',
      version: 2,
      params: {
        'folder_path': path,
        'additional': ['size', 'owner', 'time', 'perm', 'type'],
        'offset': 0,
        'limit': 1000,
        'sort_by': 'name',
        'sort_direction': 'asc',
      },
    );
    final list = (data['files'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => FileEntry.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<void> createFolder(String parentPath, String name) async {
    if (demo) return DemoStore.instance.createFolder(parentPath, name);
    await client.callMap(
      api: 'SYNO.FileStation.CreateFolder',
      method: 'create',
      version: 2,
      params: {'folder_path': parentPath, 'name': name, 'force_parent': false},
    );
  }

  Future<void> rename(String path, String newName) async {
    if (demo) return DemoStore.instance.rename(path, newName);
    await client.callMap(
      api: 'SYNO.FileStation.Rename',
      method: 'rename',
      version: 2,
      params: {'path': path, 'name': newName},
    );
  }

  Future<void> delete(List<String> paths) async {
    if (demo) {
      for (final p in paths) {
        DemoStore.instance.delete(p);
      }
      return;
    }
    await client.callMap(
      api: 'SYNO.FileStation.Delete',
      method: 'start',
      version: 2,
      params: {'path': paths},
    );
  }

  Future<void> upload(String localPath, String destDir) async {
    if (demo) return;
    await client.uploadFile(localPath, destDir);
  }

  Future<void> uploadStream({
    required String filename,
    required Stream<List<int>> stream,
    required int length,
    required String destDir,
  }) async {
    if (demo) return;
    await client.uploadStream(filename: filename, stream: stream, length: length, destDir: destDir);
  }

  Uri downloadUri(String path, {bool open = false}) {
    return client.downloadUri(path, open: open);
  }

  Uri? thumbnailUri(String path, {String size = 'small'}) {
    if (demo) return null;
    return client.thumbnailUri(path, size: size);
  }

  // ---------- Download Station ----------

  Future<List<DownloadTask>> downloads() async {
    if (demo) return DemoStore.instance.downloads();
    try {
      final data = await client.callMap(
        api: 'SYNO.DownloadStation.Task',
        method: 'list',
        version: 1,
        params: {
          'offset': 0,
          'limit': 200,
          'additional': ['detail', 'transfer', 'file'],
        },
      );
      final tasks = (data['tasks'] as List?) ?? const [];
      return tasks.whereType<Map>().map((e) => DownloadTask.fromJson(e.cast<String, dynamic>())).toList();
    } on DsmException catch (e) {
      if (e.code == 102 || e.code == 103 || e.code == 104 || e.code == 105) {
        return _downloadsV2();
      }
      rethrow;
    }
  }

  Future<List<DownloadTask>> _downloadsV2() async {
    final data = await client.callMap(
      api: 'SYNO.DownloadStation2.Task',
      method: 'list',
      version: 1,
      params: {'offset': 0, 'limit': 200, 'additional': ['detail', 'transfer']},
    );
    final tasks = (data['tasks'] as List?) ?? const [];
    return tasks.whereType<Map>().map((e) {
      final map = e.cast<String, dynamic>();
      final additional = (map['additional'] as Map?)?.cast<String, dynamic>() ?? const {};
      final transfer = (additional['transfer'] as Map?)?.cast<String, dynamic>() ?? const {};
      return DownloadTask(
        id: '${map['id']}',
        title: '${map['title'] ?? '未命名任务'}',
        status: '${map['status'] ?? ''}',
        size: (map['size'] as num?)?.toInt() ?? 0,
        downloaded: (transfer['size_downloaded'] as num?)?.toInt() ?? 0,
        speedDownload: (transfer['speed_download'] as num?)?.toInt() ?? 0,
        destination: '${(additional['detail'] as Map?)?['destination'] ?? ''}',
      );
    }).toList();
  }

  Future<void> addDownload(String uri, {String? destination}) async {
    if (demo) return DemoStore.instance.addDownload(uri);
    try {
      await client.callMap(
        api: 'SYNO.DownloadStation.Task',
        method: 'create',
        version: 3,
        params: {'uri': uri, if (destination != null && destination.isNotEmpty) 'destination': destination},
      );
    } on DsmException catch (e) {
      if (e.code == 102 || e.code == 103 || e.code == 104) {
        await client.callMap(
          api: 'SYNO.DownloadStation2.Task',
          method: 'create',
          version: 1,
          params: {'type': 'url', 'url': [uri], 'destination': destination ?? ''},
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> downloadAction(String action, List<String> ids) async {
    if (demo) {
      for (final id in ids) {
        DemoStore.instance.downloadAction(action, id);
      }
      return;
    }
    try {
      await client.callMap(
        api: 'SYNO.DownloadStation.Task',
        method: action,
        version: 1,
        params: {'id': ids},
      );
    } on DsmException catch (e) {
      if (e.code == 102 || e.code == 103 || e.code == 104) {
        await client.callMap(
          api: 'SYNO.DownloadStation2.Task',
          method: action,
          version: 1,
          params: {'id': ids},
        );
        return;
      }
      rethrow;
    }
  }

  // ---------- 套件 ----------

  Future<List<DsmPackage>> packages() async {
    if (demo) return DemoStore.instance.packages();
    Map<String, dynamic> data;
    try {
      // DSM 6 与部分 DSM 7 在 v1 才会返回 status 字段，优先用 v1。
      data = await client.callMap(
        api: 'SYNO.Core.Package',
        method: 'list',
        version: 1,
        params: {
          'additional': ['description', 'status', 'startable', 'installed_info', 'dsm_apps', 'url'],
          'polling_interval': 15,
        },
      );
    } on DsmException {
      data = await client.callMap(
        api: 'SYNO.Core.Package',
        method: 'list',
        version: 2,
        params: {
          'additional': ['description', 'status', 'startable', 'installed_info', 'dsm_apps', 'url'],
          'polling_interval': 15,
        },
      );
    }
    final list = (data['packages'] as List?) ?? const [];
    var packages = list.whereType<Map>().map((e) => DsmPackage.fromJson(e.cast<String, dynamic>())).toList();
    // v1 在部分 DSM 7 上会把 status 省略或统一返回 stop，再用 v2 校正一次。
    if (packages.isNotEmpty && !packages.any((p) => p.isRunning)) {
      try {
        final data2 = await client.callMap(
          api: 'SYNO.Core.Package',
          method: 'list',
          version: 2,
          params: {
            'additional': ['description', 'status', 'startable', 'installed_info', 'dsm_apps', 'url'],
            'polling_interval': 15,
          },
        );
        final list2 = (data2['packages'] as List?) ?? const [];
        final byId = <String, DsmPackage>{};
        for (final raw in list2.whereType<Map>()) {
          final pkg = DsmPackage.fromJson(raw.cast<String, dynamic>());
          if (pkg.id.isNotEmpty) byId[pkg.id.toLowerCase()] = pkg;
        }
        if (byId.isNotEmpty) {
          packages = packages.map((p) {
            final other = byId[p.id.toLowerCase()];
            return other != null && other.statusKnown ? p.copyWith(status: other.status) : p;
          }).toList();
        }
      } on DsmException {
        // 继续走 Polling.Data 兜底。
      }
    }
    // 仍然全部为停止/未知时，用运行中的进程数据补齐。
    if (packages.isNotEmpty && !packages.any((p) => p.isRunning)) {
      final running = await _runningPackageIds();
      if (running.isNotEmpty) {
        packages = packages.map((p) => p.copyWith(status: running.contains(p.id.toLowerCase()) ? 'running' : 'stopped')).toList();
      }
    }
    return packages;
  }

  Future<Set<String>> _runningPackageIds() async {
    final result = <String>{};
    try {
      final data = await client.callMap(
        api: 'SYNO.Core.Polling.Data',
        method: 'get',
        version: 1,
        params: {'action': 'load', 'load_disabled_port': true},
      );
      void visit(dynamic node) {
        if (node is Map) {
          final status = '${node['status'] ?? node['state'] ?? ''}'.toLowerCase();
          final id = '${node['id'] ?? node['package'] ?? node['pkg'] ?? ''}'.toLowerCase();
          if (id.isNotEmpty && (status == 'running' || status == 'started')) result.add(id);
          node.forEach((_, value) => visit(value));
        } else if (node is List) {
          for (final item in node) {
            visit(item);
          }
        }
      }

      visit(data);
    } catch (_) {}
    return result;
  }

  Future<List<CatalogPackage>> catalogPackages() async {
    if (demo) return DemoStore.instance.catalogPackages();
    Map<String, dynamic> data;
    try {
      data = await client.callMap(
        api: 'SYNO.Core.Package.Server',
        method: 'list',
        version: 2,
        params: {'updateSprite': true, 'blforcereload': false, 'blloadothers': true},
      );
    } on DsmException {
      data = await client.callMap(
        api: 'SYNO.Core.Package.Server',
        method: 'list',
        version: 1,
        params: {'updateSprite': true, 'blforcereload': false, 'blloadothers': true},
      );
    }
    final raw = data['packages'] ?? data['data'];
    final list = raw is List ? raw : const [];
    return list.whereType<Map>().map((e) => CatalogPackage.fromJson(e.cast<String, dynamic>())).where((p) => p.id.isNotEmpty).toList();
  }

  Future<List<PackageVolume>> packageVolumes() async {
    if (demo) return DemoStore.instance.packageVolumes();
    final data = await client.callMap(
      api: 'SYNO.Core.Storage.Volume',
      method: 'list',
      version: 1,
      params: {'limit': -1, 'offset': 0, 'location': 'internal'},
    );
    final list = (data['volumes'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => PackageVolume.fromJson(e.cast<String, dynamic>())).where((v) => v.path.isNotEmpty).toList();
  }

  Future<String> installPackage(String id, String volumePath, {bool beta = false}) async {
    if (demo) {
      DemoStore.instance.installPackage(id, volumePath);
      return 'demo-task';
    }
    final data = await client.callPostMap(
      api: 'SYNO.Core.Package.Installation',
      method: 'install',
      version: 1,
      params: {
        'name': id,
        'volume_path': volumePath,
        'is_syno': true,
        'beta': beta,
        'installrunpackage': true,
        'blqinst': true,
      },
    );
    final taskId = '${data['taskid'] ?? data['task_id'] ?? ''}';
    if (taskId.isEmpty) throw const DsmException(-1, '安装任务创建失败，请确认账号有管理员权限');
    return taskId;
  }

  Future<Map<String, dynamic>> packageInstallStatus(String taskId) async {
    if (demo) return {'finished': true, 'progress': 100};
    return client.callMap(
      api: 'SYNO.Core.Package.Installation',
      method: 'status',
      version: 1,
      params: {'task_id': taskId},
    );
  }

  Future<void> uninstallPackage(String id) async {
    if (demo) {
      DemoStore.instance.uninstallPackage(id);
      return;
    }
    await client.callPostMap(
      api: 'SYNO.Core.Package.Uninstallation',
      method: 'uninstall',
      version: 1,
      params: {'id': id},
    );
  }
  Future<void> packageControl(String id, bool start) async {
    if (demo) return DemoStore.instance.packageControl(id, start);
    await client.callMap(
      api: 'SYNO.Core.Package.Control',
      method: start ? 'start' : 'stop',
      version: 1,
      params: {'id': id},
    );
  }

  /// DSM 套件图标路径（与 Web 端使用同一套图标文件）。
  List<String> packageIconUrls(String id) {
    if (demo) return const [];
    final encoded = Uri.encodeComponent(id);
    return [
      '${client.baseUrl}/webman/3rdparty/$encoded/images/icon_72.png',
      '${client.baseUrl}/webman/3rdparty/$encoded/images/icon_64.png',
      '${client.baseUrl}/webman/3rdparty/$encoded/images/icon_48.png',
      '${client.baseUrl}/webman/3rdparty/$encoded/images/icon_128.png',
      '${client.baseUrl}/webman/3rdparty/$encoded/images/icon.png',
      '${client.baseUrl}/webman/3rdparty/$encoded/icon_72.png',
      '${client.baseUrl}/webman/3rdparty/$encoded/ui/images/icon_72.png',
    ];
  }

  Map<String, String> get imageHeaders => demo ? const {} : client.imageHeaders;

  // ---------- 账号 / 日志 / 计划任务 ----------

  Future<List<DsmUser>> users() async {
    if (demo) return DemoStore.instance.users();
    final data = await client.callMap(
      api: 'SYNO.Core.User',
      method: 'list',
      version: 1,
      params: {'offset': 0, 'limit': 200, 'additional': ['description', 'email', 'expired', 'groups']},
    );
    final list = (data['users'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => DsmUser.fromJson(e.cast<String, dynamic>())).toList();
  }

  /// 当前用户资料（含头像候选字段与邮箱）。
  Future<Map<String, dynamic>> userProfile(String name) async {
    if (demo) {
      return {'name': name, 'description': '系统管理员', 'email': 'demo@example.com'};
    }
    final data = await client.callMap(
      api: 'SYNO.Core.User',
      method: 'get',
      version: 1,
      params: {
        'name': name,
        'additional': ['description', 'email', 'expired', 'avatar', 'photo', 'profile_photo', 'avatar_url'],
      },
    );
    return data;
  }

  Future<void> updateUser(String name, {required String description, required String email}) async {
    if (demo) {
      DemoStore.instance.updateUser(name, description: description, email: email);
      return;
    }
    await client.callMap(
      api: 'SYNO.Core.User',
      method: 'set',
      version: 1,
      params: {'name': name, 'description': description, 'email': email},
    );
  }

  Future<List<LogEntry>> logs() async {
    if (demo) return DemoStore.instance.logs();
    final data = await client.callMap(
      api: 'SYNO.Core.SyslogClient.Log',
      method: 'list',
      version: 1,
      params: {'start': 0, 'limit': 100, 'dir': 'desc', 'target': 'LOCAL'},
    );
    final list = (data['logs'] as List?) ?? (data['items'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => LogEntry.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<void> clearLogs() async {
    if (demo) return;
    try {
      await client.callMap(
        api: 'SYNO.Core.SyslogClient.Log',
        method: 'clear',
        version: 1,
        params: {'target': 'LOCAL'},
      );
    } on DsmException catch (e) {
      if (e.code == 102 || e.code == 103 || e.code == 104) {
        throw const DsmException(-1, '当前 DSM 不允许在 App 内清除日志，请在 Log Center 中操作');
      }
      rethrow;
    }
  }

  Future<List<ScheduledTask>> tasks() async {
    if (demo) return DemoStore.instance.tasks();
    final data = await client.callMap(
      api: 'SYNO.Core.TaskScheduler',
      method: 'list',
      version: 1,
      params: {'offset': 0, 'limit': 100, 'sort_by': 'next_trigger_time', 'sort_direction': 'ASC'},
    );
    final list = (data['tasks'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => ScheduledTask.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<void> toggleTask(String id, bool enabled) async {
    if (demo) return DemoStore.instance.toggleTask(id, enabled);
    await client.callMap(
      api: 'SYNO.Core.TaskScheduler',
      method: 'set_enable',
      version: 1,
      params: {'id': id, 'enable': enabled},
    );
  }

  // ---------- 系统控制 ----------

  Future<void> power(String action) async {
    if (demo) return;
    await client.callMap(api: 'SYNO.Core.System', method: action, version: 1, params: {'force': true, 'local': true});
  }

  Future<bool> sshEnabled() async {
    if (demo) return true;
    final data = await client.callMap(api: 'SYNO.Core.Terminal', method: 'get', version: 3);
    return data['enable_ssh'] == true;
  }

  Future<void> setSsh(bool enabled) async {
    if (demo) return;
    String sshPort = '22';
    try {
      final info = await client.callMap(api: 'SYNO.Core.Terminal', method: 'get', version: 3);
      sshPort = '${info['ssh_port'] ?? 22}';
    } catch (_) {}
    await client.callMap(
      api: 'SYNO.Core.Terminal',
      method: 'set',
      version: 3,
      params: {'enable_ssh': enabled, 'enable_telnet': false, 'ssh_port': sshPort},
    );
  }

  // ---------- 文件分享 / 相册 / 头像 ----------

  Future<SharedLink> createSharingLink(String path, {String? password, DateTime? expireDate, int? expireTimes}) async {
    if (demo) {
      final expires = expireDate == null ? '永久' : '${expireDate.year}-${expireDate.month.toString().padLeft(2, '0')}-${expireDate.day.toString().padLeft(2, '0')}';
      return SharedLink(id: 'demo', url: 'https://demo.example.com/sharing/demo', expireDate: expires);
    }
    final params = <String, dynamic>{'path': [path]};
    if (password != null && password.isNotEmpty) params['password'] = password;
    if (expireDate != null) {
      params['date_expired'] = '"${expireDate.year}-${expireDate.month.toString().padLeft(2, '0')}-${expireDate.day.toString().padLeft(2, '0')}"';
    }
    if (expireTimes != null && expireTimes > 0) params['expire_times'] = expireTimes;
    final data = await client.callMap(
      api: 'SYNO.FileStation.Sharing',
      method: 'create',
      version: 3,
      params: params,
    );
    final links = (data['links'] as List?) ?? const [];
    if (links.isEmpty || links.first is! Map) {
      throw const DsmException(-1, '创建共享链接失败，请确认账号有分享权限');
    }
    return SharedLink.fromJson((links.first as Map).cast<String, dynamic>());
  }

  Future<List<SharedLink>> sharingLinks() async {
    if (demo) return const [SharedLink(id: 'demo', url: 'https://demo.example.com/sharing/demo', expireDate: '永久')];
    final data = await client.callMap(
      api: 'SYNO.FileStation.Sharing',
      method: 'list',
      version: 3,
      params: {
        'offset': 0,
        'limit': 100,
        'filter_type': 'SYNO.SDS.App.FileStation3.Instance,SYNO.SDS.App.SharingUpload.Application',
      },
    );
    final links = (data['links'] as List?) ?? const [];
    return links.whereType<Map>().map((e) => SharedLink.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<void> deleteSharingLinks(List<String> ids) async {
    if (demo) return;
    await client.callMap(
      api: 'SYNO.FileStation.Sharing',
      method: 'delete',
      version: 3,
      params: {'id': ids},
    );
  }

  /// Synology Photos 时间线。
  Future<List<PhotoItem>> synologyPhotoItems({int offset = 0, int limit = 100}) async {
    if (demo) return const [];
    final data = await client.callMap(
      api: 'SYNO.Foto.Browse.Item',
      method: 'list',
      version: 1,
      params: {
        'offset': offset,
        'limit': limit,
        'sort_by': 'takentime',
        'sort_direction': 'desc',
        'additional': ['thumbnail', 'resolution'],
      },
    );
    final list = (data['list'] ?? data['items']) as List? ?? const [];
    return list.whereType<Map>().map((raw) {
      final item = raw.cast<String, dynamic>();
      final additional = (item['additional'] as Map?)?.cast<String, dynamic>() ?? const {};
      final thumbnail = (additional['thumbnail'] as Map?)?.cast<String, dynamic>() ?? const {};
      final cacheKey = thumbnail['cache_key']?.toString();
      final time = item['time'] as num?;
      final id = '${item['id']}';
      return PhotoItem(
        id: id,
        name: '${item['filename'] ?? ''}',
        takenAt: time == null ? null : DateTime.fromMillisecondsSinceEpoch(time.toInt() * 1000),
        thumbUrl: _fotoThumbUrl(id, cacheKey, 'm'),
        originalUrl: _fotoThumbUrl(id, cacheKey, 'xl'),
      );
    }).toList();
  }

  String _fotoThumbUrl(String id, String? cacheKey, String size) {
    return client
        .rawUri('entry.cgi', {
          'api': 'SYNO.Foto.Thumbnail',
          'method': 'get',
          'version': '2',
          'id': id,
          'size': size,
          'type': 'unit',
          if (cacheKey != null && cacheKey.isNotEmpty) 'cache_key': '"$cacheKey"',
          if (client.sessionId.isNotEmpty) '_sid': client.sessionId,
        })
        .toString();
  }

  /// 选取一个 DSM 文件夹作为相册（只取图片文件）。
  final Map<String, String> _folderPhotoTasks = {};

  /// 递归读取目录及子目录中的图片，分页返回；搜索任务在服务端缓存。
  Future<List<PhotoItem>> folderPhotoPage(String path, {int offset = 0, int limit = 80}) async {
    if (demo) {
      final entries = await files(path);
      return entries.where((e) => !e.isDir && e.kind == FileKind.image).map(_photoFromEntry).toList();
    }
    var taskId = _folderPhotoTasks[path];
    if (taskId == null) {
      final start = await client.callMap(
        api: 'SYNO.FileStation.Search',
        method: 'start',
        version: 1,
        params: {
          'folder_path': path,
          'recursive': true,
          'extension': 'jpg,jpeg,png,gif,webp,bmp,heic,heif',
        },
      );
      taskId = '${start['taskid'] ?? ''}';
      if (taskId.isEmpty) throw const DsmException(-1, '无法开始读取该目录，请确认目录可访问');
      _folderPhotoTasks[path] = taskId;
    }
    Map<String, dynamic> data = const {};
    for (var attempt = 0; attempt < 5; attempt++) {
      data = await client.callMap(
        api: 'SYNO.FileStation.Search',
        method: 'list',
        version: 1,
        params: {
          'taskid': taskId,
          'offset': offset,
          'limit': limit,
          'additional': ['size', 'time', 'type'],
        },
      );
      final page = (data['files'] as List?) ?? const [];
      if (page.isNotEmpty || data['finished'] == true) break;
      await Future.delayed(const Duration(milliseconds: 350));
    }
    final photoMaps = (data['files'] as List?) ?? const [];
    final items = photoMaps.whereType<Map>().map((raw) {
      final map = raw.cast<String, dynamic>();
      if (map['isdir'] == true) return null;
      final additional = (map['additional'] as Map?)?.cast<String, dynamic>() ?? const {};
      final time = (additional['time'] as Map?)?.cast<String, dynamic>() ?? const {};
      final mtime = (time['mtime'] as num?)?.toInt();
      final size = (additional['size'] as num?)?.toInt() ?? 0;
      final filePath = '${map['path'] ?? ''}';
      return PhotoItem(
        id: filePath,
        name: '${map['name'] ?? ''}',
        takenAt: mtime == null ? null : DateTime.fromMillisecondsSinceEpoch(mtime * 1000),
        createdAt: mtime == null ? null : DateTime.fromMillisecondsSinceEpoch(mtime * 1000),
        size: size,
        path: filePath,
        thumbUrl: thumbnailUri(filePath, size: 'small')?.toString() ?? '',
        originalUrl: downloadUri(filePath, open: true).toString(),
      );
    }).whereType<PhotoItem>().toList();
    items.sort((a, b) => (b.takenAt ?? DateTime(0)).compareTo(a.takenAt ?? DateTime(0)));
    return items;
  }

  PhotoItem _photoFromEntry(FileEntry entry) => PhotoItem(
        id: entry.path,
        name: entry.name,
        takenAt: entry.mtime,
        createdAt: entry.mtime,
        size: entry.size,
        path: entry.path,
        thumbUrl: demo ? '' : (thumbnailUri(entry.path, size: 'small')?.toString() ?? ''),
        originalUrl: demo ? '' : downloadUri(entry.path, open: true).toString(),
      );

  void resetFolderPhotoTask(String path) {
    _folderPhotoTasks.remove(path);
  }

  Future<Map<String, dynamic>> fileInfo(String path) async {
    final data = await client.callMap(
      api: 'SYNO.FileStation.List',
      method: 'getinfo',
      version: 2,
      params: {
        'path': [path],
        'additional': ['size', 'time', 'type'],
      },
    );
    final files = (data['files'] as List?) ?? const [];
    return files.isNotEmpty && files.first is Map ? (files.first as Map).cast<String, dynamic>() : const {};
  }
  /// 尝试从 DSM 获取当前登录用户的头像地址。
  Future<String?> avatarUrl(String account) async {
    if (demo) return null;
    try {
      final profile = await userProfile(account);
      for (final key in ['avatar', 'photo', 'profile_photo', 'avatar_url']) {
        final value = profile[key];
        final url = _absoluteUrl(value);
        if (url != null) return url;
      }
      final additional = profile['additional'];
      if (additional is Map) {
        for (final key in ['avatar', 'photo', 'profile_photo']) {
          final url = _absoluteUrl(additional[key]);
          if (url != null) return url;
        }
      }
    } catch (_) {}
    try {
      final data = await client.callMap(api: 'SYNO.Core.PersonalSettings', method: 'get', version: 1);
      for (final key in ['avatar', 'photo', 'profile_photo', 'avatar_url']) {
        final url = _absoluteUrl(data[key]);
        if (url != null) return url;
      }
    } catch (_) {}
    return null;
  }

  String? _absoluteUrl(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('/')) return '${client.baseUrl}$value';
    return null;
  }

  // ---------- Docker ----------

  Future<List<DockerContainer>> dockerContainers() async {
    if (demo) return DemoStore.instance.dockerContainers();
    final data = await client.callMap(
      api: 'SYNO.Docker.Container',
      method: 'list',
      version: 1,
      params: {'limit': -1, 'offset': 0, 'type': 'all'},
    );
    final containers = <String, DockerContainer>{};

    void addContainer(dynamic raw, [String? fallbackName]) {
      if (raw is! Map) return;
      final map = raw.cast<String, dynamic>();
      final name = (map['name'] ?? fallbackName ?? '').toString();
      if (name.isEmpty) return;
      containers[name] = DockerContainer(
        name: name,
        status: (map['status'] ?? map['state'] ?? '').toString(),
        image: (map['image'] ?? map['Image'] ?? '').toString(),
        id: (map['id'] ?? '').toString(),
        ports: _dockerPorts(map),
      );
    }

    final raw = data['containers'] ?? data['data'];
    if (raw is List) {
      for (final item in raw) {
        addContainer(item);
      }
    } else if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          if (value['containers'] is List) {
            for (final item in value['containers'] as List) {
              addContainer(item, '${key}');
            }
          } else {
            addContainer(value, '$key');
          }
        }
      });
    }

    try {
      final resourceData = await client.callMap(api: 'SYNO.Docker.Container.Resource', method: 'get', version: 1);
      final resources = (resourceData['resources'] as List?) ?? const [];
      for (final item in resources) {
        if (item is! Map) continue;
        final name = item['name']?.toString();
        if (name == null || name.isEmpty) continue;
        final existing = containers[name];
        if (existing == null) {
          containers[name] = DockerContainer(name: name, cpu: _asNum(item['cpu']), memory: _asNum(item['memory']).toInt());
        } else {
          containers[name] = existing.copyWith(cpu: _asNum(item['cpu']), memory: _asNum(item['memory']).toInt());
        }
      }
    } catch (_) {}
    final list = containers.values.toList()
      ..sort((a, b) {
        if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  double _asNum(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _dockerPorts(Map<String, dynamic> map) {
    final raw = map['ports'] ?? map['port_bindings'];
    if (raw is List) {
      final parts = <String>[];
      for (final item in raw) {
        if (item is Map) {
          final host = item['host_port'] ?? item['hostPort'] ?? item['host'];
          final container = item['container_port'] ?? item['containerPort'] ?? item['container'] ?? item['port'];
          if (host != null && container != null) parts.add('$host:$container');
        } else {
          parts.add('$item');
        }
      }
      return parts.take(3).join(', ');
    }
    return raw?.toString() ?? '';
  }

  Future<List<DockerImage>> dockerImages() async {
    if (demo) return DemoStore.instance.dockerImages();
    final data = await client.callMap(
      api: 'SYNO.Docker.Image',
      method: 'list',
      version: 1,
      params: {'limit': -1, 'offset': 0, 'show_dsm': false},
    );
    final list = (data['images'] as List?) ?? const [];
    return list.whereType<Map>().map((raw) {
      final map = raw.cast<String, dynamic>();
      final tags = (map['tags'] as List?) ?? const [];
      return DockerImage(
        repository: '${map['repository'] ?? ''}',
        tag: tags.isEmpty ? '' : '${tags.first}',
        size: (map['size'] as num?)?.toInt() ?? 0,
        id: '${map['id'] ?? ''}',
      );
    }).toList()
      ..sort((a, b) => a.repository.toLowerCase().compareTo(b.repository.toLowerCase()));
  }

  Future<void> dockerAction(String name, String action) async {
    if (demo) {
      DemoStore.instance.dockerAction(name, action);
      return;
    }
    await client.callMap(
      api: 'SYNO.Docker.Container',
      method: action,
      version: 1,
      params: {'name': '"$name"', if (action == 'delete') 'preserve_profile': false},
    );
  }

  Future<void> dockerPull(String repository, String tag) async {
    if (demo) {
      DemoStore.instance.dockerPull(repository, tag);
      return;
    }
    await client.callMap(
      api: 'SYNO.Docker.Image',
      method: 'pull',
      version: 1,
      params: {'repository': repository, 'tag': tag.isEmpty ? 'latest' : tag},
    );
  }

  Future<void> dockerCreate(Map<String, dynamic> profile) async {
    if (demo) {
      DemoStore.instance.dockerCreate(profile);
      return;
    }
    await client.callMap(
      api: 'SYNO.Docker.Container',
      method: 'create',
      version: 1,
      params: {'profile': profile},
    );
  }

  Future<String> dockerLogs(String name) async {
    if (demo) return DemoStore.instance.dockerLogs(name);
    final data = await client.callMap(
      api: 'SYNO.Docker.Container.Log',
      method: 'get',
      version: 1,
      params: {
        'name': '"$name"',
        'sort_dir': '"ASC"',
        'date': '"${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}"',
        'limit': 200,
        'offset': 0,
      },
    );
    final logs = data['logs'] ?? data['data'];
    if (logs is List) {
      return logs.map((item) {
        if (item is Map) return '${item['msg'] ?? item['log'] ?? item['message'] ?? item}';
        return '$item';
      }).join('\n');
    }
    return logs?.toString() ?? '';
  }

  Future<Map<String, dynamic>> networkInfo() async {
    if (demo) {
      return {
        'interfaces': [
          {'name': 'eth0', 'ip': '192.168.110.10', 'mask': '255.255.255.0', 'gateway': '192.168.110.1', 'mac': '00:11:32:AB:CD:EF', 'speed': '1000 Mbps, Full duplex, MTU 1500'},
          {'name': 'eth1', 'ip': '未连接', 'mask': '', 'gateway': '', 'mac': '00:11:32:AB:CD:F0', 'speed': ''},
        ],
        'dns': '223.5.5.5',
        'hostname': 'HomeCloud',
      };
    }
    return client.callMap(api: 'SYNO.Core.System', method: 'info', version: 1, params: {'type': 'network'});
  }
}
