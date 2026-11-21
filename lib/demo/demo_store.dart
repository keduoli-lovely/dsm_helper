import 'dart:math';

import '../dsm/models.dart';

/// 演示模式：没有连接 NAS 时也能完整体验界面与交互。
class DemoStore {
  DemoStore._() {
    _seed();
  }
  static final DemoStore instance = DemoStore._();

  final Random _random = Random(42);
  late SystemInfo systemInfo;
  late StorageSnapshot storage;
  final Map<String, List<FileEntry>> _tree = {};
  final List<DownloadTask> _downloads = [];
  final List<DsmPackage> _packages = [];
  final List<DsmUser> _users = [];
  final List<LogEntry> _logs = [];
  final List<ScheduledTask> _tasks = [];
  double _cpu = 18;
  double _mem = 41;
  double _net = 1.4;
  double _disk = 42;

  void _seed() {
    systemInfo = const SystemInfo(
      model: 'DS918+',
      serial: '1920PDN123456',
      firmwareVer: 'DSM 7.2.2-72806',
      uptime: 1_842_600,
      temperature: 46,
      cpuCores: 4,
      cpuModel: 'Intel Celeron J3455',
      ramMb: 8192,
      hostname: 'HomeCloud',
    );

    storage = StorageSnapshot(
      volumes: const [
        VolumeInfo(id: 'volume_1', name: '存储空间 1', total: 24_000_000_000_000, used: 13_600_000_000_000, fsType: 'Btrfs', raidType: 'SHR'),
        VolumeInfo(id: 'volume_2', name: '存储空间 2', total: 8_000_000_000_000, used: 2_100_000_000_000, fsType: 'Btrfs', raidType: 'Basic'),
      ],
      disks: const [
        DiskInfo(id: 'sata1', model: 'WD40EFRX-68N32N0', size: 4_000_787_030_016, temperature: 34),
        DiskInfo(id: 'sata2', model: 'WD40EFRX-68N32N0', size: 4_000_787_030_016, temperature: 36),
        DiskInfo(id: 'sata3', model: 'ST8000VN004-2M2101', size: 8_001_563_222_016, temperature: 38),
        DiskInfo(id: 'sata4', model: 'ST8000VN004-2M2101', size: 8_001_563_222_016, temperature: 39),
      ],
    );

    _tree[''] = const [];
    _tree['/影视'] = [
      _folder('电影', '/影视/电影'),
      _folder('剧集', '/影视/剧集'),
      _folder('动画', '/影视/动画'),
      _file('流浪地球2.2023.2160p.mkv', '/影视/流浪地球2.2023.2160p.mkv', 13_310_000_000),
      _file('沙丘2.2024.2160p.mkv', '/影视/沙丘2.2024.2160p.mkv', 16_800_000_000),
    ];
    _tree['/影视/电影'] = [
      _file('星际穿越.2014.2160p.mkv', '/影视/电影/星际穿越.2014.2160p.mkv', 18_420_000_000),
      _file('奥本海默.2023.1080p.mp4', '/影视/电影/奥本海默.2023.1080p.mp4', 5_120_000_000),
      _file('让子弹飞.2010.1080p.mkv', '/影视/电影/让子弹飞.2010.1080p.mkv', 3_400_000_000),
    ];
    _tree['/影视/剧集'] = [
      _folder('三体', '/影视/剧集/三体'),
      _file('漫长的季节.S01E01.mkv', '/影视/剧集/漫长的季节.S01E01.mkv', 2_100_000_000),
    ];
    _tree['/影视/动画'] = [
      _file('千与千寻.2001.1080p.mkv', '/影视/动画/千与千寻.2001.1080p.mkv', 4_300_000_000),
    ];
    _tree['/照片'] = [
      _folder('2025', '/照片/2025'),
      _folder('2024', '/照片/2024'),
      _folder('宝宝', '/照片/宝宝'),
      _file('封面.jpg', '/照片/封面.jpg', 2_400_000),
    ];
    _tree['/照片/2025'] = [
      _file('IMG_2031.HEIC', '/照片/2025/IMG_2031.HEIC', 4_900_000),
      _file('IMG_2032.HEIC', '/照片/2025/IMG_2032.HEIC', 5_200_000),
      _file('IMG_2033.HEIC', '/照片/2025/IMG_2033.HEIC', 4_700_000),
      _file('海边日落.jpg', '/照片/2025/海边日落.jpg', 6_300_000),
      _file('全家福.jpg', '/照片/2025/全家福.jpg', 7_100_000),
      _file('vlog-01.mp4', '/照片/2025/vlog-01.mp4', 320_000_000),
    ];
    _tree['/照片/2024'] = [
      _file('IMG_1102.HEIC', '/照片/2024/IMG_1102.HEIC', 4_200_000),
      _file('IMG_1103.HEIC', '/照片/2024/IMG_1103.HEIC', 4_400_000),
    ];
    _tree['/照片/宝宝'] = [
      _file('第一次走路.mp4', '/照片/宝宝/第一次走路.mp4', 180_000_000),
      _file('生日.jpg', '/照片/宝宝/生日.jpg', 5_800_000),
    ];
    _tree['/文档'] = [
      _file('家庭账本.xlsx', '/文档/家庭账本.xlsx', 1_800_000),
      _file('租房合同.pdf', '/文档/租房合同.pdf', 3_200_000),
      _file('读书笔记.md', '/文档/读书笔记.md', 42_000),
      _file('旅行计划.docx', '/文档/旅行计划.docx', 820_000),
    ];
    _tree['/音乐'] = [
      _file('夜曲.flac', '/音乐/夜曲.flac', 38_000_000),
      _file('七里香.flac', '/音乐/七里香.flac', 41_000_000),
      _file('平凡之路.mp3', '/音乐/平凡之路.mp3', 9_800_000),
    ];
    _tree['/备份'] = [
      _file('手机备份-2025-11.zip', '/备份/手机备份-2025-11.zip', 18_400_000_000),
      _file('群晖配置备份.dss', '/备份/群晖配置备份.dss', 24_000_000),
    ];
    // 兼容 DSM 默认的英文共享名
    _tree['/photo'] = _tree['/照片']!;
    _tree['/video'] = _tree['/影视']!;

    _downloads.addAll([
      const DownloadTask(
        id: 'dbid_101',
        title: '沙丘2.2024.2160p.UHD.BluRay.x265.mkv',
        status: 'downloading',
        size: 24_800_000_000,
        downloaded: 10_900_000_000,
        speedDownload: 8_600_000,
        destination: '/影视/电影',
      ),
      const DownloadTask(
        id: 'dbid_102',
        title: '三体.S01E05.2160p.WEB-DL.mkv',
        status: 'finished',
        size: 3_200_000_000,
        downloaded: 3_200_000_000,
        destination: '/影视/剧集',
      ),
      const DownloadTask(
        id: 'dbid_103',
        title: 'ubuntu-24.04.1-desktop-amd64.iso',
        status: 'paused',
        size: 5_900_000_000,
        downloaded: 2_100_000_000,
        destination: '/备份',
      ),
      const DownloadTask(
        id: 'dbid_104',
        title: 'LG.4K.HDR.演示片.mp4',
        status: 'waiting',
        size: 1_100_000_000,
        downloaded: 0,
        destination: '/影视',
      ),
    ]);

    _packages.addAll([
      const DsmPackage(id: 'SynologyPhotos', name: 'Synology Photos', version: '1.7.1-0819', status: 'running'),
      const DsmPackage(id: 'DownloadStation', name: 'Download Station', version: '4.0.6-3829', status: 'running'),
      const DsmPackage(id: 'Docker', name: 'Container Manager', version: '24.0.2-1535', status: 'running'),
      const DsmPackage(id: 'SynologyDrive', name: 'Synology Drive Server', version: '3.5.1-26102', status: 'running'),
      const DsmPackage(id: 'PlexMediaServer', name: 'Plex Media Server', version: '1.41.3', status: 'running'),
      const DsmPackage(id: 'Virtualization', name: 'Virtual Machine Manager', version: '2.6.5-12202', status: 'stopped'),
      const DsmPackage(id: 'MariaDB10', name: 'MariaDB 10', version: '10.1.48-0120', status: 'stopped'),
      const DsmPackage(id: 'WebStation', name: 'Web Station', version: '3.1.4-0330', status: 'running'),
      const DsmPackage(id: 'LogCenter', name: 'Log Center', version: '1.4.3-0150', status: 'running'),
      const DsmPackage(id: 'NoteStation', name: 'Note Station', version: '2.6.4-0831', status: 'stopped'),
      const DsmPackage(id: 'ActiveBackup', name: 'Active Backup for Business', version: '2.6.1-13108', status: 'stopped'),
    ]);

    _users.addAll([
      const DsmUser(name: 'admin', description: '系统管理员', group: 'administrators'),
      const DsmUser(name: 'keduoli', description: '家庭管理员', group: 'users'),
      const DsmUser(name: 'media', description: '影音专用账号', group: 'users'),
      const DsmUser(name: 'guest', description: '访客账号', group: 'guest', disabled: true),
    ]);

    _logs.addAll([
      const LogEntry(who: 'keduoli', what: '通过 DSM 助手登录系统', time: '2025-11-21 12:30:18', from: '192.168.110.24'),
      const LogEntry(who: 'system', what: '存储空间 1 的 SMART 检测已完成，状态正常', time: '2025-11-21 03:00:02', from: ''),
      const LogEntry(who: 'DownloadStation', what: '下载任务「三体.S01E05」已完成', time: '2025-11-20 22:41:07', from: ''),
      const LogEntry(who: 'admin', what: '通过 Web 端登录 DSM', time: '2025-11-20 20:12:55', from: '192.168.110.88'),
      const LogEntry(who: 'system', what: '套件「MariaDB 10」已停止', time: '2025-11-19 18:03:44', from: ''),
    ]);

    _tasks.addAll([
      const ScheduledTask(id: '1', name: '每日配置备份', nextRun: '2025-11-22 02:00', lastStatus: '0', enabled: true),
      const ScheduledTask(id: '2', name: 'SMART 快速检测', nextRun: '2025-11-23 03:00', lastStatus: '0', enabled: true),
      const ScheduledTask(id: '3', name: '夜间自动关机', nextRun: '2025-11-21 23:30', lastStatus: '0', enabled: false),
    ]);
  }

