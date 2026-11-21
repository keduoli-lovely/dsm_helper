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
    final data = await client.callMap(
      api: 'SYNO.Core.System.Utilization',
      method: 'get',
      version: 1,
      params: {
        'type': 'current',
        'resource': ['cpu', 'memory', 'network', 'disk'],
      },
    );
    return Utilization.fromJson(data);
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
    final data = await client.callMap(
      api: 'SYNO.Core.Package',
      method: 'list',
      version: 2,
      params: {
        'additional': ['description', 'status', 'startable', 'installed_info', 'dsm_apps', 'url'],
        'polling_interval': 15,
      },
    );
    final list = (data['packages'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => DsmPackage.fromJson(e.cast<String, dynamic>())).toList();
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

  // ---------- 账号 / 日志 / 计划任务 ----------

  Future<List<DsmUser>> users() async {
    if (demo) return DemoStore.instance.users();
    final data = await client.callMap(
      api: 'SYNO.Core.User',
      method: 'list',
      version: 1,
      params: {'offset': 0, 'limit': 200, 'additional': ['description', 'email', 'groups']},
    );
    final list = (data['users'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => DsmUser.fromJson(e.cast<String, dynamic>())).toList();
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
