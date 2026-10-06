import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../db/database_helper.dart';
import '../providers/connectivity_provider.dart';
import '../providers/auth_provider.dart';
import '../models/service_model.dart';
import '../models/staff_model.dart';

final syncStatusProvider = StateProvider<bool>((ref) => false);

final syncRepositoryProvider = Provider((ref) => SyncRepository(ref));

class SyncRepository {
  final Ref _ref;
  final DatabaseHelper _db = DatabaseHelper();
  final _uuid = const Uuid();
  bool _isSyncing = false;

  SyncRepository(this._ref);

  ApiService get _api => _ref.read(apiServiceProvider);

  // --- Synchronization Logic ---

  Future<void> syncPendingChanges() async {
    if (_isSyncing) return;
    
    final isOnline = _ref.read(isOnlineProvider);
    if (!isOnline) return;

    if (kIsWeb) return; // Sync queue not used on web

    final pending = await _db.getQueue();
    if (pending.isEmpty) return;

    _isSyncing = true;

    _ref.read(syncStatusProvider.notifier).state = true;
    try {
      for (final item in pending) {
        final data = jsonDecode(item['payload']);
        final id = item['id'];
        final method = item['method'];
        final endpoint = item['endpoint'];
        final retryCount = item['retry_count'] ?? 0;

        try {
          if (method == 'POST') {
            if (endpoint == '/api/sales') {
              await _api.createSale(data);
            } else if (endpoint == '/api/staff') {
              await _api.createStaff(data);
            } else if (endpoint == '/api/appointments') {
              await _api.createAppointment(data);
            }
          } else if (method == 'PUT') {
            if (endpoint.startsWith('/api/sales/')) {
              final saleId = endpoint.split('/').last;
              await _api.updateSale(saleId, data);
            }
          }
          await _db.removeFromQueue(id);
        } catch (e) {
          await _db.updateQueueError(id, e.toString(), retryCount);
        }
      }
    } finally {
      _isSyncing = false;
      _ref.read(syncStatusProvider.notifier).state = false;
    }
  }

  // --- Wrapped Data Fetching (Offline First with Typed Models) ---

  Future<List<Service>> getServices() async {
    final isOnline = _ref.read(isOnlineProvider);
    if (isOnline) {
      try {
        final List<dynamic> servicesJson = await _api.getServices();
        final List<Service> services = servicesJson.map((s) => Service.fromJson(s)).toList();
        
        // Also fetch sellable inventory items
        try {
          final List<dynamic> inventoryJson = await _api.getInventoryItems();
          final List<Service> products = inventoryJson
            .where((i) => i['canBeSold'] == 'true' || i['canBeSold'] == true)
            .map((i) => Service(
              id: 'inv_${i['id']}',
              name: i['name'],
              price: i['sellingPrice']?.toString() ?? '0',
              costPrice: i['unitPrice']?.toString() ?? '0',
              category: 'Products',
              duration: 0,
              isPackage: false,
              stockQuantity: double.tryParse(i['stockQuantity']?.toString() ?? '0'),
            )).toList();
          services.addAll(products);
        } catch (e) {
          debugPrint('Error fetching inventory for POS: $e');
        }

        if (!kIsWeb) {
          for (var s in services) {
            await _db.insert('services', s.toDb());
          }
        }
        return services;
      } catch (_) {}
    }
    
    if (kIsWeb) return []; // No local DB on web
    final salonId = _ref.read(authProvider)?['salonId'];
    final local = await _db.queryAll('services');
    return local
      .where((s) => s['salonId'] == salonId)
      .map((s) => Service.fromJson(s))
      .toList();
  }

  Future<List<Staff>> getStaff({String? salonId}) async {
    final isOnline = _ref.read(isOnlineProvider);
    if (isOnline) {
      try {
        final List<dynamic> staffJson = await _api.getStaff(salonId: salonId);
        final staff = staffJson.map((s) => Staff.fromJson(s)).toList();
        
        if (!kIsWeb) {
          for (var s in staff) {
            await _db.insert('staff', s.toDb());
          }
        }
        return staff;
      } catch (_) {}
    }
    
    if (kIsWeb) return []; // No local DB on web
    final localSalonId = salonId ?? _ref.read(authProvider)?['salonId'];
    final local = await _db.queryAll('staff');
    return local
      .where((s) => s['salonId'] == localSalonId)
      .map((s) => Staff.fromJson(s))
      .toList();
  }

  // --- Wrapped Data Storage ---

  Future<void> createSale(Map<String, dynamic> saleData) async {
    final isOnline = _ref.read(isOnlineProvider);

    if (kIsWeb) {
      if (isOnline) {
        await _api.createSale(saleData);
      } else {
        throw Exception('Offline mode not supported on Web');
      }
      return;
    }

    final saleId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    final items = saleData['items'] as List;
    
    await _db.transaction((txn) async {
      await _db.insert('sales', {
        'id': saleId,
        'totalAmount': saleData['total'].toString(),
        'paymentMethod': saleData['paymentMethod'],
        'clientPhone': saleData['customerPhone'],
        'staffId': saleData['staffId'],
        'createdAt': now,
        'isSynced': 0,
      }, txn: txn);

      for (var item in items) {
        await _db.insert('sale_items', {
          'id': _uuid.v4(),
          'saleId': saleId,
          'serviceId': item['serviceId'],
          'price': item['price'].toString(),
          'quantity': item['quantity'],
        }, txn: txn);
      }

      await _db.addToQueue('/api/sales', 'POST', saleData, txn: txn);
    });

    if (isOnline) {
      try {
        await syncPendingChanges(); 
      } catch (e) {}
    }
  }

  Future<void> updateSale(String id, Map<String, dynamic> saleData) async {
    final isOnline = _ref.read(isOnlineProvider);

    if (kIsWeb) {
      if (isOnline) {
        await _api.updateSale(id, saleData);
      } else {
        throw Exception('Offline mode not supported on Web');
      }
      return;
    }

    final now = DateTime.now().toIso8601String();
    final items = saleData['items'] as List;

    await _db.transaction((txn) async {
      await _db.insert('sales', {
        'id': id,
        'totalAmount': saleData['total'].toString(),
        'paymentMethod': saleData['paymentMethod'],
        'clientPhone': saleData['customerPhone'],
        'staffId': saleData['staffId'],
        'createdAt': now,
        'isSynced': 0,
      }, txn: txn);

      // Delete old local sale items for this sale
      try {
        await txn.delete('sale_items', where: 'saleId = ?', whereArgs: [id]);
      } catch (_) {}

      for (var item in items) {
        await _db.insert('sale_items', {
          'id': _uuid.v4(),
          'saleId': id,
          'serviceId': item['serviceId'],
          'price': item['price'].toString(),
          'quantity': item['quantity'],
        }, txn: txn);
      }

      await _db.addToQueue('/api/sales/$id', 'PUT', saleData, txn: txn);
    });

    if (isOnline) {
      try {
        await syncPendingChanges();
      } catch (e) {}
    }
  }
}
