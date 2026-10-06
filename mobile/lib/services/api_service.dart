import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/auth_provider.dart';
import '../config/api_config.dart';

final apiServiceProvider = Provider((ref) => ApiService(ref));


class ApiService {
  final Ref _ref;
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));
  CancelToken _cancelToken = CancelToken();

  ApiService(this._ref) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        const storage = FlutterSecureStorage();
        final token = await storage.read(key: 'token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.headers['Accept'] = 'application/json';
        if (options.path.startsWith('/api/api/')) {
          options.path = options.path.replaceFirst('/api/api/', '/api/');
        }
        options.cancelToken = _cancelToken;
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final isLoginRequest = error.requestOptions.path.contains('/api/auth/login');
          if (!isLoginRequest) {
            _ref.read(authProvider.notifier).logout();
          }
        }
        return handler.next(error);
      },
    ));
  }

  void cancelAllRequests() {
    _cancelToken.cancel();
    _cancelToken = CancelToken();
  }

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final response = await _dio.get('/api/auth/me');
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch profile'));
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post('/api/auth/login', data: {
        'email': email,
        'password': password,
      });
      
      if (response.statusCode == 200) {
        var data = _processData(response.data);
        if (data is! Map) {
           throw Exception('Unexpected data type from server: ${data.runtimeType}. Data: $data');
        }
        const storage = FlutterSecureStorage();
        await storage.write(key: 'token', value: data['token']?.toString());
        await storage.write(key: 'user', value: jsonEncode(data['user']));
        return Map<String, dynamic>.from(data);
      }
      throw Exception('Login failed');
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Login failed'));
    }
  }

  Future<Map<String, dynamic>> getDashboardMetrics({String? salonId}) async {
    try {
      final response = await _dio.get('/api/dashboard/metrics', queryParameters: {
        if (salonId != null) 'salonId': salonId,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch metrics'));
    }
  }

  Future<Map<String, dynamic>> getReportsSummary(DateTime start, DateTime end, {String? groupBy, String? staffId, String? salonId}) async {
    try {
      final startStr = "${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}";
      final endStr = "${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}";
      final response = await _dio.get('/api/reports/summary', queryParameters: {
        'startDate': startStr,
        'endDate': endStr,
        if (groupBy != null) 'groupBy': groupBy,
        if (staffId != null) 'staffId': staffId,
        if (salonId != null) 'salonId': salonId,
        'timezoneOffset': DateTime.now().timeZoneOffset.inMinutes.toString(),
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch report'));
    }
  }

  Future<String> exportReportCsv(DateTime start, DateTime end, {String? staffId, String? salonId}) async {
    try {
      final startStr = "${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}";
      final endStr = "${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}";
      final response = await _dio.get('/api/reports/export', queryParameters: {
        'startDate': startStr,
        'endDate': endStr,
        if (staffId != null) 'staffId': staffId,
        if (salonId != null) 'salonId': salonId,
        'timezoneOffset': DateTime.now().timeZoneOffset.inMinutes.toString(),
      });
      return response.data.toString();
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to export report'));
    }
  }

  Future<List<dynamic>> getStaff({String? salonId}) async {
    try {
      final response = await _dio.get('/api/staff', queryParameters: {
        if (salonId != null) 'salonId': salonId,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch staff'));
    }
  }

  Future<void> createStaff(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/staff', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create staff'));
    }
  }

  Future<void> updateStaff(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/staff/$id', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update staff'));
    }
  }

  Future<void> toggleUserLock(String userId) async {
    try {
      final response = await _dio.patch('/api/auth/users/$userId/toggle-lock');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to toggle status'));
    }
  }

  Future<void> resetUserPassword(String userId, String newPassword) async {
    try {
      final response = await _dio.post('/api/auth/users/$userId/reset-password', data: {'newPassword': newPassword});
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to reset password'));
    }
  }

  Future<List<dynamic>> getServices({String? salonId}) async {
    try {
      final response = await _dio.get('/api/services', queryParameters: {
        if (salonId != null) 'salonId': salonId,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch services'));
    }
  }

  Future<void> createService(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/services', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create service'));
    }
  }

  Future<void> bulkCreateServices(List<Map<String, dynamic>> servicesList) async {
    try {
      final response = await _dio.post('/api/services/bulk', data: {'servicesList': servicesList});
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to bulk create services'));
    }
  }

  Future<dynamic> bulkCreateStaff(List<Map<String, dynamic>> staffList) async {
    try {
      final response = await _dio.post('/api/staff/bulk', data: {'staffList': staffList});
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to bulk create staff members'));
    }
  }

  Future<void> updateService(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/services/$id', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update service'));
    }
  }

  Future<List<dynamic>> getSales({String? status, String? salonId, String? startDate, String? endDate}) async {
    try {
      final response = await _dio.get('/api/sales', queryParameters: {
        if (status != null) 'status': status,
        if (salonId != null) 'salonId': salonId,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        'timezoneOffset': DateTime.now().timeZoneOffset.inMinutes.toString(),
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch sales history'));
    }
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> saleData) async {
    try {
      final response = await _dio.post('/api/sales', data: saleData);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to process sale'));
    }
  }

  Future<Map<String, dynamic>> updateSale(String id, Map<String, dynamic> saleData) async {
    try {
      final response = await _dio.put('/api/sales/$id', data: saleData);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update sale'));
    }
  }

  Future<void> deleteSale(String id) async {
    try {
      final response = await _dio.delete('/api/sales/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete sale'));
    }
  }

  Future<List<dynamic>> getSalons() async {
    try {
      final response = await _dio.get('/api/salons');
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch salons'));
    }
  }

  Future<Map<String, dynamic>> createSalon(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/salons', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create salon'));
    }
  }

  Future<List<dynamic>> getAttendance({String? salonId}) async {
    try {
      final response = await _dio.get('/api/attendance', queryParameters: {
        if (salonId != null) 'salonId': salonId,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch attendance'));
    }
  }

  Future<void> checkIn() async {
    try {
      final response = await _dio.post('/api/attendance/check-in');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Check-in failed'));
    }
  }

  Future<void> checkOut({String? staffId}) async {
    try {
      final response = await _dio.post('/api/attendance/check-out', data: staffId != null ? {'staffId': staffId} : {});
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Check-out failed'));
    }
  }

  Future<List<dynamic>> getAppointments({String? staffId}) async {
    try {
      final response = await _dio.get('/api/appointments', queryParameters: staffId != null ? {'staffId': staffId} : null);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch appointments'));
    }
  }

  Future<void> createAppointment(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/appointments', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create appointment'));
    }
  }

  Future<void> updateAppointmentStatus(String id, String status, {String? staffId}) async {
    try {
      final response = await _dio.patch('/api/appointments/$id', data: {
        'status': status,
        if (staffId != null) 'staffId': staffId,
      });
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update appointment'));
    }
  }

  Future<void> updateAppointment(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/appointments/$id', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to reschedule appointment'));
    }
  }

  Future<Map<String, dynamic>> extendSubscription(
    String salonId, {
    int? days,
    String? newDate,
    bool? isLifetime,
  }) async {
    try {
      final response = await _dio.patch('/api/salons/$salonId/subscription', data: {
        if (days != null) 'days': days,
        if (newDate != null) 'newDate': newDate,
        if (isLifetime != null) 'isLifetime': isLifetime,
      });
      final data = _processData(response.data);
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to refill subscription'));
    }
  }

  Future<void> resetSalonOwnerPassword(String salonId, String newPassword) async {
    try {
      final response = await _dio.patch('/api/salons/$salonId/owner-password', data: {'newPassword': newPassword});
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to reset owner password'));
    }
  }

  Future<void> toggleSuspension(String salonId) async {
    try {
      final response = await _dio.patch('/api/salons/$salonId/toggle-suspension');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to toggle suspension'));
    }
  }

  Future<void> updateSalon(String salonId, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/salons/$salonId', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update salon'));
    }
  }

  Future<void> markAttendance(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/attendance/mark', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to mark attendance'));
    }
  }

  Future<void> markBulkAttendance(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/attendance/bulk', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to mark bulk attendance'));
    }
  }

  Future<void> lockAttendance(String date) async {
    try {
      final response = await _dio.post('/api/attendance/lock', data: {'date': date});
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to lock attendance'));
    }
  }

  Future<Map<String, dynamic>> getAttendanceLockStatus(String date) async {
    try {
      final response = await _dio.get('/api/attendance/lock-status', queryParameters: {'date': date});
      return _processData(response.data) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to check lock status'));
    }
  }

  Future<void> updateSalonSettings(Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/salons/settings/me', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update salon settings'));
    }
  }

  Future<void> recalculateCashDrawer({String? salonId}) async {
    try {
      final payload = salonId != null ? {'salonId': salonId} : {};
      final response = await _dio.post('/api/salons/settings/me/recalculate-cash', data: payload);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to recalculate cash drawer'));
    }
  }

  Future<void> approveAttendance(String id) async {
    try {
      final response = await _dio.patch('/api/attendance/$id/approve');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to approve attendance'));
    }
  }

  Future<void> rejectAttendance(String id) async {
    try {
      final response = await _dio.patch('/api/attendance/$id/reject');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to reject attendance'));
    }
  }

  Future<void> deleteService(String id) async {
    try {
      final response = await _dio.delete('/api/services/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete service'));
    }
  }

  Future<void> deleteStaff(String id) async {
    try {
      final response = await _dio.delete('/api/staff/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete staff'));
    }
  }

  Future<void> deleteSalon(String id) async {
    try {
      final response = await _dio.delete('/api/salons/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete salon'));
    }
  }

  Future<List<dynamic>> getExpenses({String? startDate, String? endDate, String? salonId}) async {
    try {
      final response = await _dio.get('/api/expenses', queryParameters: {
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        if (salonId != null) 'salonId': salonId,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch expenses'));
    }
  }

  Future<Map<String, dynamic>> createExpense(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/expenses', data: data);
      return Map<String, dynamic>.from(_processData(response.data));
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create expense'));
    }
  }

  Future<void> updateExpense(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/expenses/$id', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update expense'));
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      final response = await _dio.delete('/api/expenses/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete expense'));
    }
  }

  Future<void> logout() async {
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
  }

  Future<List<dynamic>> getTopServices({DateTime? start, DateTime? end, int limit = 5, String? staffId, String? salonId}) async {
    try {
      final startStr = start != null ? "${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}" : null;
      final endStr = end != null ? "${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}" : null;
      final response = await _dio.get('/api/reports/top-services', queryParameters: {
        if (startStr != null) 'startDate': startStr,
        if (endStr != null) 'endDate': endStr,
        'limit': limit,
        if (staffId != null) 'staffId': staffId,
        if (salonId != null) 'salonId': salonId,
        'timezoneOffset': DateTime.now().timeZoneOffset.inMinutes.toString(),
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch top services'));
    }
  }

  Future<void> voidSale(String id, {String reason = 'Voided by Owner'}) async {
    try {
      final response = await _dio.patch('/api/sales/$id/void', data: {'reason': reason});
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to void sale'));
    }
  }

  // Salary Deduction Methods
  Future<List<dynamic>> getSalaryDeductions({String? staffId, DateTime? startDate, DateTime? endDate}) async {
    try {
      final response = await _dio.get('/api/salary', queryParameters: {
        if (staffId != null) 'staffId': staffId,
        if (startDate != null) 'startDate': startDate.toIso8601String().split('T')[0],
        if (endDate != null) 'endDate': endDate.toIso8601String().split('T')[0],
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch salary deductions'));
    }
  }

  Future<Map<String, dynamic>> createSalaryDeduction(String staffId, String type, double amount, {String? reason, String? date, String? paymentMethod}) async {
    try {
      final response = await _dio.post('/api/salary', data: {
        'staffId': staffId,
        'type': type, // 'DEDUCTION' or 'ADVANCE'
        'amount': amount,
        if (reason != null) 'reason': reason,
        if (date != null) 'date': date,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
      });
      return Map<String, dynamic>.from(_processData(response.data));
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create salary deduction'));
    }
  }

  Future<void> updateSalaryDeduction(String id, {String? type, double? amount, String? reason, String? date}) async {
    try {
      final response = await _dio.patch('/api/salary/$id', data: {
        if (type != null) 'type': type,
        if (amount != null) 'amount': amount,
        if (reason != null) 'reason': reason,
        if (date != null) 'date': date,
      });
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update salary deduction'));
    }
  }

  Future<void> deleteSalaryDeduction(String id) async {
    try {
      final response = await _dio.delete('/api/salary/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete salary deduction'));
    }
  }

  // --- Clients API ---

  Future<List<dynamic>> getClients({String? salonId}) async {
    try {
      final response = await _dio.get('/api/clients', queryParameters: {
        if (salonId != null) 'salonId': salonId,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch clients'));
    }
  }

  Future<Map<String, dynamic>> createClient(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/clients', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create client'));
    }
  }

  Future<void> bulkCreateClients(List<Map<String, dynamic>> clients) async {
    try {
      await _dio.post('/api/clients/bulk', data: {'clients': clients});
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Bulk import failed'));
    }
  }

  Future<Map<String, dynamic>> updateClient(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/clients/$id', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update client'));
    }
  }

  Future<void> deleteClient(String id) async {
    try {
      final response = await _dio.delete('/api/clients/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete client'));
    }
  }

  // --- Inventory API ---

  Future<List<dynamic>> getVendors() async {
    try {
      final response = await _dio.get('/api/inventory/vendors');
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch vendors'));
    }
  }

  Future<Map<String, dynamic>> createVendor(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/inventory/vendors', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create vendor'));
    }
  }

  Future<Map<String, dynamic>> updateVendor(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/inventory/vendors/$id', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update vendor'));
    }
  }

  Future<void> deleteVendor(String id) async {
    try {
      final response = await _dio.delete('/api/inventory/vendors/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete vendor'));
    }
  }

  Future<void> clearHistory(String confirmationPhrase) async {
    try {
      final response = await _dio.post('/api/maintenance/clear-history', data: {'confirm': confirmationPhrase});
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to clear history'));
    }
  }

  Future<List<dynamic>> getInventoryItems({String? salonId}) async {
    try {
      final response = await _dio.get('/api/inventory/items', queryParameters: {
        if (salonId != null) 'salonId': salonId,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch inventory items'));
    }
  }

  Future<Map<String, dynamic>> createInventoryItem(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/inventory/items', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to create inventory item'));
    }
  }

  Future<Map<String, dynamic>> updateInventoryItem(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/inventory/items/$id', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update inventory item'));
    }
  }

  Future<void> deleteInventoryItem(String id) async {
    try {
      await _dio.delete('/api/inventory/items/$id');
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete inventory item'));
    }
  }

  Future<Map<String, dynamic>> createInventoryTransaction(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/inventory/transactions', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to record transaction'));
    }
  }

  Future<List<dynamic>> getAllInventoryTransactions({String? salonId, String? startDate, String? endDate}) async {
    try {
      final response = await _dio.get('/api/inventory/transactions', queryParameters: {
        if (salonId != null) 'salonId': salonId,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch inventory transactions'));
    }
  }

  Future<List<dynamic>> getInventoryTransactions(String itemId) async {
    try {
      final response = await _dio.get('/api/inventory/transactions/$itemId');
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch transactions'));
    }
  }

  // --- Ledger API ---

  Future<dynamic> getLedger({String? clientId, String? vendorId, String? staffId, String? salonId, int? limit, int? offset, bool? includeOnline}) async {
    try {
      final response = await _dio.get('/api/ledger', queryParameters: {
        if (clientId != null) 'clientId': clientId,
        if (vendorId != null) 'vendorId': vendorId,
        if (staffId != null) 'staffId': staffId,
        if (salonId != null) 'salonId': salonId,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (includeOnline != null) 'includeOnline': includeOnline.toString(),
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch ledger'));
    }
  }

  Future<Map<String, dynamic>> createLedgerPayment(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/ledger/payment', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to record payment'));
    }
  }

  Future<Map<String, dynamic>> postReconciliation(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/ledger/reconcile', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to record reconciliation'));
    }
  }

  Future<void> updateLedgerPayment(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/ledger/payment/$id', data: data);
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update ledger entry'));
    }
  }

  Future<List<dynamic>> getClientUnpaidSales(String clientId) async {
    try {
      final response = await _dio.get('/api/ledger/unpaid-sales/$clientId');
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch unpaid sales'));
    }
  }

  Future<void> deleteLedgerPayment(String id) async {
    try {
      final response = await _dio.delete('/api/ledger/payment/$id');
      _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to delete ledger entry'));
    }
  }

  // --- Purchase API ---

  Future<Map<String, dynamic>> createPurchase(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/purchases', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to record purchase'));
    }
  }

  Future<List<dynamic>> getPurchases() async {
    try {
      final response = await _dio.get('/api/purchases');
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch purchases'));
    }
  }

  String _handleError(DioException e, String defaultMessage) {
    if (e.response != null) {
      if (e.response!.statusCode == 403) {
        final data = e.response!.data;
        if (data is Map && data.containsKey('message')) {
          return data['message'].toString();
        }
        return 'Access Denied: Your subscription may have expired or the salon is suspended.';
      }

      if (e.response!.data != null) {
        final data = e.response!.data;
        if (data is Map && data.containsKey('message')) {
          return data['message'].toString();
        } else if (data is String) {
          // If it's a string, it might be HTML or a plain text error
          if (data.contains('<!DOCTYPE html>') || data.contains('<html')) {
            if (data.contains('Space is sleeping') || data.contains('Starting')) {
               return 'Server is starting up. Please try again in 30 seconds.';
            }
            return '$defaultMessage (Server Error: ${e.response!.statusCode})';
          }
          return data.length > 120 ? '$defaultMessage (${e.response!.statusCode})' : data;
        }
      }
    }
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. The server might be waking up, please try again.';
    }
    return e.message ?? defaultMessage;
  }

  dynamic _processData(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is String) throw Exception('Unexpected server response format');
        return decoded;
      } catch (_) {
        if (data.contains('<!DOCTYPE html>') || data.contains('<html')) {
          throw Exception('Server is waking up. Please try again in a few moments.');
        }
        throw Exception('Server returned an unexpected format. Please check your connection.'); 
      }
    }
    return data;
  }

  Future<Map<String, dynamic>> getPublicSale(String invoiceId, String? verifyHash) async {
    try {
      final response = await _dio.get('/api/sales/public/$invoiceId', queryParameters: {
        if (verifyHash != null) 'verify': verifyHash,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch public invoice'));
    }
  }

  Future<Map<String, dynamic>> getZktecoConfig({String? salonId}) async {
    try {
      final response = await _dio.get('/api/zkteco/config', queryParameters: {
        if (salonId != null) 'salonId': salonId,
      });
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to fetch ZKTeco config'));
    }
  }

  Future<Map<String, dynamic>> updateZktecoConfig(Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/zkteco/config', data: data);
      return _processData(response.data);
    } on DioException catch (e) {
      throw Exception(_handleError(e, 'Failed to update ZKTeco config'));
    }
  }
}
