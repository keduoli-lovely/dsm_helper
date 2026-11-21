import 'dart:io';

/// 让 `Image.network` 等系统级 HTTP 请求也能访问自签证书的群晖。
/// 只对当前连接且开启「忽略证书校验」的主机放行，其余主机保持严格校验。
class TrustedHttpOverrides extends HttpOverrides {
  static String? trustedHost;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final allowed = trustedHost;
      return allowed != null && host == allowed;
    };
    return client;
  }
}
