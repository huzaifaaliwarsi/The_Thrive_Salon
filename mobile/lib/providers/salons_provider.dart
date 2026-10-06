import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final salonsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return await apiService.getSalons();
});
