import 'dart:convert';

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String _asString(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

/// 一台已保存的群晖服务器。
class DsmServer {
  final String host;
  final String port;
  final bool https;
  final bool trustSelfSigned;
  final String account;
  final String? password;
  final bool autoLogin;
  final bool rememberPassword;
  final String? note;
  final String? sid;
  final String? cookie;

  const DsmServer({
    required this.host,
    this.port = '5000',
    this.https = false,
    this.trustSelfSigned = true,
    required this.account,
    this.password,
    this.autoLogin = false,
    this.rememberPassword = true,
    this.note,
    this.sid,
    this.cookie,
  });

  String get baseUrl => '${https ? 'https' : 'http'}://$host:$port';

  String get displayName => (note != null && note!.isNotEmpty) ? note! : host;

  DsmServer copyWith({String? password, bool? autoLogin, String? sid, String? cookie, String? note}) => DsmServer(
        host: host,
        port: port,
        https: https,
        trustSelfSigned: trustSelfSigned,
        account: account,
        password: password ?? this.password,
        autoLogin: autoLogin ?? this.autoLogin,
        rememberPassword: rememberPassword,
        note: note ?? this.note,
        sid: sid ?? this.sid,
        cookie: cookie ?? this.cookie,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'https': https,
        'trust_self_signed': trustSelfSigned,
        'account': account,
        'password': password,
        'auto_login': autoLogin,
        'remember_password': rememberPassword,
        'note': note,
        'sid': sid,
        'cookie': cookie,
      };

  factory DsmServer.fromJson(Map<String, dynamic> json) => DsmServer(
        host: _asString(json['host']),
        port: _asString(json['port'], '5000'),
        https: json['https'] == true,
        trustSelfSigned: json['trust_self_signed'] != false,
        account: _asString(json['account']),
        password: json['password'] as String?,
        autoLogin: json['auto_login'] == true,
        rememberPassword: json['remember_password'] != false,
        note: json['note'] as String?,
        sid: json['sid'] as String?,
        cookie: json['cookie'] as String?,
      );
}

class SystemInfo {
  final String model;
  final String serial;
  final String firmwareVer;
  final int uptime;
  final double temperature;
  final int cpuCores;
  final String cpuModel;
  final int ramMb;
  final String hostname;

  const SystemInfo({
    this.model = '',
    this.serial = '',
    this.firmwareVer = '',
    this.uptime = 0,
    this.temperature = 0,
    this.cpuCores = 0,
    this.cpuModel = '',
    this.ramMb = 0,
    this.hostname = '',
  });

  int get dsmMajor {
    final match = RegExp(r'DSM\s*(\d+)').firstMatch(firmwareVer);
    return int.tryParse(match?.group(1) ?? '') ?? 7;
  }

  String get dsmLabel {
    final clean = firmwareVer.replaceFirst('DSM ', '');
    return clean.isEmpty ? firmwareVer : clean;
  }

  factory SystemInfo.fromJson(Map<String, dynamic> d) => SystemInfo(
        model: _asString(d['model']),
        serial: _asString(d['serial']),
        firmwareVer: _asString(d['firmware_ver']),
        uptime: _asInt(d['up_time'] ?? d['uptime']),
        temperature: _asDouble(d['temperature']),
        cpuCores: _asInt(d['cpu_cores']),
        cpuModel: _asString(d['cpu_vendor']).isEmpty ? _asString(d['cpu_series']) : _asString(d['cpu_vendor']),
        ramMb: _asInt(d['ram_size']),
        hostname: _asString(d['hostname']),
      );
}

class Utilization {
  final double cpuPercent;
  final double memPercent;
  final int memUsedBytes;
  final int memTotalBytes;
  final double netRx;
  final double netTx;
  final double diskRead;
  final double diskWrite;
  final double diskUtil;
  final List<DiskThroughput> disks;
  final DateTime sampledAt;

  const Utilization({
    this.cpuPercent = 0,
    this.memPercent = 0,
    this.memUsedBytes = 0,
    this.memTotalBytes = 0,
    this.netRx = 0,
    this.netTx = 0,
    this.diskRead = 0,
    this.diskWrite = 0,
    this.diskUtil = 0,
    this.disks = const [],
    required this.sampledAt,
  });

  factory Utilization.fromJson(Map<String, dynamic> d) {
    Map<String, dynamic> mapOf(dynamic value) {
      if (value is Map) return value.map((key, item) => MapEntry('$key', item));
      return const {};
    }

    /// DSM 6 返回数组，DSM 7 部分接口返回以设备名为 key 的对象，两种都兼容。
    List<dynamic> listOf(dynamic value) {
      if (value is List) return value;
      if (value is Map) {
        // 单个吞吐对象（disk.total 等），直接作为一个元素。
        if (value.containsKey('read_byte') || value.containsKey('read') || value.containsKey('write') || value.containsKey('rx') || value.containsKey('tx')) {
          return [value];
        }
        final total = value['total'];
        if (total is List) return total;
        if (total is Map) return [total];
        final items = <dynamic>[];
        value.forEach((key, item) {
          if (item is Map) {
            items.add({...item, 'device': item['device'] ?? '$key'});
          } else if (item is List) {
            items.addAll(item.whereType<Map>());
          }
        });
        return items;
      }
      return const [];
    }

    final cpu = mapOf(d['cpu']);
    final mem = mapOf(d['memory']);

    var cpuPercent = _asDouble(cpu['total']);
    if (cpuPercent <= 0) cpuPercent = _asDouble(cpu['user']) + _asDouble(cpu['system']) + _asDouble(cpu['other']);
    if (cpuPercent <= 0) cpuPercent = _asDouble(cpu['user_load']) + _asDouble(cpu['system_load']) + _asDouble(cpu['other_load']);
    if (cpuPercent <= 0) cpuPercent = _asDouble(cpu['usage']);

    // DSM 7 的 memory_size 单位是 KB，部分老版本返回 MB。
    final memSize = _asDouble(mem['memory_size']);
    final availKb = _asDouble(mem['avail_real']);
    final totalRealKb = _asDouble(mem['total_real']);
    var memTotal = 0;
    var memUsed = 0;
    var memPercent = 0.0;
    if (memSize > 0) {
      final sizeKb = memSize >= 1000000 ? memSize : memSize * 1024;
      memTotal = (sizeKb * 1024).round();
      final usedKb = sizeKb - availKb;
      memUsed = (usedKb * 1024).round().clamp(0, memTotal);
      memPercent = (usedKb / sizeKb * 100).clamp(0, 100).toDouble();
    } else if (totalRealKb > 0) {
      memTotal = (totalRealKb * 1024).round();
      memUsed = ((totalRealKb - availKb) * 1024).round().clamp(0, memTotal);
      memPercent = (memUsed / memTotal * 100).clamp(0, 100).toDouble();
    }
    // DSM 的 real_usage 已扣除缓存/缓冲，与 Web 页面显示的百分比一致，优先使用。
    final realUsage = _asDouble(mem['real_usage']);
    if (realUsage > 0) {
      memPercent = realUsage.clamp(0, 100).toDouble();
      if (memTotal > 0) memUsed = (memTotal * memPercent / 100).round();
    }

    final netItems = listOf(d['network']);
    Map<dynamic, dynamic>? netTotal;
    final netOthers = <dynamic>[];
    for (final item in netItems) {
      if (item is! Map) continue;
      if ('${item['device'] ?? ''}' == 'total') {
        netTotal = item;
      } else {
        netOthers.add(item);
      }
    }
    var netRx = 0.0;
    var netTx = 0.0;
    for (final item in (netTotal != null ? [netTotal] : netOthers)) {
      netRx += _asDouble(item['rx']);
      netTx += _asDouble(item['tx']);
    }

    final diskRaw = d['disk'];
    final diskMap = mapOf(diskRaw);
    final diskTotalList = listOf(diskMap['total'] ?? diskRaw);
    double readOf(Map<dynamic, dynamic> item) => item.containsKey('read_byte') ? _asDouble(item['read_byte']) : _asDouble(item['read']);
    double writeOf(Map<dynamic, dynamic> item) => item.containsKey('write_byte') ? _asDouble(item['write_byte']) : _asDouble(item['write']);
    var diskRead = 0.0;
    var diskWrite = 0.0;
    var diskUtil = 0.0;
    if (diskTotalList.isNotEmpty && diskTotalList.first is Map) {
      final total = diskTotalList.first as Map;
      diskRead = readOf(total);
      diskWrite = writeOf(total);
      diskUtil = _asDouble(total['utilization']);
    }
    if (diskRead <= 0 && diskWrite <= 0) {
      for (final item in diskTotalList) {
        if (item is Map) {
          diskRead += readOf(item);
          diskWrite += writeOf(item);
        }
      }
    }

    final disks = <DiskThroughput>[];
    final diskList = diskMap.isNotEmpty ? listOf(diskMap['disk']) : (diskRaw is List ? diskRaw : const []);
    for (final item in diskList) {
      if (item is Map) {
        disks.add(DiskThroughput(
          device: _asString(item['device']),
          read: readOf(item),
          write: writeOf(item),
          utilization: _asDouble(item['utilization']),
        ));
      }
    }

    return Utilization(
      cpuPercent: cpuPercent.clamp(0, 100).toDouble(),
      memPercent: memPercent.clamp(0, 100).toDouble(),
      memUsedBytes: memUsed,
      memTotalBytes: memTotal,
      netRx: netRx,
      netTx: netTx,
      diskRead: diskRead,
      diskWrite: diskWrite,
      diskUtil: diskUtil,
      disks: disks,
      sampledAt: DateTime.now(),
    );
  }
}

class DiskThroughput {
  final String device;
  final double read;
  final double write;
  final double utilization;
  const DiskThroughput({required this.device, required this.read, required this.write, required this.utilization});
}

class VolumeInfo {
  final String id;
  final String name;
  final int total;
  final int used;
  final String status;
  final String fsType;
  final String raidType;

  const VolumeInfo({
    required this.id,
    required this.name,
    required this.total,
    required this.used,
    this.status = 'normal',
    this.fsType = '',
    this.raidType = '',
  });

  double get ratio => total <= 0 ? 0 : (used / total).clamp(0.0, 1.0);

  String get fsLabel {
    if (fsType.isEmpty) return '';
    return switch (fsType.toLowerCase()) {
      'btrfs' => 'Btrfs',
      'ext4' => 'ext4',
      'ext3' => 'ext3',
      'f2fs' => 'F2FS',
      _ => fsType.toUpperCase(),
    };
  }

  String get raidLabel {
    if (raidType.isEmpty) return '';
    final lower = raidType.toLowerCase();
    if (lower == 'shr') return 'SHR';
    if (lower.startsWith('raid')) return raidType.replaceFirst('raid', 'RAID').toUpperCase();
    if (lower == 'basic') return 'Basic';
    return raidType.toUpperCase();
  }

  factory VolumeInfo.fromJson(Map<String, dynamic> d) {
    final size = (d['size'] as Map?)?.cast<String, dynamic>() ?? const {};
    final display = _asString(d['display_name'] ?? d['name'] ?? d['id']);
    return VolumeInfo(
      id: _asString(d['id']),
      name: display.isEmpty ? _asString(d['id']) : display,
      total: _asInt(size['total']),
      used: _asInt(size['used']),
      status: _asString(d['status'], 'normal'),
      fsType: _asString(d['fs_type']),
      raidType: _asString(d['raid_type']),
    );
  }
}

class DiskInfo {
  final String id;
  final String model;
  final int size;
  final String status;
  final double temperature;
  const DiskInfo({required this.id, this.model = '', this.size = 0, this.status = 'normal', this.temperature = 0});

  factory DiskInfo.fromJson(Map<String, dynamic> d) => DiskInfo(
        id: _asString(d['id'] ?? d['device']),
        model: _asString(d['model']),
        size: _asInt(d['size_total']),
        status: _asString(d['status'], 'normal'),
        temperature: _asDouble(d['temp']),
      );
}

class ShareInfo {
  final String name;
  final String path;
  final int size;
  final String owner;
  const ShareInfo({required this.name, required this.path, this.size = 0, this.owner = ''});

  factory ShareInfo.fromJson(Map<String, dynamic> d) {
    final additional = (d['additional'] as Map?)?.cast<String, dynamic>() ?? const {};
    final owner = additional['owner'] is Map ? _asString((additional['owner'] as Map)['user']) : '';
    return ShareInfo(
      name: _asString(d['name']),
      path: _asString(d['path']),
      size: _asInt(additional['size']),
      owner: owner,
    );
  }
}

enum FileKind { folder, image, video, audio, document, archive, other }

class FileEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? mtime;
  final String owner;
  final bool? isWritable;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.mtime,
    this.owner = '',
    this.isWritable,
  });

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  FileKind get kind {
    if (isDir) return FileKind.folder;
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'tif', 'tiff', 'raw', 'cr2', 'nef', 'arw', 'dng'};
    const videos = {'mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'rmvb', '3gp', 'mpg', 'mpeg'};
    const audios = {'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'ape', 'wma', 'opus', 'dts', 'dsf'};
    const docs = {
      'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'log', 'csv', 'rtf', 'epub', 'odt', 'pages', 'numbers', 'key',
      'html', 'htm', 'json', 'xml', 'yaml', 'yml', 'dart', 'py', 'js', 'ts', 'java', 'kt', 'c', 'cpp', 'h', 'sh', 'conf', 'ini',
    };
    const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'iso', 'dmg'};
    if (images.contains(extension)) return FileKind.image;
    if (videos.contains(extension)) return FileKind.video;
    if (audios.contains(extension)) return FileKind.audio;
    if (docs.contains(extension)) return FileKind.document;
    if (archives.contains(extension)) return FileKind.archive;
    return FileKind.other;
  }

  factory FileEntry.fromJson(Map<String, dynamic> d) {
    final additional = (d['additional'] as Map?)?.cast<String, dynamic>() ?? const {};
    final time = (additional['time'] as Map?)?.cast<String, dynamic>() ?? const {};
    final perm = (additional['perm'] as Map?)?.cast<String, dynamic>() ?? const {};
    int? mtime;
    if (time['mtime'] is num) {
      mtime = (time['mtime'] as num).toInt();
    } else if (d['mtime'] is num) {
      mtime = (d['mtime'] as num).toInt();
    }
    return FileEntry(
      name: _asString(d['name'] ?? d['filename']),
      path: _asString(d['path']),
      isDir: d['isdir'] == true,
      size: _asInt(additional['size'] ?? d['size']),
      mtime: mtime == null ? null : DateTime.fromMillisecondsSinceEpoch(mtime * 1000),
      owner: additional['owner'] is Map ? _asString((additional['owner'] as Map)['user']) : '',
      isWritable: perm['is_writable'] is bool ? perm['is_writable'] as bool : null,
    );
  }
}