  FileEntry _folder(String name, String path) =>
      FileEntry(name: name, path: path, isDir: true, mtime: DateTime.now().subtract(const Duration(days: 3)));

  FileEntry _file(String name, String path, int size) => FileEntry(
        name: name,
        path: path,
        isDir: false,
        size: size,
        mtime: DateTime.now().subtract(Duration(minutes: _random.nextInt(60 * 24 * 30))),
        isWritable: true,
      );

  Utilization nextUtilization() {
    double walk(double value, double min, double max, double step) {
      final next = value + (_random.nextDouble() - 0.5) * step;
      return next.clamp(min, max).toDouble();
    }

    _cpu = walk(_cpu, 8, 78, 9);
    _mem = walk(_mem, 32, 72, 2.2);
    _net = walk(_net, 0.2, 9, 1.8);
    _disk = walk(_disk, 5, 120, 14);
    const total = 8 * 1024 * 1024 * 1024;
    return Utilization(
      cpuPercent: _cpu,
      memPercent: _mem,
      memUsedBytes: (total * _mem / 100).round(),
      memTotalBytes: total,
      netRx: _net * 1024 * 1024,
      netTx: _net * 0.18 * 1024 * 1024,
      diskRead: _disk * 1024 * 1024,
      diskWrite: _disk * 0.42 * 1024 * 1024,
      diskUtil: (_disk / 1.6).clamp(0, 100).toDouble(),
      disks: const [],
      sampledAt: DateTime.now(),
    );
  }

