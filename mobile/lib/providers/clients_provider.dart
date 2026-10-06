import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final clientsProvider = StateNotifierProvider<ClientsNotifier, AsyncValue<List<dynamic>>>((ref) {
  return ClientsNotifier(ref.watch(apiServiceProvider));
});

class ClientsNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _apiService;

  ClientsNotifier(this._apiService) : super(const AsyncValue.loading()) {
    fetchClients();
  }

  Future<void> fetchClients() async {
    state = const AsyncValue.loading();
    try {
      final clients = await _apiService.getClients();
      state = AsyncValue.data(clients);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addClient(Map<String, dynamic> data) async {
    try {
      await _apiService.createClient(data);
      await fetchClients();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> bulkAddClients(List<Map<String, dynamic>> clients) async {
    try {
      // Reduced chunk size to 20 for maximum stability on slow networks/Vercel timeouts
      const int chunkSize = 20;
      for (int i = 0; i < clients.length; i += chunkSize) {
        final end = (i + chunkSize < clients.length) ? i + chunkSize : clients.length;
        final chunk = clients.sublist(i, end);
        await _apiService.bulkCreateClients(chunk);
        
        // Add a small delay between chunks for Flutter Web stability
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await fetchClients();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateClient(String id, Map<String, dynamic> data) async {
    try {
      await _apiService.updateClient(id, data);
      await fetchClients();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteClient(String id) async {
    try {
      await _apiService.deleteClient(id);
      await fetchClients();
    } catch (e) {
      rethrow;
    }
  }
}
