import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final dashboardViewModelProvider = StateNotifierProvider<DashboardViewModel, AsyncValue<Map<String, dynamic>>>((ref) {
  return DashboardViewModel(ref.read(apiServiceProvider));
});

class DashboardViewModel extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final ApiService _apiService;

  DashboardViewModel(this._apiService) : super(const AsyncValue.loading()) {
    fetchMetrics();
  }

  Future<void> fetchMetrics() async {
    state = const AsyncValue.loading();
    try {
      final metrics = await _apiService.getDashboardMetrics();
      state = AsyncValue.data(metrics);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
