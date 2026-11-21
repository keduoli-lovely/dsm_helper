import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';

/// 轻量 Immich API 客户端：只依赖 /api/server/about、/api/search/metadata 与缩略图接口。
class ImmichClient {
  final String baseUrl;
  final String apiKey;
  final bool trustSelfSigned;
  late final http.Client _http = (baseUrl.startsWith('https') && trustSelfSigned)
      ? IOClient(DsmClient.trustAllHttpClient())
      : http.Client();

  ImmichClient({required String url, required this.apiKey, this.trustSelfSigned = true})
      : baseUrl = url.replaceFirst(RegExp(r'/+$'), '');

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get headers => {
        'x-api-key': apiKey,
        'Accept': 'application/json',
      };

  Future<void> testConnection() async {
    final response = await _http.get(_uri('/api/server/about'), headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const DsmException(-1, 'Immich 认证失败，请检查 API Key');
    }
    if (response.statusCode != 200) {
      throw DsmException(-1, '无法连接 Immich（HTTP ${response.statusCode}）');
    }
  }

  Future<List<PhotoItem>> search({int page = 1, int size = 80}) async {
    final response = await _http
        .post(
          _uri('/api/search/metadata'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'page': page, 'size': size}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw DsmException(-1, 'Immich 返回错误（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    List<dynamic> items = const [];
    if (decoded is Map) {
      final assets = decoded['assets'];
      if (assets is Map && assets['items'] is List) {
        items = assets['items'] as List;
      } else if (decoded['items'] is List) {
        items = decoded['items'] as List;
      }
    }
    final result = <PhotoItem>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      if ((item['type'] ?? 'IMAGE').toString().toUpperCase() != 'IMAGE') continue;
      final id = '${item['id']}';
      final exif = (item['exifInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
      final time = item['fileCreatedAt'] ?? item['localDateTime'] ?? exif['dateTimeOriginal'];
      DateTime? takenAt;
      if (time is String) takenAt = DateTime.tryParse(time)?.toLocal();
      final size = (item['fileSizeInByte'] as num?)?.toInt() ?? (exif['fileSizeInByte'] as num?)?.toInt() ?? 0;
      result.add(PhotoItem(
        id: id,
        name: '${item['originalFileName'] ?? item['originalPath'] ?? ''}',
        takenAt: takenAt,
        createdAt: takenAt,
        size: size,
        thumbUrl: thumbnailUrl(id, 'preview'),
        originalUrl: originalUrl(id),
        headers: {'x-api-key': apiKey},
      ));
    }
    return result;
  }

  String thumbnailUrl(String id, [String size = 'thumbnail']) => '$baseUrl/api/assets/$id/thumbnail?size=$size';

  String originalUrl(String id) => '$baseUrl/api/assets/$id/original';

  Future<String> createShareLink(String assetId) async {
    final response = await _http
        .post(
          _uri('/api/shared-links'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'type': 'INDIVIDUAL',
            'assetIds': [assetId],
            'allowDownload': true,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw DsmException(-1, 'Immich 创建分享链接失败（HTTP ${response.statusCode}）');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final key = data is Map ? (data['key'] ?? data['slug'] ?? data['id'] ?? '').toString() : '';
    if (key.isEmpty) throw const DsmException(-1, 'Immich 未返回分享链接');
    return '$baseUrl/share/$key';
  }

  void dispose() => _http.close();
}