  List<FileEntry> list(String path) {
    if (path.isEmpty) {
      return shares().map((s) => FileEntry(name: s.name, path: s.path, isDir: true, size: s.size)).toList();
    }
    final entries = _tree[path] ?? const <FileEntry>[];
    final sorted = [...entries]..sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return sorted;
  }

  int _shareSize(String name) {
    final prefix = '/$name';
    var total = 0;
    _tree.forEach((path, files) {
      if (path == prefix || path.startsWith('$prefix/')) {
        for (final f in files) {
          if (!f.isDir) total += f.size;
        }
      }
    });
    return total == 0 ? 1_000_000_000 : total;
  }

  List<ShareInfo> shares() {
    return ['影视', '照片', '文档', '音乐', '备份']
        .map((name) => ShareInfo(name: name, path: '/$name', size: _shareSize(name), owner: 'keduoli'))
        .toList();
  }

  void createFolder(String parent, String name) {
    final path = parent.isEmpty ? '/$name' : '$parent/$name';
    _tree[parent] ??= [];
    _tree[parent]!.insert(0, FileEntry(name: name, path: path, isDir: true, mtime: DateTime.now()));
    _tree[path] ??= [];
  }

  void rename(String path, String newName) {
    final parent = path.substring(0, path.lastIndexOf('/'));
    final list = _tree[parent] ?? [];
    final index = list.indexWhere((e) => e.path == path);
    if (index >= 0) {
      final old = list[index];
      list[index] = FileEntry(name: newName, path: '$parent/$newName', isDir: old.isDir, size: old.size, mtime: DateTime.now(), isWritable: true);
    }
  }

