import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../dsm/dsm_client.dart';
import '../dsm/dsm_service.dart';
import '../dsm/models.dart';

/// 下载工具的统一接口：DSM Download Station / qBittorrent / Transmission。
abstract class DownloadAdapter {
  Future<void> testConnection();
  Future<List<DownloadTask>> list();
  Future<void> add(String uri);
  Future<void> action(String action, List<String> ids);
  void dispose() {}
}

DownloadAdapter adapterFor(DownloadTool tool, DsmService? service) {
  switch (tool.type) {
    case DownloadToolType.dsm:
      if (service == null) throw const DsmException(-1, '请先连接群晖设备');
      return DsmDownloadAdapter(service);
    case DownloadToolType.qbittorrent:
      return QbittorrentAdapter(tool);
    case DownloadToolType.transmission:
      return TransmissionAdapter(tool);
  }
}

class DsmDownloadAdapter implements DownloadAdapter {
  final DsmService _service;
  DsmDownloadAdapter(this._service);

  @override
  Future<void> testConnection() async {
    await _service.downloads();
  }

  @override
  Future<List<DownloadTask>> list() => _service.downloads();

  @override
  Future<void> add(String uri) => _service.addDownload(uri);

  @override
  Future<void> action(String action, List<String> ids) => _service.downloadAction(action, ids);

  @override
  void dispose() {}
}

http.Client _clientFor(DownloadTool tool) {
  if (tool.https && tool.trustSelfSigned) return IOClient(DsmClient.trustAllHttpClient());
  return http.Client();
}

class QbittorrentAdapter implements DownloadAdapter {
  final DownloadTool tool;
  late final http.Client _http = _clientFor(tool);
  String? _cookie;

  QbittorrentAdapter(this.tool);

  Uri _uri(String path) => Uri.parse('${tool.baseUrl}$path');

  Map<String, String> get _headers => {
        if (tool.apiKey.isNotEmpty) 'Authorization': 'Bearer ${tool.apiKey}',
        if (_cookie != null) 'Cookie': _cookie!,
        'Referer': tool.baseUrl,
      };

  Future<void> _ensureAuth() async {
    if (tool.apiKey.isNotEmpty) return;
    if (_cookie != null) return;
    try {
    final response = await _http
        .post(
          _uri('/api/v2/auth/login'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded', 'Referer': tool.baseUrl},
          body: {'username': tool.username, 'password': tool.password},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 || response.body.trim().toLowerCase() != 'ok.') {
      throw const DsmException(-1, 'qBittorrent 登录失败：请检查账号密码（或使用 API Key）');
    }
    final cookie = response.headers['set-cookie'];
    if (cookie != null && cookie.isNotEmpty) _cookie = cookie.split(';').first.trim();
    } on TimeoutException {
      throw const DsmException(-1, '连接 qBittorrent 超时，请检查地址与端口');
    } on http.ClientException {
      throw const DsmException(-1, '无法连接到 qBittorrent，请检查地址、端口与服务是否启动');
    }
  }

  @override
  Future<void> testConnection() async {
    await _ensureAuth();
    final response = await _http.get(_uri('/api/v2/app/version'), headers: _headers).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw DsmException(-1, response.statusCode == 403 ? '认证失败，请检查账号密码或 API Key' : '连接失败（HTTP ${response.statusCode}）');
    }
  }

  @override
  Future<List<DownloadTask>> list() async {
    await _ensureAuth();
    final http.Response response;
    try {
      response = await _http.get(_uri('/api/v2/torrents/info'), headers: _headers).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const DsmException(-1, '读取 qBittorrent 任务超时');
    } on http.ClientException {
      throw const DsmException(-1, '无法连接到 qBittorrent，请检查服务是否启动');
    }
    if (response.statusCode != 200) {
      throw DsmException(-1, '读取 qBittorrent 任务失败（HTTP ${response.statusCode}）');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! List) return const [];
    return data.whereType<Map>().map((raw) {
      final map = raw.cast<String, dynamic>();
      final size = (map['size'] as num?)?.toInt() ?? 0;
      final progress = (map['progress'] as num?)?.toDouble() ?? 0;
      return DownloadTask(
        id: '${map['hash'] ?? ''}',
        title: '${map['name'] ?? '未命名任务'}',
        status: _statusFor('${map['state'] ?? ''}'),
        size: size,
        downloaded: (size * progress).round(),
        speedDownload: (map['dlspeed'] as num?)?.toInt() ?? 0,
        destination: '${map['save_path'] ?? ''}',
      );
    }).toList();
  }

