import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../utils/web_download_helper.dart' as web_helper;
import '../../../utils/format_helper.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/reports_provider.dart';
import '../../../providers/clients_provider.dart';
import '../../../providers/staff_provider.dart';
import '../../../providers/inventory_provider.dart';
import '../../../providers/expenses_provider.dart';
import '../../../providers/attendance_provider.dart';
import '../../../providers/ledger_provider.dart';
import '../../../providers/auth_provider.dart';

class ReportCsvExporter {
  static Future<void> exportCsv({
    required BuildContext context,
    required WidgetRef ref,
    required String activeTab,
    required String? salonId,
    required DateTime startDate,
    required DateTime endDate,
    required List<dynamic> salesList,
    required double cashSalesTotal,
    required double onlineSalesTotal,
    required double creditSalesTotal,
    String? selectedItemFilterId,
  }) async {
    final currency = ref.read(currencyProvider);
    final reportParams = ReportParams(
      start: startDate,
      end: endDate,
      salonId: salonId,
    );

    String csvData = '';
    String filename = '${activeTab.toLowerCase().replaceAll(' ', '_')}_report.csv';

    try {
      switch (activeTab) {
        case 'Overview':
          final reportsAsync = ref.read(reportsProvider(reportParams));
          final m = reportsAsync.value ?? {};
          final totalBillings = double.tryParse(m['totalBillings']?.toString() ?? '0') ?? 0.0;
          final totalExpenses = double.tryParse(m['totalExpenses']?.toString() ?? '0') ?? 0.0;
          final profit = double.tryParse(m['profit']?.toString() ?? '0') ?? 0.0;
          final totalTax = double.tryParse(m['totalTax']?.toString() ?? '0') ?? 0.0;

          csvData = 'Metric,Value\n'
              'Total Billings,$totalBillings\n'
              'Cash Sales,$cashSalesTotal\n'
              'Online Sales,$onlineSalesTotal\n'
              'Credit Sales,$creditSalesTotal\n'
              'Total Operating Expenses,$totalExpenses\n'
              'VAT / Tax Collected,$totalTax\n'
              'Net Profit,$profit\n';
          break;

        case 'Galla / Drawer':
          final reportsAsync = ref.read(reportsProvider(reportParams));
          final m = reportsAsync.value ?? {};
          final ledgerIn = double.tryParse(m['ledgerIn']?.toString() ?? '0') ?? 0.0;
          final ledgerOut = double.tryParse(m['ledgerOut']?.toString() ?? '0') ?? 0.0;
          final globalReceivables = double.tryParse(m['globalReceivables']?.toString() ?? '0') ?? 0.0;
          final globalPayables = double.tryParse(m['globalPayables']?.toString() ?? '0') ?? 0.0;
          final netCash = cashSalesTotal + ledgerIn - ledgerOut;

          csvData = 'Metric,Value\n'
              'Cash Sales,$currency ${formatAmount(cashSalesTotal)}\n'
              'Online Sales,$currency ${formatAmount(onlineSalesTotal)}\n'
              'Credit Sales,$currency ${formatAmount(creditSalesTotal)}\n'
              'Ledger Cash In (Inflow),$currency ${formatAmount(ledgerIn)}\n'
              'Ledger Cash Out (Outflow / Void Reversals),- $currency ${formatAmount(ledgerOut)}\n'
              'Net Cash Drawer Balance,$currency ${formatAmount(netCash)}\n'
              'Global Receivables,$currency ${formatAmount(globalReceivables)}\n'
              'Global Payables,$currency ${formatAmount(globalPayables)}\n';
          break;

        case 'Sales':
          csvData = 'Date,Client,Phone,Staff,Payment Method,Subtotal,Discount,Tax,Total,Status\n';
          for (var s in salesList) {
            final date = DateTime.tryParse(s['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now();
            final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(date);
            final client = s['customerName'] ?? 'Walk-in Customer';
            final phone = s['customerPhone'] ?? '';
            final staff = s['staff']?['name'] ?? 'Staff';
            final payMethod = s['paymentMethod'] ?? 'CASH';
            final subtotal = s['subtotal']?.toString() ?? '0';
            final discount = s['discount']?.toString() ?? '0';
            final tax = s['taxAmount']?.toString() ?? '0';
            final total = s['total']?.toString() ?? '0';
            final status = s['status'] ?? 'ACTIVE';

            csvData += '"$dateStr","$client","$phone","$staff","$payMethod",$subtotal,$discount,$tax,$total,"$status"\n';
          }
          break;

        case 'Receivables':
          final clientsAsync = salonId != null
              ? ref.read(clientsForSalonProvider(salonId))
              : ref.read(clientsProvider);
          final clients = clientsAsync.value ?? [];
          final receivables = clients.where((c) {
            final bal = double.tryParse(c['balance']?.toString() ?? '0') ?? 0.0;
            return bal > 0;
          }).toList();

          csvData = 'Customer,Phone,Last Visit,Receivable Balance\n';
          for (var c in receivables) {
            final name = c['name'] ?? 'Unknown';
            final phone = c['phone'] ?? '';
            final lastVisitStr = c['lastVisit']?.toString() ?? '';
            final date = DateTime.tryParse(lastVisitStr);
            final formattedDate = date != null ? DateFormat('yyyy-MM-dd').format(date) : 'N/A';
            final bal = c['balance']?.toString() ?? '0';

            csvData += '"$name","$phone","$formattedDate",$bal\n';
          }
          break;

        case 'Expenses':
          final filter = ExpenseFilter(start: startDate, end: endDate, salonId: salonId);
          final expensesAsync = ref.read(expensesProvider(filter));
          final rawExpenses = expensesAsync.value ?? [];
          final expenses = List.from(rawExpenses);

          final purchasesAsync = ref.read(purchasesProvider);
          final rawPurchases = purchasesAsync.value ?? [];
          for (var p in rawPurchases) {
            final dateStr = p['date']?.toString() ?? p['createdAt']?.toString() ?? '';
            final date = DateTime.tryParse(dateStr);
            if (date != null) {
              final localDate = date.toLocal();
              final dateMidnight = DateTime(localDate.year, localDate.month, localDate.day);
              final startMidnight = DateTime(startDate.year, startDate.month, startDate.day);
              final endMidnight = DateTime(endDate.year, endDate.month, endDate.day);
              if (dateMidnight.isBefore(startMidnight) || dateMidnight.isAfter(endMidnight)) {
                continue;
              }
            }
            final total = double.tryParse(p['total']?.toString() ?? '0') ?? 0.0;
            final notes = p['notes']?.toString() ?? '';
            final vendorName = p['vendor']?['name']?.toString() ?? 'One-time Supplier';
            
            expenses.add({
              'name': notes.isNotEmpty ? notes : 'Stock-In: Purchase from $vendorName',
              'amount': total,
              'category': 'Inventory Stock-In',
              'date': dateStr,
            });
          }

          csvData = 'Date,Category,Description,Amount\n';
          for (var e in expenses) {
            final dateStr = e['date']?.toString() ?? '';
            final date = DateTime.tryParse(dateStr) ?? DateTime.now();
            final formattedDate = DateFormat('yyyy-MM-dd').format(date);
            final category = e['category'] ?? 'General';
            final desc = e['description'] ?? e['notes'] ?? e['name'] ?? '';
            final amount = e['amount']?.toString() ?? '0';

            csvData += '"$formattedDate","$category","$desc",$amount\n';
          }
          break;

        case 'Staff':
          final staffAsync = salonId != null
              ? ref.read(staffForSalonProvider(salonId))
              : ref.read(staffProvider);
          final staffList = staffAsync.value ?? [];

          csvData = 'Staff Member,Role,Salary Type,Sales Volume,Commission,Commission %\n';
          for (var staff in staffList) {
            final staffId = staff['id'];
            final name = staff['name'] ?? 'Staff';
            final role = staff['role'] ?? 'Stylist';
            final salType = staff['salaryType'] ?? 'MONTHLY';
            
            double volume = 0;
            double comm = 0;
            for (var s in salesList) {
              if (s['staffId'] == staffId) {
                final total = double.tryParse(s['total']?.toString() ?? '0') ?? 0.0;
                volume += total;
                final rate = double.tryParse(s['commissionRate']?.toString() ?? '0') ?? 0.0;
                if (rate >= 0 && rate <= 100) {
                  comm += total * (rate / 100);
                }
              }
            }
            final commPerc = staff['commissionPercentage'] ?? '0';
            csvData += '"$name","$role","$salType",$volume,$comm,$commPerc\n';
          }
          break;

        case 'Inventory':
          final invTxAsync = salonId != null
              ? ref.read(allInventoryTransactionsForSalonProvider(reportParams))
              : ref.read(allInventoryTransactionsProvider(reportParams));
          final productsAsync = salonId != null
              ? ref.read(inventoryForSalonProvider(salonId))
              : ref.read(inventoryProvider);
          final rawTxs = invTxAsync.value ?? [];
          final products = productsAsync.value ?? [];

          final txs = rawTxs.where((tx) {
            final dateStr = tx['createdAt']?.toString() ?? tx['date']?.toString() ?? '';
            final txDate = DateTime.tryParse(dateStr);
            if (txDate == null) return false;
            final localTxDate = txDate.toLocal();
            final isWithinDates = (localTxDate.isAfter(startDate) || localTxDate.isAtSameMomentAs(startDate)) &&
                                  (localTxDate.isBefore(endDate) || localTxDate.isAtSameMomentAs(endDate));
            if (!isWithinDates) return false;
            if (selectedItemFilterId != null) {
              if (!selectedItemFilterId.startsWith('product_')) return false;
              final cleanProductId = selectedItemFilterId.replaceFirst('product_', '');
              if (tx['itemId'] != cleanProductId) return false;
            }
            return true;
          }).toList();

          final prodMap = {for (var p in products) p['id']?.toString(): p['name']?.toString() ?? 'Product'};

          csvData = 'Date,Product,Transaction Type,Quantity,Notes\n';
          for (var t in txs) {
            final dateStr = t['createdAt']?.toString() ?? t['date']?.toString() ?? '';
            final date = DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now();
            final formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(date);
            final prodName = prodMap[t['itemId']?.toString()] ?? 'Product';
            final type = t['type'] ?? 'OUT';
            final qty = t['quantity'] ?? '0';
            final notes = t['notes'] ?? '';

            csvData += '"$formattedDate","$prodName","$type",$qty,"$notes"\n';
          }
          break;

        case 'Profit':
        case 'Tax & Compliance':
          final reportsAsync = ref.read(reportsProvider(reportParams));
          final m = reportsAsync.value ?? {};
          final totalBillings = double.tryParse(m['totalBillings']?.toString() ?? '0') ?? 0.0;
          final totalExpenses = double.tryParse(m['totalExpenses']?.toString() ?? '0') ?? 0.0;
          final productCogs = double.tryParse(m['productCogs']?.toString() ?? m['totalInventoryCost']?.toString() ?? '0') ?? 0.0;
          final totalTax = double.tryParse(m['totalTax']?.toString() ?? '0') ?? 0.0;
          final profit = double.tryParse(m['profit']?.toString() ?? '0') ?? 0.0;

          csvData = 'Line Item,Amount\n'
              'Total Billings (with Tax),$totalBillings\n'
              'Tax Collected,-$totalTax\n'
              'Product & Consumables COGS,-$productCogs\n'
              'Operating Expenses,-$totalExpenses\n'
              'Net Profit,$profit\n';
          break;

        default:
          csvData = 'Timestamp,Report\n"${DateTime.now()}","$activeTab"\n';
          break;
      }

      if (kIsWeb) {
        web_helper.downloadCsv(csvData, filename);
      } else {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$filename');
        await file.writeAsString(csvData);
        await Share.shareXFiles([XFile(file.path)], text: 'Salon Report - $activeTab');
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported $filename successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export CSV: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
