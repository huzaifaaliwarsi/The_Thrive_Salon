import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/service_model.dart';

class ReportParams {
  final DateTime start;
  final DateTime end;
  final String? groupBy;
  final String? staffId;
  final String? salonId;

  ReportParams({required this.start, required this.end, this.groupBy, this.staffId, this.salonId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportParams &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          groupBy == other.groupBy &&
          staffId == other.staffId &&
          salonId == other.salonId;

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ groupBy.hashCode ^ staffId.hashCode ^ salonId.hashCode;
}

final reportsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, ReportParams>((ref, params) async {
  final api = ref.watch(apiServiceProvider);
  
  try {
    final results = await Future.wait([
      api.getReportsSummary(params.start, params.end, groupBy: params.groupBy, staffId: params.staffId, salonId: params.salonId),
      api.getTopServices(start: params.start, end: params.end, limit: 10, staffId: params.staffId, salonId: params.salonId),
    ]);

    final summary = results[0] as Map<String, dynamic>;
    final topServices = results[1] as List<dynamic>;
    
    print('[ReportsProvider] Summary keys: ${summary.keys.toList()}');
    print('[ReportsProvider] Staff ID: ${params.staffId}');
    print('[ReportsProvider] Total Sales: ${summary['totalSales']}');
    print('[ReportsProvider] Base Salary: ${summary['baseSalary']}');
    print('[ReportsProvider] Breakdown items: ${(summary['breakdown'] as List?)?.length ?? 0}');
    
    // Fetch recent sales separately with error handling (it's not critical for the report)
    List<dynamic> rawSales = [];
    try {
      final startStr = "${params.start.year.toString().padLeft(4, '0')}-${params.start.month.toString().padLeft(2, '0')}-${params.start.day.toString().padLeft(2, '0')}";
      final endStr = "${params.end.year.toString().padLeft(4, '0')}-${params.end.month.toString().padLeft(2, '0')}-${params.end.day.toString().padLeft(2, '0')}";
      rawSales = await api.getSales(
        startDate: startStr,
        endDate: endStr,
        salonId: params.salonId,
      );
    } catch (e) {

      print('Warning: Failed to fetch recent sales: $e');
      // Continue without sales data
    }

    final result = {
      ...summary,
      'topServices': topServices,
      'recentSales': rawSales,
    };
    
    print('[ReportsProvider] Final result keys: ${result.keys.toList()}');
    return result;
  } catch (e) {
    rethrow;
  }
});

final allInventoryTransactionsProvider = FutureProvider.autoDispose.family<List<dynamic>, ReportParams>((ref, params) async {
  final api = ref.watch(apiServiceProvider);
  return await api.getAllInventoryTransactions(
    startDate: params.start.toUtc().toIso8601String(),
    endDate: params.end.toUtc().toIso8601String(),
  );
});

final allInventoryTransactionsForSalonProvider = FutureProvider.autoDispose.family<List<dynamic>, ReportParams>((ref, params) async {
  final api = ref.watch(apiServiceProvider);
  return await api.getAllInventoryTransactions(
    salonId: params.salonId,
    startDate: params.start.toUtc().toIso8601String(),
    endDate: params.end.toUtc().toIso8601String(),
  );
});

final clientsForSalonProvider = FutureProvider.family<List<dynamic>, String?>((ref, salonId) async {
  final api = ref.watch(apiServiceProvider);
  return await api.getClients(salonId: salonId);
});

final servicesForSalonProvider = FutureProvider.family<List<Service>, String?>((ref, salonId) async {
  final api = ref.watch(apiServiceProvider);
  final raw = await api.getServices(salonId: salonId);
  return raw.map((s) => Service.fromJson(s as Map<String, dynamic>)).toList();
});

final inventoryForSalonProvider = FutureProvider.family<List<dynamic>, String?>((ref, salonId) async {
  final api = ref.watch(apiServiceProvider);
  return await api.getInventoryItems(salonId: salonId);
});

final attendanceForSalonProvider = FutureProvider.family<List<dynamic>, String?>((ref, salonId) async {
  final api = ref.watch(apiServiceProvider);
  return await api.getAttendance(salonId: salonId);
});