  String _statusFor(String state) {
    if (state.contains('error') || state.contains('missing')) return 'error';
    if (state.contains('checking')) return 'hash_checking';
    if (state.contains('paused') || state == 'stoppedDL' || state == 'stoppedUP') return 'paused';
    if (state.endsWith('UP') || state == 'uploading' || state == 'stalledUP' || state == 'forcedUP') return 'finished';
    if (state == 'moving') return 'finishing';
    if (state.contains('queued') || state == 'allocating') return 'waiting';
    if (state.contains('DL') || state == 'downloading' || state == 'stalledDL' || state == 'metaDL') return 'downloading';
    return 'waiting';
  }

  @override
  Future<void> add(String uri) async {
    await _ensureAuth();
    final response = await _http
        .post(
          _uri('/api/v2/torrents/add'),
          headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'urls': uri, 'autoTMM': 'false'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw DsmException(-1, '添加任务失败（HTTP ${response.statusCode}）');
  }

  @override
  Future<void> action(String action, List<String> ids) async {
    await _ensureAuth();
    final hashes = ids.join('|');
    final path = switch (action) {
      'pause' => '/api/v2/torrents/stop',
      'resume' => '/api/v2/torrents/start',
      'delete' => '/api/v2/torrents/delete',
      _ => throw DsmException(-1, '不支持的操作：$action'),
    };
    final response = await _http
        .post(
          _uri(path),
          headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'hashes': hashes, if (action == 'delete') 'deleteFiles': 'false'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw DsmException(-1, '操作失败（HTTP ${response.statusCode}）');
  }

  @override
  void dispose() => _http.close();
}

class TransmissionAdapter implements DownloadAdapter {
  final DownloadTool tool;
  late final http.Client _http = _clientFor(tool);
  String? _sessionId;
  int _requestId = 0;

  TransmissionAdapter(this.tool);

  Uri get _uri => Uri.parse('${tool.baseUrl}/transmission/rpc');

  Map<String, String> get _headers => {
        if (tool.username.isNotEmpty) 'Authorization': 'Basic ${base64Encode(utf8.encode('${tool.username}:${tool.password}'))}',
        if (_sessionId != null) 'X-Transmission-Session-Id': _sessionId!,
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _rpc(String method, [Map<String, dynamic>? arguments]) async {
    final body = jsonEncode({'method': method, 'arguments': arguments ?? {}, 'tag': ++_requestId});
    var response = await _http.post(_uri, headers: _headers, body: body).timeout(const Duration(seconds: 10));
    if (response.statusCode == 409) {
      final id = response.headers['x-transmission-session-id'];
      if (id == null) throw const DsmException(-1, 'Transmission 会话握手失败');
      _sessionId = id;
      response = await _http.post(_uri, headers: _headers, body: body).timeout(const Duration(seconds: 10));
    }
    if (response.statusCode == 401) throw const DsmException(-1, 'Transmission 认证失败');
    if (response.statusCode != 200) throw DsmException(-1, 'Transmission 请求失败（HTTP ${response.statusCode}）');
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) throw const DsmException(-1, 'Transmission 返回格式异常');
    final result = json['result'];
    if (result != 'success') throw DsmException(-1, 'Transmission 返回错误：$result');
    return (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  @override
  Future<void> testConnection() async {
    await _rpc('session-get');
  }

  @override
  Future<List<DownloadTask>> list() async {
    final args = await _rpc('torrent-get', {
      'fields': ['id', 'name', 'status', 'totalSize', 'percentDone', 'rateDownload', 'downloadDir'],
    });
    final torrents = (args['torrents'] as List?) ?? const [];
    return torrents.whereType<Map>().map((raw) {
      final map = raw.cast<String, dynamic>();
      final size = (map['totalSize'] as num?)?.toInt() ?? 0;
      final progress = (map['percentDone'] as num?)?.toDouble() ?? 0;
      return DownloadTask(
        id: '${map['id']}',
        title: '${map['name'] ?? '未命名任务'}',
        status: _statusFor((map['status'] as num?)?.toInt() ?? 0),
        size: size,
        downloaded: (size * progress).round(),
        speedDownload: (map['rateDownload'] as num?)?.toInt() ?? 0,
        destination: '${map['downloadDir'] ?? ''}',
      );
    }).toList();
  }

  String _statusFor(int status) => switch (status) {
        0 => 'paused',
        1 || 2 => 'waiting',
        3 || 4 => 'downloading',
        5 || 6 => 'finished',
        _ => 'waiting',
      };

  @override
  Future<void> add(String uri) async {
    await _rpc('torrent-add', {'filename': uri});
  }

  @override
  Future<void> action(String action, List<String> ids) async {
    final numerical = ids.map(int.tryParse).whereType<int>().toList();
    switch (action) {
      case 'pause':
        await _rpc('torrent-stop', {'ids': numerical});
        break;
      case 'resume':
        await _rpc('torrent-start', {'ids': numerical});
        break;
      case 'delete':
        await _rpc('torrent-remove', {'ids': numerical, 'delete-local-data': false});
        break;
    }
  }

  @override
  void dispose() => _http.close();
}

/// 局域网下载工具发现：DSM Download Station、qBittorrent、Transmission。
class DownloadDiscovery {
  static Future<List<DownloadTool>> scan({DsmService? service, String host = '', bool trustSelfSigned = true}) async {
    final found = <DownloadTool>[];
    if (service != null && !service.demo) {
      try {
        await service.downloads();
        found.add(DownloadTool(
          id: 'dsm-${service.server.host}-${service.server.port}',
          type: DownloadToolType.dsm,
          name: 'Download Station',
          host: service.server.host,
          port: service.server.port,
          https: service.server.https,
        ));
      } catch (_) {}
    }

    final candidates = <Future<DownloadTool?>>[
      _probeQb(host, 8080, trustSelfSigned),
      _probeQb(host, 8081, trustSelfSigned),
      _probeQb(host, 8090, trustSelfSigned),
      _probeTransmission(host, 9091, trustSelfSigned),
    ];
    for (final result in await Future.wait(candidates)) {
      if (result != null) found.add(result);
    }
    return found;
  }

  static Future<DownloadTool?> _probeQb(String host, int port, bool trustSelfSigned) async {
    if (host.isEmpty) return null;
    final client = trustSelfSigned ? IOClient(DsmClient.trustAllHttpClient()) : http.Client();
    try {
      final response = await client
          .get(Uri.parse('http://$host:$port/api/v2/app/version'))
          .timeout(const Duration(milliseconds: 1200));
      if (response.statusCode == 200 || response.statusCode == 403) {
        return DownloadTool(
          id: 'qb-$host-$port',
          type: DownloadToolType.qbittorrent,
          name: 'qBittorrent',
          host: host,
          port: '$port',
        );
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  static Future<DownloadTool?> _probeTransmission(String host, int port, bool trustSelfSigned) async {
    if (host.isEmpty) return null;
    final client = trustSelfSigned ? IOClient(DsmClient.trustAllHttpClient()) : http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('http://$host:$port/transmission/rpc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'method': 'session-get'}),
          )
          .timeout(const Duration(milliseconds: 1200));
      if (response.statusCode == 409 || response.statusCode == 200) {
        return DownloadTool(
          id: 'tr-$host-$port',
          type: DownloadToolType.transmission,
          name: 'Transmission',
          host: host,
          port: '$port',
        );
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }
}
