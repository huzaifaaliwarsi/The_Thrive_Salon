import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // Add this for kIsWeb

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on Web');
    }
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Helper to check if we should skip db operations
  bool get _skipDb => kIsWeb;

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'salon_offline.db');
    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE sync_queue ADD COLUMN retry_count INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE sync_queue ADD COLUMN last_error TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE staff ADD COLUMN user TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE staff ADD COLUMN salaryType TEXT');
      await db.execute('ALTER TABLE staff ADD COLUMN salaryValue TEXT');
      await db.execute('ALTER TABLE staff ADD COLUMN commissionPercentage TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE staff ADD COLUMN joiningDate TEXT');
    }
    if (oldVersion < 6) {
      // Match Staff.toDb so cached staff retain their PIN and shift settings.
      final columns = (await db.rawQuery('PRAGMA table_info(staff)'))
          .map((column) => column['name']).toSet();
      const additions = {
        'biometricPin': 'TEXT', 'balance': 'REAL', 'createdAt': 'TEXT',
        'inTimeLimit': 'TEXT', 'outTimeLimit': 'TEXT', 'lateTimeLimit': 'TEXT',
        'earlyExitTimeLimit': 'TEXT', 'lateDeductionRate': 'TEXT',
        'earlyExitDeductionRate': 'TEXT', 'allowedLeaves': 'INTEGER',
      };
      for (final column in additions.entries) {
        if (!columns.contains(column.key)) {
          await db.execute('ALTER TABLE staff ADD COLUMN ${column.key} ${column.value}');
        }
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS services (
        id TEXT PRIMARY KEY,
        name TEXT,
        price TEXT,
        category TEXT,
        duration INTEGER,
        salonId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff (
        id TEXT PRIMARY KEY,
        name TEXT,
        role TEXT,
        phone TEXT,
        salonId TEXT,
        userId TEXT,
        user TEXT,
        salaryType TEXT,
        salaryValue TEXT,
        commissionPercentage TEXT,
        joiningDate TEXT,
        biometricPin TEXT,
        balance REAL,
        createdAt TEXT,
        inTimeLimit TEXT,
        outTimeLimit TEXT,
        lateTimeLimit TEXT,
        earlyExitTimeLimit TEXT,
        lateDeductionRate TEXT,
        earlyExitDeductionRate TEXT,
        allowedLeaves INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id TEXT PRIMARY KEY,
        totalAmount TEXT,
        paymentMethod TEXT,
        clientName TEXT,
        clientPhone TEXT,
        staffId TEXT,
        salonId TEXT,
        createdAt TEXT,
        isSynced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT PRIMARY KEY,
        saleId TEXT,
        serviceId TEXT,
        serviceName TEXT,
        price TEXT,
        quantity INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint TEXT,
        method TEXT,
        payload TEXT,
        timestamp TEXT,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT
      )
    ''');
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    if (_skipDb) return null as T;
    final db = await database;
    return await db.transaction(action);
  }

  Future<void> insert(String table, Map<String, dynamic> data, {Transaction? txn}) async {
    if (_skipDb) return;
    final executor = txn ?? await database;
    await executor.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> queryAll(String table) async {
    if (_skipDb) return [];
    final db = await database;
    return await db.query(table);
  }

  Future<void> delete(String table, String id) async {
    if (_skipDb) return;
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearTable(String table) async {
    if (_skipDb) return;
    final db = await database;
    await db.delete(table);
  }

  Future<void> clearAllData() async {
    if (_skipDb) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('services');
      await txn.delete('staff');
      await txn.delete('sales');
      await txn.delete('sale_items');
      await txn.delete('sync_queue');
    });
  }

  Future<void> addToQueue(String endpoint, String method, Map<String, dynamic> payload, {Transaction? txn}) async {
    if (_skipDb) return;
    final executor = txn ?? await database;
    await executor.insert('sync_queue', {
      'endpoint': endpoint,
      'method': method,
      'payload': jsonEncode(payload),
      'timestamp': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getQueue() async {
    if (_skipDb) return [];
    final db = await database;
    return await db.query('sync_queue', orderBy: 'timestamp ASC', where: 'retry_count < 5');
  }

  Future<void> removeFromQueue(int id) async {
    if (_skipDb) return;
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateQueueError(int id, String error, int currentRetries) async {
    if (_skipDb) return;
    final db = await database;
    await db.update('sync_queue', {
      'last_error': error,
      'retry_count': currentRetries + 1,
    }, where: 'id = ?', whereArgs: [id]);
  }
}
