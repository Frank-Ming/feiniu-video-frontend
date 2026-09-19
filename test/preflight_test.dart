// 临时 preflight：验证关键逻辑（不依赖 flutter binding）
import 'package:flutter_test/flutter_test.dart';
import 'package:feiniu_video/services/api_service.dart';

void main() {
  group('ApiService.isLanHost', () {
    test('内网 IPv4 识别', () {
      expect(ApiService(baseUrl: 'http://192.168.1.100:6969').isLanHost, true);
      expect(ApiService(baseUrl: 'http://192.168.0.1:8000').isLanHost, true);
      expect(ApiService(baseUrl: 'http://10.0.0.5:6969').isLanHost, true);
      expect(ApiService(baseUrl: 'http://172.16.5.10:80').isLanHost, true);
      expect(ApiService(baseUrl: 'http://172.31.255.254:1').isLanHost, true);
      expect(ApiService(baseUrl: 'http://172.32.0.1:1').isLanHost, false);
    });

    test('公网域名识别为外网', () {
      expect(ApiService(baseUrl: 'http://www.zming.fun:6969').isLanHost, false);
      expect(ApiService(baseUrl: 'https://example.com').isLanHost, false);
      expect(ApiService(baseUrl: 'http://1.2.3.4:6969').isLanHost, false);
    });

    test('localhost/127 为内网', () {
      expect(ApiService(baseUrl: 'http://localhost:6969').isLanHost, true);
      expect(ApiService(baseUrl: 'http://127.0.0.1:6969').isLanHost, true);
    });

    test('奇怪的 host 也安全返回 false', () {
      expect(ApiService(baseUrl: 'http://[::1]:6969').isLanHost, true);
      expect(ApiService(baseUrl: 'http://').isLanHost, false);
      expect(ApiService(baseUrl: 'not a url').isLanHost, false);
    });
  });
}
