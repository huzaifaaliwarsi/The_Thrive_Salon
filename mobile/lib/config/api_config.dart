import 'package:flutter/foundation.dart';

class ApiConfig {
  static final String baseUrl = validateBaseUrl(
    const String.fromEnvironment('API_BASE_URL'),
    release: kReleaseMode,
  );

  static String validateBaseUrl(String value, {required bool release}) {
    final configured = value.trim();
    if (configured.isEmpty) {
      return 'http://127.0.0.1:3001';
    }
    final uri = Uri.tryParse(configured);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw StateError('API_BASE_URL must be a valid HTTP(S) origin.');
    }
    var sanitized = configured.replaceFirst(RegExp(r'/+$'), '');
    if (sanitized.toLowerCase().endsWith('/api')) {
      sanitized = sanitized.substring(0, sanitized.length - 4).replaceFirst(RegExp(r'/+$'), '');
    }
    return sanitized;
  }
}
