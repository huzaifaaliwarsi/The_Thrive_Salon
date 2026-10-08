import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/payment_account.dart';
import '../services/api_service.dart';

final paymentAccountsProvider = StateNotifierProvider<PaymentAccountsNotifier, AsyncValue<List<PaymentAccount>>>((ref) {
  return PaymentAccountsNotifier(ref.watch(apiServiceProvider));
});

final activePaymentAccountsProvider = Provider<List<PaymentAccount>>((ref) {
  final accountsAsync = ref.watch(paymentAccountsProvider);
  return accountsAsync.maybeWhen(
    data: (accounts) => accounts.where((a) => a.isActive).toList(),
    orElse: () => [],
  );
});

class PaymentAccountsNotifier extends StateNotifier<AsyncValue<List<PaymentAccount>>> {
  final ApiService _apiService;

  PaymentAccountsNotifier(this._apiService) : super(const AsyncValue.loading()) {
    fetchAccounts();
  }

  Future<void> fetchAccounts({bool includeInactive = true}) async {
    state = const AsyncValue.loading();
    try {
      final rawList = await _apiService.getPaymentAccounts(includeInactive: includeInactive);
      final accounts = rawList.map((item) => PaymentAccount.fromJson(Map<String, dynamic>.from(item))).toList();
      state = AsyncValue.data(accounts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<PaymentAccount> createAccount(Map<String, dynamic> data) async {
    try {
      final res = await _apiService.createPaymentAccount(data);
      final created = PaymentAccount.fromJson(Map<String, dynamic>.from(res));
      await fetchAccounts();
      return created;
    } catch (e) {
      rethrow;
    }
  }

  Future<PaymentAccount> updateAccount(String id, Map<String, dynamic> data) async {
    try {
      final res = await _apiService.updatePaymentAccount(id, data);
      final updated = PaymentAccount.fromJson(Map<String, dynamic>.from(res));
      await fetchAccounts();
      return updated;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteAccount(String id, {bool permanent = false}) async {
    try {
      await _apiService.deletePaymentAccount(id, permanent: permanent);
      await fetchAccounts();
    } catch (e) {
      rethrow;
    }
  }
}