class DownloadTask {
  final String id;
  final String title;
  final String status;
  final int size;
  final int downloaded;
  final int speedDownload;
  final String destination;

  const DownloadTask({
    required this.id,
    required this.title,
    required this.status,
    this.size = 0,
    this.downloaded = 0,
    this.speedDownload = 0,
    this.destination = '',
  });

  double get progress => size <= 0 ? 0 : (downloaded / size).clamp(0.0, 1.0);

  bool get isActive => status == 'downloading' || status == 'waiting' || status == 'finishing' || status == 'hash_checking' || status == 'extracting';
  bool get isPaused => status == 'paused';
  bool get isFinished => status == 'finished' || status == 'seeding';

  String get statusLabel {
    switch (status) {
      case 'waiting':
        return '等待中';
      case 'downloading':
        return '下载中';
      case 'paused':
        return '已暂停';
      case 'finishing':
        return '正在完成';
      case 'finished':
        return '已完成';
      case 'hash_checking':
        return '校验中';
      case 'seeding':
        return '做种中';
      case 'extracting':
        return '解压中';
      case 'error':
        return '出错';
      default:
        return status.isEmpty ? '未知' : status;
    }
  }

  factory DownloadTask.fromJson(Map<String, dynamic> d) {
    final additional = (d['additional'] as Map?)?.cast<String, dynamic>() ?? const {};
    final transfer = (additional['transfer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final detail = (additional['detail'] as Map?)?.cast<String, dynamic>() ?? const {};
    return DownloadTask(
      id: _asString(d['id']),
      title: _asString(d['title']).isEmpty ? _asString(detail['title'], '未命名任务') : _asString(d['title']),
      status: _asString(d['status']),
      size: _asInt(d['size'] ?? transfer['size_downloaded']),
      downloaded: _asInt(transfer['size_downloaded']),
      speedDownload: _asInt(transfer['speed_download']),
      destination: _asString(detail['destination']),
    );
  }
}

class DsmPackage {
  final String id;
  final String name;
  final String version;
  final String status;
  final bool? startable;
  final String description;

  const DsmPackage({
    required this.id,
    required this.name,
    this.version = '',
    this.status = 'stopped',
    this.startable,
    this.description = '',
  });

  bool get isRunning {
    final value = status.toLowerCase();
    return value == 'running' || value == 'start' || value == 'started' || value == 'on';
  }

  bool get statusKnown => status.isNotEmpty;
  bool get canStart => startable != false && !isSystemService;
  String get displayName => name.isEmpty ? id : name;

  /// 群晖的系统级套件不允许被手动停止（startable=false）。
  bool get isSystemService => startable == false;

  bool get isDocker => id.toLowerCase().contains('docker') || id.toLowerCase().contains('container');

  DsmPackage copyWith({String? status}) => DsmPackage(
        id: id,
        name: name,
        version: version,
        status: status ?? this.status,
        startable: startable,
        description: description,
      );

  factory DsmPackage.fromJson(Map<String, dynamic> d) {
    // DSM 7 把 status / startable 放在 additional 对象里，不能只看顶层。
    final additional = d['additional'] is Map ? (d['additional'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    String pick(String key) => _asString(d[key] ?? additional[key]);
    final status = pick('status').isNotEmpty
        ? pick('status')
        : (pick('status_origin').isNotEmpty ? pick('status_origin') : (pick('package_status').isNotEmpty ? pick('package_status') : pick('state')));
    final runningFlag = d['running'] ?? d['is_running'] ?? additional['running'];
    final startable = d['startable'] ?? additional['startable'];
    return DsmPackage(
      id: _asString(d['id']),
      name: _asString(d['name'] ?? d['dname']),
      version: _asString(d['version']),
      status: status.isNotEmpty ? status : (runningFlag == true ? 'running' : ''),
      startable: startable is bool ? startable : null,
      description: _asString(d['description'] ?? additional['description']),
    );
  }
}

class DsmUser {
  final String name;
  final String description;
  final String group;
  final bool disabled;
  final String email;
  const DsmUser({required this.name, this.description = '', this.group = '', this.disabled = false, this.email = ''});

  factory DsmUser.fromJson(Map<String, dynamic> d) => DsmUser(
        name: _asString(d['name']),
        description: _asString(d['description']),
        group: d['groups'] is List && (d['groups'] as List).isNotEmpty ? _asString((d['groups'] as List).first) : '',
        disabled: d['disabled'] == true || d['expired'] == 'now',
        email: _asString(d['email']),
      );

  DsmUser copyWith({String? description, String? email}) => DsmUser(
        name: name,
        description: description ?? this.description,
        group: group,
        disabled: disabled,
        email: email ?? this.email,
      );
}

class LogEntry {
  final String who;
  final String what;
  final String time;
  final String from;
  const LogEntry({this.who = '', this.what = '', this.time = '', this.from = ''});

  factory LogEntry.fromJson(Map<String, dynamic> d) => LogEntry(
        who: _asString(d['who'] ?? d['user']),
        what: _asString(d['descr'] ?? d['what'] ?? d['event']),
        time: _asString(d['time']),
        from: _asString(d['logged_from'] ?? d['from']),
      );
}

class ScheduledTask {
  final String id;
  final String name;
  final String nextRun;
  final String lastStatus;
  final bool enabled;
  const ScheduledTask({required this.id, required this.name, this.nextRun = '', this.lastStatus = '', this.enabled = true});

  factory ScheduledTask.fromJson(Map<String, dynamic> d) => ScheduledTask(
        id: _asString(d['id']),
        name: _asString(d['name']),
        nextRun: _asString(d['next_trigger_time']),
        lastStatus: d['last_run_status'] is num ? '${d['last_run_status']}' : _asString(d['last_run_status']),
        enabled: d['enabled'] != false,
      );
}

class StorageSnapshot {
  final List<VolumeInfo> volumes;
  final List<DiskInfo> disks;
  const StorageSnapshot({this.volumes = const [], this.disks = const []});

  int get totalBytes => volumes.fold(0, (sum, v) => sum + v.total);
  int get usedBytes => volumes.fold(0, (sum, v) => sum + v.used);
  double get ratio => totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0);
}

String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(decimals);
  return '$text ${units[unit]}';
}

String formatSpeed(num bytesPerSecond, {bool compact = false}) {
  if (!compact) return '${formatBytes(bytesPerSecond)}/s';
  if (bytesPerSecond >= 1024 * 1024) {
    final mb = bytesPerSecond / 1024 / 1024;
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB/s';
  }
  if (bytesPerSecond >= 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

String formatUptime(int seconds) {  if (seconds <= 0) return '—';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '$days 天 $hours 小时';
  if (hours > 0) return '$hours 小时 $minutes 分';
  return '$minutes 分钟';
}

String formatDate(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (now.year == time.year) return '${time.month}月${time.day}日';
  return '${time.year}/${time.month}/${time.day}';
}

String encodeJsonParam(Object value) => jsonEncode(value);

/// 判断地址是否属于局域网（用于显示「局域网连接 / 远程连接」）。
bool isLanAddress(String host) {
  if (host.isEmpty) return false;
  if (host == "localhost" || host.endsWith(".local")) return true;
  final private = RegExp(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$").firstMatch(host);
  if (private != null) {
    final a = int.parse(private.group(1)!);
    final b = int.parse(private.group(2)!);
    if (a == 10 || a == 127) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 169 && b == 254) return true;
    return false;
  }
  // 单段主机名（如 nas、homecloud）通常也在局域网内
  return !host.contains(".");
}

enum DownloadToolType { dsm, qbittorrent, transmission, aria2 }

/// 用户配置的下载工具，可以是 DSM 自带的 Download Station，也可以是局域网里的 qBittorrent。
class DownloadTool {
  final String id;
  final DownloadToolType type;
  final String name;
  final String host;
  final String port;
  final bool https;
  final bool trustSelfSigned;
  final String username;
  final String password;
  final String apiKey;
  final String secret;

  const DownloadTool({
    required this.id,
    required this.type,
    this.name = '',
    this.host = '',
    this.port = '',
    this.https = false,
    this.trustSelfSigned = true,
    this.username = '',
    this.password = '',
    this.apiKey = '',
    this.secret = '',
  });

  String get baseUrl => '${https ? 'https' : 'http'}://$host:$port';

  String get label {
    if (name.isNotEmpty) return name;
    return switch (type) {
      DownloadToolType.dsm => 'Download Station',
      DownloadToolType.qbittorrent => 'qBittorrent',
      DownloadToolType.transmission => 'Transmission',
      DownloadToolType.aria2 => 'Aria2',
    };
  }

  String get typeLabel => switch (type) {
        DownloadToolType.dsm => '群晖 Download Station',
        DownloadToolType.qbittorrent => 'qBittorrent',
        DownloadToolType.transmission => 'Transmission',
        DownloadToolType.aria2 => 'Aria2',
      };

  DownloadTool copyWith({String? name, String? host, String? port, bool? https, String? username, String? password, String? apiKey, String? secret}) => DownloadTool(
        id: id,
        type: type,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        https: https ?? this.https,
        trustSelfSigned: trustSelfSigned,
        username: username ?? this.username,
        password: password ?? this.password,
        apiKey: apiKey ?? this.apiKey,
        secret: secret ?? this.secret,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'host': host,
        'port': port,
        'https': https,
        'trust_self_signed': trustSelfSigned,
        'username': username,
        'password': password,
        'api_key': apiKey,
        'secret': secret,
      };

  factory DownloadTool.fromJson(Map<String, dynamic> json) => DownloadTool(
        id: _asString(json['id']),
        type: DownloadToolType.values.firstWhere((e) => e.name == json['type'], orElse: () => DownloadToolType.qbittorrent),
        name: _asString(json['name']),
        host: _asString(json['host']),
        port: _asString(json['port']),
        https: json['https'] == true,
        trustSelfSigned: json['trust_self_signed'] != false,
        username: _asString(json['username']),
        password: _asString(json['password']),
        apiKey: _asString(json['api_key']),
        secret: _asString(json['secret']),
      );
}

enum PhotoSourceType { none, folder, synologyPhotos, immich }

class PhotoSource {
  final PhotoSourceType type;
  final String folderPath;
  final String immichUrl;
  final String immichKey;
  final bool trustSelfSigned;

  const PhotoSource({
    this.type = PhotoSourceType.none,
    this.folderPath = '',
    this.immichUrl = '',
    this.immichKey = '',
    this.trustSelfSigned = true,
  });

  bool get configured => type != PhotoSourceType.none;

  String get label => switch (type) {
        PhotoSourceType.none => '未配置',
        PhotoSourceType.folder => folderPath.isEmpty ? '相册目录' : folderPath,
        PhotoSourceType.synologyPhotos => 'Synology Photos',
        PhotoSourceType.immich => 'Immich',
      };

  PhotoSource copyWith({PhotoSourceType? type, String? folderPath, String? immichUrl, String? immichKey, bool? trustSelfSigned, bool clear = false}) => PhotoSource(
        type: type ?? this.type,
        folderPath: folderPath ?? this.folderPath,
        immichUrl: immichUrl ?? this.immichUrl,
        immichKey: immichKey ?? this.immichKey,
        trustSelfSigned: trustSelfSigned ?? this.trustSelfSigned,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'folder_path': folderPath,
        'immich_url': immichUrl,
        'immich_key': immichKey,
        'trust_self_signed': trustSelfSigned,
      };

  factory PhotoSource.fromJson(Map<String, dynamic> json) => PhotoSource(
        type: PhotoSourceType.values.firstWhere((e) => e.name == json['type'], orElse: () => PhotoSourceType.none),
        folderPath: _asString(json['folder_path']),
        immichUrl: _asString(json['immich_url']),
        immichKey: _asString(json['immich_key']),
        trustSelfSigned: json['trust_self_signed'] != false,
      );
}

class PhotoItem {
  final String id;
  final String name;
  final DateTime? takenAt;
  final DateTime? createdAt;
  final int size;
  final String path;
  final String thumbUrl;
  final String originalUrl;
  final Map<String, String> headers;

  const PhotoItem({
    required this.id,
    required this.name,
    this.takenAt,
    this.createdAt,
    this.size = 0,
    this.path = '',
    this.thumbUrl = '',
    this.originalUrl = '',
    this.headers = const {},
  });
}

/// 首页可自由开关的卡片。
enum HomeWidgetType { resource, storage, transfers, overview, network, disks, recentFiles, quickActions, photos, packages, logs, docker }

class CatalogPackage {
  final String id;
  final String name;
  final String version;
  final String description;
  final String category;
  final String iconUrl;
  final String source;
  final bool beta;

  const CatalogPackage({
    required this.id,
    required this.name,
    this.version = '',
    this.description = '',
    this.category = '',
    this.iconUrl = '',
    this.source = '',
    this.beta = false,
  });

  factory CatalogPackage.fromJson(Map<String, dynamic> d) => CatalogPackage(
        id: _asString(d['id'] ?? d['package']),
        name: _asString(d['dname'] ?? d['name'] ?? d['id']),
        version: _asString(d['version']),
        description: _asString(d['desc'] ?? d['description']),
        category: _asString(d['category'] ?? d['type']),
        iconUrl: _asString(((d['thumbnail'] as List?)?.isNotEmpty == true ? (d['thumbnail'] as List).first : null) ?? ((d['thumbnail_retina'] as List?)?.isNotEmpty == true ? (d['thumbnail_retina'] as List).first : null)),
        source: _asString(d['source']),
        beta: d['beta'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'category': category,
        'iconUrl': iconUrl,
        'source': source,
        'beta': beta,
      };
}

class PackageVolume {
  final String path;
  final String name;
  final int freeBytes;
  final String fsType;

  const PackageVolume({required this.path, required this.name, this.freeBytes = 0, this.fsType = ''});

  factory PackageVolume.fromJson(Map<String, dynamic> d) => PackageVolume(
        path: _asString(d['volume_path'] ?? d['path']),
        name: _asString(d['display_name'] ?? d['desc'] ?? d['volume_path']),
        freeBytes: int.tryParse('${d['size_free_byte'] ?? ''}') ?? 0,
        fsType: _asString(d['fs_type']),
      );
}

class SharedLink {
  final String id;
  final String url;
  final String expireDate;
  final String owner;
  const SharedLink({required this.id, required this.url, this.expireDate = '', this.owner = ''});

  factory SharedLink.fromJson(Map<String, dynamic> d) => SharedLink(
        id: _asString(d['id'] ?? d['link_id']),
        url: _asString(d['url'] ?? d['link_url']),
        expireDate: _asString(d['expire_date'] ?? d['date_expired']),
        owner: _asString(d['link_owner'] ?? d['owner']),
      );
}

class DockerContainer {
  final String name;
  final String status;
  final String image;
  final String id;
  final String ports;
  final double cpu;
  final int memory;

  const DockerContainer({
    required this.name,
    this.status = '',
    this.image = '',
    this.id = '',
    this.ports = '',
    this.cpu = 0,
    this.memory = 0,
  });

  bool get isRunning => _normalized == 'running';
  bool get isStopped => _normalized == 'stopped';
  bool get isError => _normalized == 'error';
  bool get statusKnown => status.isNotEmpty;

  String get _normalized {
    final value = status.toLowerCase();
    if (value == 'running' || value == 'up' || value == 'started' || value == 'active') return 'running';
    if (value == 'stopped' || value == 'exited' || value == 'down' || value == 'created') return 'stopped';
    if (value == 'error' || value == 'dead' || value == 'restarting') return 'error';
    return '';
  }

  String get statusLabel => switch (_normalized) {
        'running' => '运行中',
        'stopped' => '已停止',
        'error' => '异常',
        _ => '状态未知',
      };

  DockerContainer copyWith({String? status, double? cpu, int? memory}) => DockerContainer(
        name: name,
        status: status ?? this.status,
        image: image,
        id: id,
        ports: ports,
        cpu: cpu ?? this.cpu,
        memory: memory ?? this.memory,
      );
}

class DockerImage {
  final String repository;
  final String tag;
  final int size;
  final String id;

  const DockerImage({required this.repository, this.tag = '', this.size = 0, this.id = ''});

  String get displayName => tag.isEmpty ? repository : '$repository:$tag';
}