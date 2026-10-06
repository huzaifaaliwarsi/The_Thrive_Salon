import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'reports_provider.dart';
import 'ledger_provider.dart';
import 'salons_provider.dart';
import '../view_models/dashboard_view_model.dart';

class ExpenseFilter {
  final DateTime? start;
  final DateTime? end;
  final String? salonId;
  const ExpenseFilter({this.start, this.end, this.salonId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseFilter &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          salonId == other.salonId;

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ salonId.hashCode;
}

final expensesProvider = FutureProvider.family<List<dynamic>, ExpenseFilter>((ref, filter) async {
  final api = ref.watch(apiServiceProvider);
  return api.getExpenses(
    startDate: filter.start?.toIso8601String().split('T')[0],
    endDate: filter.end?.toIso8601String().split('T')[0],
    salonId: filter.salonId,
  );
});

class ExpenseController extends StateNotifier<AsyncValue<void>> {
  final Ref ref;
  ExpenseController(this.ref) : super(const AsyncValue.data(null));

  void _invalidateAll() {
    ref.invalidate(expensesProvider);
    ref.invalidate(reportsProvider);
    ref.invalidate(ledgerProvider);
    ref.invalidate(salonsProvider);
    ref.invalidate(dashboardViewModelProvider);
  }

  Future<void> addExpense(Map<String, dynamic> data) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(apiServiceProvider).createExpense(data);
      _invalidateAll();
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> updateExpense(String id, Map<String, dynamic> data) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(apiServiceProvider).updateExpense(id, data);
      _invalidateAll();
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> deleteExpense(String id) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(apiServiceProvider).deleteExpense(id);
      _invalidateAll();
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

final expenseControllerProvider = StateNotifierProvider<ExpenseController, AsyncValue<void>>((ref) {
  return ExpenseController(ref);
});
