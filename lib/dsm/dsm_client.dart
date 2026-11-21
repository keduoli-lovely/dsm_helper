import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'models.dart';

class DsmException implements Exception {
  final int code;
  final String message;
  final String? api;
  const DsmException(this.code, this.message, {this.api});

  bool get needOtp => code == 403;
  bool get isAuthError => code == 400 || code == 401 || code == 402 || code == 407 || code == 408;

  @override
  String toString() => message;
}

/// 群晖 WebAPI 的底层 HTTP 客户端。
/// 兼容 DSM 6.x / 7.x，支持自签名 HTTPS 与 2FA。
class DsmClient {
  final DsmServer server;
  final http.Client _http;
  String sid;
  String cookie;
  void Function()? onAuthExpired;
  Map<String, int> _maxVersions = const {};

  DsmClient({required this.server, this.sid = '', this.cookie = ''}) : _http = _buildClient(server);

  static http.Client _buildClient(DsmServer server) {
    if (!server.https || !server.trustSelfSigned) {
      return http.Client();
    }
    final ioClient = HttpClient()
      ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 8);
    return IOClient(ioClient);
  }

  Uri get _webapi => Uri.parse('${server.baseUrl}/webapi/');

  Map<String, String> get _headers => {
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Origin': server.baseUrl,
        'Referer': server.baseUrl,
        if (cookie.isNotEmpty) 'Cookie': cookie,
      };

  bool get connected => sid.isNotEmpty;

  Future<void> login({
    required String account,
    required String password,
    String otpCode = '',
    bool rememberDevice = false,
  }) async {
    final data = await _raw('auth.cgi', {
      'account': account,
      'passwd': password,
      'otp_code': otpCode,
      'version': '4',
      'api': 'SYNO.API.Auth',
      'method': 'login',
      'session': 'webui',
      'format': 'sid',
      'enable_device_token': rememberDevice ? 'yes' : 'no',
    });
    final result = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    sid = (result['sid'] ?? '').toString();
    if (sid.isEmpty) {
      throw const DsmException(500, '登录失败：未获取到会话，请检查地址与端口');
    }
  }

  Future<void> logout() async {
    if (sid.isEmpty) return;
    try {
      await _raw('auth.cgi', {
        'api': 'SYNO.API.Auth',
        'version': '4',
        'method': 'logout',
        'session': 'webui',
        '_sid': sid,
      });
    } catch (_) {}
    sid = '';
  }

  /// 查询设备支持的各 API 最大版本，保证 DSM 6 / 7 都能用。
  Future<void> loadApiInfo() async {
    try {
      final data = await getRaw('query.cgi', {
        'api': 'SYNO.API.Info',
        'version': '1',
        'method': 'query',
        'query': 'all',
        'format': 'json',
      });
      final map = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final versions = <String, int>{};
      map.forEach((key, value) {
        if (value is Map && value['maxVersion'] is num) {
          versions[key] = (value['maxVersion'] as num).toInt();
        }
      });
      if (versions.isNotEmpty) _maxVersions = versions;
    } catch (_) {
      // query.cgi 在部分老版本不可用，忽略即可。
    }
  }

  int versionFor(String api, int preferred) {
    final max = _maxVersions[api];
    if (max == null) return preferred;
    return preferred > max ? max : preferred;
  }

  /// 调用 entry.cgi，返回 data 对象（Map / List / null）。
  Future<dynamic> call({
    required String api,
    required String method,
    int version = 1,
    Map<String, Object?> params = const {},
    String script = 'entry.cgi',
    bool useApiVersion = true,
  }) async {
    final query = <String, String>{
      'api': api,
      'method': method,
      'version': '${useApiVersion ? versionFor(api, version) : version}',
      if (sid.isNotEmpty) '_sid': sid,
    };
    for (final entry in params.entries) {
      final value = entry.value;
      if (value == null) continue;
      query[entry.key] = _encodeParam(value);
    }
    final data = await _raw(script, query);
    return data['data'];
  }

  Future<Map<String, dynamic>> callMap({
    required String api,
    required String method,
    int version = 1,
    Map<String, Object?> params = const {},
  }) async {
    final data = await call(api: api, method: method, version: version, params: params);
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Future<List<dynamic>> callList({
    required String api,
    required String method,
    int version = 1,
    Map<String, Object?> params = const {},
  }) async {
    final data = await call(api: api, method: method, version: version, params: params);
    if (data is List) return data;
    return const [];
  }

  /// 表单 POST 到 entry.cgi（上传文件等场景由调用方自行构造）。
  Future<dynamic> postRaw(String script, Map<String, String> body) async {
    final data = await _raw(script, body, post: true);
    return data['data'];
  }

  /// 上传本地文件到指定目录。
  Future<void> uploadFile(String localPath, String destDir) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw const DsmException(-5, '本地文件不存在');
    }
    await uploadStream(
      filename: localPath.split(Platform.pathSeparator).last,
      stream: file.openRead(),
      length: await file.length(),
      destDir: destDir,
    );
  }

  /// 以流的方式上传（兼容 Android 内容 URI）。
  Future<void> uploadStream({
    required String filename,
    required Stream<List<int>> stream,
    required int length,
    required String destDir,
  }) async {
    final uri = _webapi.replace(path: '${_webapi.path}entry.cgi', queryParameters: {
      'api': 'SYNO.FileStation.Upload',
      'method': 'upload',
      'version': '2',
      if (sid.isNotEmpty) '_sid': sid,
      'path': destDir,
      'create_parents': 'true',
      'overwrite': 'true',
    });
    final request = http.MultipartRequest('POST', uri)..headers.addAll(_headers);
    request.files.add(http.MultipartFile('file', stream, length, filename: filename));
    try {
      final streamed = await _http.send(request).timeout(const Duration(minutes: 30));
      final response = await http.Response.fromStream(streamed);
      _captureCookies(response);
      final text = utf8.decode(response.bodyBytes);
      final json = jsonDecode(text.replaceFirst('\uFEFF', ''));
      if (json is! Map || json['success'] != true) {
        final code = ((json is Map ? json['error'] : null) as Map?)?['code'];
        throw DsmException((code as num?)?.toInt() ?? -5, '上传失败（${code ?? '未知错误'}）');
      }
    } on DsmException {
      rethrow;
    } catch (e) {
      throw DsmException(-5, '上传失败：$e');
    }
  }

  Uri downloadUri(String path, {bool open = false}) {
    return _webapi.replace(path: '${_webapi.path}entry.cgi', queryParameters: {
      'api': 'SYNO.FileStation.Download',
      'method': 'download',
      'version': '2',
      'path': jsonEncode([path]),
      'mode': open ? 'open' : 'download',
      if (sid.isNotEmpty) '_sid': sid,
    });
  }

  Uri thumbnailUri(String path, {String size = 'small'}) {
    return _webapi.replace(path: '${_webapi.path}entry.cgi', queryParameters: {
      'api': 'SYNO.FileStation.Thumb',
      'method': 'get',
      'version': '2',
      'path': jsonEncode([path]),
      'size': size,
      if (sid.isNotEmpty) '_sid': sid,
    });
  }

  Future<Map<String, dynamic>> getRaw(String script, Map<String, String> query) async {
    return _raw(script, query, post: false);
  }

  Future<Map<String, dynamic>> _raw(
    String script,
    Map<String, String> params, {
    bool post = true,
  }) async {
    final uri = _webapi.replace(path: '${_webapi.path}$script');
    http.Response response;
    try {
      if (post) {
        response = await _http
            .post(uri, headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'}, body: params)
            .timeout(const Duration(seconds: 25));
      } else {
        response = await _http.get(uri.replace(queryParameters: params), headers: _headers).timeout(const Duration(seconds: 25));
      }
    } on TimeoutException {
      throw const DsmException(-1, '连接超时，请确认设备已开机且与手机在同一网络');
    } on HandshakeException catch (e) {
      throw DsmException(-2, 'HTTPS 证书校验失败：${e.message}');
    } on SocketException catch (e) {
      throw DsmException(-3, '无法连接到设备：${e.osError?.message ?? e.message}');
    } on http.ClientException catch (e) {
      throw DsmException(-3, '网络请求失败：${e.message}');
    }

    _captureCookies(response);

    if (response.statusCode >= 400) {
      throw DsmException(response.statusCode, '服务器返回 HTTP ${response.statusCode}');
    }

    dynamic decoded;
    try {
      final text = utf8.decode(response.bodyBytes);
      decoded = jsonDecode(text.replaceFirst('\uFEFF', ''));
    } catch (_) {
      throw const DsmException(-4, '返回内容不是合法的 JSON，请检查地址是否指向群晖 DSM');
    }
    if (decoded is! Map) {
      throw const DsmException(-4, '服务器返回格式异常');
    }
    final json = decoded.cast<String, dynamic>();
    if (json['success'] == true) return json;
    final error = (json['error'] as Map?)?.cast<String, dynamic>() ?? const {};
    final code = (error['code'] as num?)?.toInt() ?? -1;
    if (code == 106 && params['api'] != 'SYNO.API.Auth') {
      onAuthExpired?.call();
    }
    throw DsmException(code, _errorMessage(code), api: params['api']);
  }

  void _captureCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final found = <String, String>{};
    for (final name in ['did', 'id']) {
      final match = RegExp('(?:^|[;,\\s])$name=([^;,\\s]+)').firstMatch(raw);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty) found[name] = value;
    }
    if (found.isEmpty) return;
    final parts = cookie.isEmpty ? <String>[] : cookie.split('; ');
    found.forEach((name, value) {
      parts.removeWhere((e) => e.startsWith('$name='));
      parts.add('$name=$value');
    });
    cookie = parts.join('; ');
  }

  static String _encodeParam(Object value) {
    if (value is bool) return value ? 'true' : 'false';
    if (value is List || value is Map) return jsonEncode(value);
    return value.toString();
  }

  static String _errorMessage(int code) {
    switch (code) {
      case 100:
        return '操作失败（100）';
      case 101:
        return '参数错误（101）';
      case 102:
        return '接口不存在或该设备不支持此功能';
      case 103:
        return '该功能需要登录后使用，请重新登录';
      case 104:
        return '版本不匹配，请重新登录后再试';
      case 105:
        return '没有权限（105）';
      case 106:
        return '登录会话已失效，请重新登录';
      case 107:
        return '连接超时或网络不稳定';
      case 108:
        return '会话已被锁定';
      case 109:
        return '文件不存在或无法访问';
      case 110:
        return '磁盘空间不足';
      case 400:
        return '账号或密码错误';
      case 401:
        return '账号已被停用';
      case 402:
        return '账号没有访问权限';
      case 403:
        return '需要两步验证动态码';
      case 404:
        return '动态验证码错误';
      case 407:
        return 'IP 已被封禁，请稍后再试';
      case 408:
        return '账号密码已过期，需在 DSM 中修改';
      case 409:
        return '密码错误次数过多，请稍后再试';
      case 500:
        return '未知错误（500）';
      default:
        return '请求失败（$code）';
    }
  }
}
