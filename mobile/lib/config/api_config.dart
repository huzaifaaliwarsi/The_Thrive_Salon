import 'package:flutter/foundation.dart';

class ApiConfig {
  static final String baseUrl = validateBaseUrl(
    const String.fromEnvironment('API_BASE_URL'),
    release: kReleaseMode,
  );

  static String validateBaseUrl(String value, {required bool release}) {
    final configured = value.trim();
    if (configured.isEmpty) {
      if (release) {
        throw StateError('API_BASE_URL is required for production builds.');
      }
      return 'http://127.0.0.1:3000';
    }
    final uri = Uri.tryParse(configured);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw StateError('API_BASE_URL must be a valid HTTP(S) origin.');
    }
    final host = uri.host.toLowerCase();
    if (release && (uri.scheme != 'https' || host == 'localhost' ||
        host.endsWith('.localhost') || host == '::1' || host == '0.0.0.0' ||
        host.startsWith('127.') || host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host))) {
      throw StateError('Production builds require a public HTTPS API URL.');
    }
    var sanitized = configured.replaceFirst(RegExp(r'/+$'), '');
    if (sanitized.toLowerCase().endsWith('/api')) {
      sanitized = sanitized.substring(0, sanitized.length - 4).replaceFirst(RegExp(r'/+$'), '');
    }
    return sanitized;
  }
}
