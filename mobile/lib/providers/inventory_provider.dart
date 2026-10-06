import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../providers/services_provider.dart';
import '../view_models/dashboard_view_model.dart';

final inventoryProvider = StateNotifierProvider<InventoryNotifier, AsyncValue<List<dynamic>>>((ref) {
  return InventoryNotifier(ref);
});

class InventoryNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final Ref _ref;

  InventoryNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchItems();
  }

  ApiService get _apiService => _ref.read(apiServiceProvider);

  Future<void> fetchItems() async {
    state = const AsyncValue.loading();
    try {
      final items = await _apiService.getInventoryItems();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addItem(Map<String, dynamic> data) async {
    try {
      await _apiService.createInventoryItem(data);
      _ref.invalidate(servicesProvider);
      _ref.invalidate(dashboardViewModelProvider);
      await fetchItems();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addTransaction(Map<String, dynamic> data) async {
    try {
      await _apiService.createInventoryTransaction(data);
      await fetchItems();
    } catch (e) {
      rethrow;
    }
  }
}

final vendorsProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(apiServiceProvider).getVendors();
});

final purchasesProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(apiServiceProvider).getPurchases();
});
