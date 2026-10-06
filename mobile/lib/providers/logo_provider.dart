import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

final logoProvider = Provider<Uint8List?>((ref) {
  final user = ref.watch(authProvider);
  final logoBase64 = user?['salon']?['logo'] as String?;
  
  if (logoBase64 != null && logoBase64.startsWith('data:image')) {
    try {
      return base64.decode(logoBase64.split(',').last);
    } catch (_) {
      return null;
    }
  }
  return null;
});
