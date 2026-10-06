import 'package:flutter_test/flutter_test.dart';
import 'package:salon_management_system/config/api_config.dart';

void main() {
  test('production accepts HTTPS and rejects local or missing API configuration', () {
    expect(ApiConfig.validateBaseUrl('https://api.thrive.isywarecloud.com/', release: true),
        'https://api.thrive.isywarecloud.com');
    for (final value in ['', 'http://127.0.0.1:3000', 'https://localhost',
      'https://10.0.2.2', 'https://192.168.1.5', 'https://172.16.0.1',
      'http://api.thrive.isywarecloud.com']) {
      expect(() => ApiConfig.validateBaseUrl(value, release: true), throwsStateError);
    }
    expect(ApiConfig.validateBaseUrl('', release: false), 'http://127.0.0.1:3000');
  });
}