  void delete(String path) {
    final parent = path.substring(0, path.lastIndexOf('/'));
    _tree[parent]?.removeWhere((e) => e.path == path);
    _tree.removeWhere((key, _) => key == path || key.startsWith('$path/'));
  }

  List<DownloadTask> downloads() {
    // 让「下载中」的任务看起来是活的
    for (var i = 0; i < _downloads.length; i++) {
      final t = _downloads[i];
      if (t.status == 'downloading' && t.downloaded < t.size) {
        final next = (t.downloaded + t.speedDownload * 2).clamp(0, t.size).toInt();
        _downloads[i] = DownloadTask(
          id: t.id,
          title: t.title,
          status: next >= t.size ? 'finished' : t.status,
          size: t.size,
          downloaded: next,
          speedDownload: t.speedDownload,
          destination: t.destination,
        );
      }
    }
    return [..._downloads];
  }

  void addDownload(String uri) {
    _downloads.insert(
      0,
      DownloadTask(
        id: 'dbid_${DateTime.now().millisecondsSinceEpoch}',
        title: uri.split('/').last,
        status: 'waiting',
        size: 1_500_000_000,
        downloaded: 0,
        destination: '/影视',
      ),
    );
  }

  void downloadAction(String action, String id) {
    final index = _downloads.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final t = _downloads[index];
    switch (action) {
      case 'pause':
        _downloads[index] = DownloadTask(id: t.id, title: t.title, status: 'paused', size: t.size, downloaded: t.downloaded, destination: t.destination);
        break;
      case 'resume':
        _downloads[index] = DownloadTask(
          id: t.id,
          title: t.title,
          status: 'downloading',
          size: t.size,
          downloaded: t.downloaded,
          speedDownload: t.speedDownload == 0 ? 6_400_000 : t.speedDownload,
          destination: t.destination,
        );
        break;
      case 'delete':
        _downloads.removeAt(index);
        break;
    }
  }

  List<DsmPackage> packages() => [..._packages];

  void packageControl(String id, bool start) {
    final index = _packages.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final p = _packages[index];
    _packages[index] = DsmPackage(id: p.id, name: p.name, version: p.version, status: start ? 'running' : 'stopped');
  }

  List<DsmUser> users() => [..._users];
  List<LogEntry> logs() => [..._logs];
  List<ScheduledTask> tasks() => [..._tasks];

  void toggleTask(String id, bool enabled) {
    final index = _tasks.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final t = _tasks[index];
    _tasks[index] = ScheduledTask(id: t.id, name: t.name, nextRun: t.nextRun, lastStatus: t.lastStatus, enabled: enabled);
  }
}
