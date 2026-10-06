import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../db/database_helper.dart';

// Import providers to clear on logout
import '../view_models/dashboard_view_model.dart';
import '../view_models/pos_view_model.dart';
import 'clients_provider.dart';
import 'inventory_provider.dart';
import 'expenses_provider.dart';
import 'ledger_provider.dart';
import 'reports_provider.dart';
import 'salons_provider.dart';
import 'services_provider.dart';
import 'staff_provider.dart';
import 'appointments_provider.dart';
import 'attendance_provider.dart';
import 'logo_provider.dart';
import 'navigation_provider.dart';

final authProvider = StateNotifierProvider<AuthNotifier, Map<String, dynamic>?>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<Map<String, dynamic>?> {
  final _storage = const FlutterSecureStorage();
  final Ref _ref;

  AuthNotifier(this._ref) : super(null) {
    _init();
  }

  Future<void> _init() async {
    // On app startup, verify if there's a valid cached session
    final token = await _storage.read(key: 'token');
    final userJson = await _storage.read(key: 'user');
    
    if (token != null && userJson != null) {
      try {
        state = jsonDecode(userJson);
      } catch (e) {
        // If data is corrupted, clear everything
        await logout();
      }
    }
  }

  void setUser(Map<String, dynamic> user) {
    state = user;
    _storage.write(key: 'user', value: jsonEncode(user));
  }

  Future<void> logout() async {
    // If the user is already logged out, do not run logout flow again.
    // This prevents background 401 errors from the old session from cancelling
    // the new login request.
    if (state == null) return;

    // CRITICAL: Clear state FIRST to prevent race condition where old data is visible
    state = null;
    
    // Invalidate all business providers to clear memory cache
    try {
      _ref.invalidate(dashboardViewModelProvider);
      _ref.invalidate(posProvider);
      _ref.invalidate(clientsProvider);
      _ref.invalidate(vendorsProvider);
      _ref.invalidate(inventoryProvider);
      _ref.invalidate(expensesProvider);
      _ref.invalidate(ledgerProvider);
      _ref.invalidate(reportsProvider);
      _ref.invalidate(salonsProvider);
      _ref.invalidate(servicesProvider);
      _ref.invalidate(staffProvider);
      _ref.invalidate(appointmentsProvider);
      _ref.invalidate(attendanceProvider);
      _ref.invalidate(logoProvider);
      _ref.invalidate(navigationIndexProvider);
    } catch (e) {
      debugPrint('Error invalidating providers: $e');
    }

    // Cancel all pending API requests
    try {
      _ref.read(apiServiceProvider).cancelAllRequests();
    } catch (_) {
      // API service might not be initialized, ignore
    }

    // Clear local database to prevent cross-tenant data leaks
    try {
      await DatabaseHelper().clearAllData();
    } catch (e) {
      debugPrint('Error clearing database: $e');
    }
    
    // Then clear storage
    await _storage.deleteAll();
  }

  // Force refresh user from server to ensure no stale data
  Future<void> refreshUser(Map<String, dynamic> freshUserData) async {
    // Atomic state update
    state = freshUserData;
    
    // Write to storage without clearing everything (prevents token loss)
    await _storage.write(key: 'user', value: jsonEncode(freshUserData));
  }
}
