import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/inventory_provider.dart';
import '../../../providers/reports_provider.dart';
import '../../../utils/format_helper.dart';
import '../widgets/report_metric_card.dart';

const _kDark = Color(0xFF1E293B);
const _kPrimary = Color(0xFF6366F1);

class InventoryTabWidget extends ConsumerWidget {
  final String? salonId;
  final DateTime startDate;
  final DateTime endDate;
  final String? selectedStaffId;
  final String? selectedItemFilterId;
  final List<dynamic> salesList;

  const InventoryTabWidget({
    super.key,
    required this.salonId,
    required this.startDate,
    required this.endDate,
    required this.selectedStaffId,
    required this.selectedItemFilterId,
    required this.salesList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String formatQty(double val) => val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);

    final reportParams = ReportParams(
      start: startDate,
      end: endDate,
      groupBy: 'day',
      staffId: selectedStaffId,
      salonId: salonId,
    );
    final invTxAsync = salonId != null
        ? ref.watch(allInventoryTransactionsForSalonProvider(reportParams))
        : ref.watch(allInventoryTransactionsProvider(reportParams));
    final productsAsync = salonId != null
        ? ref.watch(inventoryForSalonProvider(salonId))
        : ref.watch(inventoryProvider);

    if (invTxAsync.isLoading || productsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    final rawTxs = invTxAsync.value ?? [];
    final products = productsAsync.value ?? [];
    final currency = ref.watch(currencyProvider);

    final txs = rawTxs.where((tx) {
      final dateStr = tx['createdAt']?.toString() ?? tx['date']?.toString() ?? '';
      final txDate = DateTime.tryParse(dateStr);
      if (txDate == null) return false;
      final localTxDate = txDate.toLocal();
      final isWithinDates = (localTxDate.isAfter(startDate) || localTxDate.isAtSameMomentAs(startDate)) &&
                            (localTxDate.isBefore(endDate) || localTxDate.isAtSameMomentAs(endDate));
      if (!isWithinDates) return false;
      if (selectedItemFilterId != null) {
        if (!selectedItemFilterId!.startsWith('product_')) return false;
        final cleanProductId = selectedItemFilterId!.replaceFirst('product_', '');
        if (tx['itemId'] != cleanProductId) return false;
      }
      return true;
    }).toList();

    final prodMap = {for (var p in products) p['id']?.toString(): p['name']?.toString() ?? 'Product'};

    final List<Map<String, dynamic>> logRows = [];
    for (var tx in txs) {
      final type = tx['type']?.toString().toUpperCase() ?? 'OUT';
      final notes = tx['notes']?.toString() ?? '';
      final notesLower = notes.toLowerCase();
      final isAdjustmentNotes = notesLower.contains('damage') ||
                                notesLower.contains('loss') ||
                                notesLower.contains('salon use') ||
                                notesLower.contains('manual') ||
                                notesLower.contains('adjustment') ||
                                notesLower.contains('correction');
      final isOutAndNotSale = type == 'OUT' && !notesLower.contains('sale #');
      final isAdjustment = isAdjustmentNotes || isOutAndNotSale;
      if (isAdjustment) {
        final dateStr = tx['createdAt']?.toString() ?? tx['date']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now();
        final formattedDate = DateFormat('dd MMM').format(date);
        final prodId = tx['itemId']?.toString();
        final prodName = prodMap[prodId] ?? 'Product';
        final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;

        logRows.add({
          'date': formattedDate,
          'product': prodName,
          'type': type == 'IN' ? 'Plus' : 'Minus',
          'qty': qty,
          'reason': notes.isEmpty ? 'Manual Adjustment' : notes,
        });
      }
    }

    final List<Map<String, dynamic>> movementRows = [];
    double totalStockValue = 0;

    for (var p in products) {
      final prodId = p['id']?.toString();
      final prodName = p['name']?.toString() ?? 'Product';
      final closing = double.tryParse(p['stockQuantity']?.toString() ?? '0') ?? 0.0;
      final price = double.tryParse(p['sellingPrice']?.toString() ?? '0') ?? 0.0;
      final purchasePrice = double.tryParse(p['unitPrice']?.toString() ?? '') ?? (price * 0.7);

      double sold = 0.0;
      for (var sale in salesList) {
        if (sale['status'] == 'VOID') continue;
        final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
        for (var item in items) {
          if (item['productId']?.toString() == prodId) {
            sold += double.tryParse(item['quantity']?.toString() ?? '0') ?? 0.0;
          }
        }
      }

      double purchased = 0.0;
      double netChange = 0.0;

      final prodTxs = txs.where((tx) => tx['itemId']?.toString() == prodId).toList();
      for (var tx in prodTxs) {
        final type = tx['type']?.toString().toUpperCase() ?? 'OUT';
        final notes = tx['notes']?.toString().toLowerCase() ?? '';
        final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;

        if (type == 'IN') {
          netChange += qty;
          if (notes.contains('purchase') || notes.contains('supplier') || notes.contains('initial')) {
            purchased += qty;
          }
        } else {
          netChange -= qty;
        }
      }

      final opening = closing - netChange;
      final adjustment = netChange - purchased + sold;
      final stockValue = closing * purchasePrice;
      totalStockValue += stockValue;

      movementRows.add({
        'name': prodName,
        'opening': opening,
        'purchased': purchased,
        'sold': sold,
        'adjustment': adjustment,
        'closing': closing,
        'value': stockValue,
      });
    }

    final isWide = MediaQuery.of(context).size.width > 900;

    final movementCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inventory Movement', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          Text('Products sold, purchased, and adjusted.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.grey.shade100),
              child: DataTable(
                columnSpacing: 20,
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                columns: [
                  DataColumn(label: Text('PRODUCT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                  DataColumn(label: Text('OPENING', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                  DataColumn(label: Text('PURCHASED', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                  DataColumn(label: Text('SOLD', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                  DataColumn(label: Text('ADJUSTMENT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                  DataColumn(label: Text('CLOSING STOCK', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                  DataColumn(label: Text('STOCK VALUE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                ],
                rows: [
                  ...List.generate(movementRows.length, (idx) {
                    final row = movementRows[idx];
                    final cellStyle = GoogleFonts.outfit(fontSize: 13, color: _kDark);

                    return DataRow(
                      cells: [
                        DataCell(Text(row['name'], style: cellStyle.copyWith(fontWeight: FontWeight.w600))),
                        DataCell(Text(formatQty(row['opening']), style: cellStyle)),
                        DataCell(Text(formatQty(row['purchased']), style: cellStyle.copyWith(color: Colors.green.shade700))),
                        DataCell(Text(formatQty(row['sold']), style: cellStyle.copyWith(color: Colors.orange.shade700))),
                        DataCell(Text('${row['adjustment'] >= 0 ? '+' : ''}${formatQty(row['adjustment'])}', style: cellStyle.copyWith(color: row['adjustment'] != 0 ? Colors.indigo.shade700 : Colors.black54))),
                        DataCell(Text(formatQty(row['closing']), style: cellStyle.copyWith(fontWeight: FontWeight.bold))),
                        DataCell(Text('$currency ${formatAmount(row['value'])}', style: cellStyle.copyWith(fontWeight: FontWeight.bold))),
                      ],
                    );
                  }),
                  DataRow(
                    cells: [
                      DataCell(Text('Total Stock Value', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kDark))),
                      const DataCell(SizedBox()),
                      const DataCell(SizedBox()),
                      const DataCell(SizedBox()),
                      const DataCell(SizedBox()),
                      const DataCell(SizedBox()),
                      DataCell(Text('$currency ${formatAmount(totalStockValue)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kPrimary))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final logCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stock Adjustment Log', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          Text('For damage, missing, salon use, or correction.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.grey.shade100),
              child: DataTable(
                columnSpacing: 20,
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                columns: [
                  DataColumn(label: Text('DATE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                  DataColumn(label: Text('PRODUCT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                  DataColumn(label: Text('TYPE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                  DataColumn(label: Text('QTY', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                  DataColumn(label: Text('REASON', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                ],
                rows: logRows.isEmpty
                    ? [
                        DataRow(
                          cells: [
                            DataCell(Text('No logs', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black38))),
                            const DataCell(SizedBox()),
                            const DataCell(SizedBox()),
                            const DataCell(SizedBox()),
                            const DataCell(SizedBox()),
                          ],
                        )
                      ]
                    : List.generate(logRows.length, (idx) {
                        final log = logRows[idx];
                        final cellStyle = GoogleFonts.outfit(fontSize: 13, color: _kDark);

                        return DataRow(
                          cells: [
                            DataCell(Text(log['date'], style: cellStyle)),
                            DataCell(Text(log['product'], style: cellStyle.copyWith(fontWeight: FontWeight.w600))),
                            DataCell(Text(log['type'], style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: log['type'] == 'Plus' ? Colors.green : Colors.red))),
                            DataCell(Text('${formatQty(log['qty'])} units', style: cellStyle)),
                            DataCell(Text(log['reason'], style: cellStyle.copyWith(color: Colors.black45))),
                          ],
                        );
                      }),
              ),
            ),
          ),
        ],
      ),
    );

    double totalUtilizedQty = 0.0;
    double totalUtilizedCost = 0.0;
    double totalAvailableQty = 0.0;
    double totalAvailableValue = totalStockValue;

    for (var row in movementRows) {
      totalUtilizedQty += (row['sold'] as double);
      final p = products.firstWhere((prod) => prod['name']?.toString() == row['name'], orElse: () => null);
      final price = double.tryParse(p?['sellingPrice']?.toString() ?? '0') ?? 0.0;
      final purchasePrice = double.tryParse(p?['unitPrice']?.toString() ?? '') ?? (price * 0.7);
      totalUtilizedCost += (row['sold'] as double) * purchasePrice;
      totalAvailableQty += (row['closing'] as double);
    }

    final summaryCards = Column(
      children: [
        Row(
          children: [
            Expanded(child: ReportMetricCard(title: 'Stock Utilized', value: '${formatQty(totalUtilizedQty)} units', icon: LucideIcons.packageCheck, color: Colors.orange)),
            const SizedBox(width: 12),
            Expanded(child: ReportMetricCard(title: 'Utilized Value (COGS)', value: '$currency ${formatAmount(totalUtilizedCost)}', icon: LucideIcons.trendingDown, color: Colors.pink)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: ReportMetricCard(title: 'Stock Available', value: '${formatQty(totalAvailableQty)} units', icon: LucideIcons.package2, color: Colors.teal)),
            const SizedBox(width: 12),
            Expanded(child: ReportMetricCard(title: 'Available Value', value: '$currency ${formatAmount(totalAvailableValue)}', icon: LucideIcons.database, color: Colors.indigo)),
          ],
        ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          summaryCards,
          const SizedBox(height: 20),
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: movementCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 3, child: logCard),
                  ],
                )
              : Column(
                  children: [
                    movementCard,
                    const SizedBox(height: 16),
                    logCard,
                  ],
                ),
        ],
      ),
    );
  }
}

class StockAdjustmentTabWidget extends ConsumerWidget {
  final String? salonId;
  final DateTime startDate;
  final DateTime endDate;
  final String? selectedStaffId;
  final String? selectedItemFilterId;

  const StockAdjustmentTabWidget({
    super.key,
    required this.salonId,
    required this.startDate,
    required this.endDate,
    required this.selectedStaffId,
    required this.selectedItemFilterId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportParams = ReportParams(
      start: startDate,
      end: endDate,
      groupBy: 'day',
      staffId: selectedStaffId,
      salonId: salonId,
    );
    final invTxAsync = salonId != null
        ? ref.watch(allInventoryTransactionsForSalonProvider(reportParams))
        : ref.watch(allInventoryTransactionsProvider(reportParams));
    final productsAsync = salonId != null
        ? ref.watch(inventoryForSalonProvider(salonId))
        : ref.watch(inventoryProvider);

    if (invTxAsync.isLoading || productsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    final rawTxs = invTxAsync.value ?? [];
    final products = productsAsync.value ?? [];

    final adjustments = rawTxs.where((t) {
      final dateStr = t['createdAt']?.toString() ?? t['date']?.toString() ?? '';
      final date = DateTime.tryParse(dateStr);
      if (date == null) return false;
      final localDate = date.toLocal();
      final isWithinDates = (localDate.isAfter(startDate) || localDate.isAtSameMomentAs(startDate)) &&
                            (localDate.isBefore(endDate) || localDate.isAtSameMomentAs(endDate));
      if (!isWithinDates) return false;

      if (selectedItemFilterId != null) {
        if (!selectedItemFilterId!.startsWith('product_')) return false;
        final cleanProductId = selectedItemFilterId!.replaceFirst('product_', '');
        if (t['itemId'] != cleanProductId) return false;
      }

      final notes = (t['notes']?.toString() ?? '').toLowerCase();
      final isAdjustmentNotes = notes.contains('damage') ||
                                notes.contains('loss') ||
                                notes.contains('salon use') ||
                                notes.contains('manual') ||
                                notes.contains('adjustment') ||
                                notes.contains('correction');
      final isOutAndNotSale = t['type'] == 'OUT' && !notes.contains('sale #');
      return isAdjustmentNotes || isOutAndNotSale;
    }).toList();

    if (adjustments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.folderOpen, size: 40, color: Colors.black12),
            const SizedBox(height: 12),
            Text('No stock adjustments found', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 13)),
          ],
        ),
      );
    }

    final prodMap = {for (var p in products) p['id']?.toString(): p['name']?.toString() ?? 'Product'};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: DataTable(
            columns: [
              DataColumn(label: Text('DATE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
              DataColumn(label: Text('PRODUCT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
              DataColumn(label: Text('QTY', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
              DataColumn(label: Text('REASON / NOTES', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
            ],
            rows: adjustments.map((t) {
              final dateStr = t['createdAt']?.toString() ?? t['date']?.toString() ?? '';
              final date = DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now();
              final formattedDate = DateFormat('MMM dd, HH:mm').format(date);
              
              final prodName = prodMap[t['itemId']?.toString()] ?? 'Product';
              final qty = t['quantity'] ?? '0';
              final notes = t['notes'] ?? 'Manual stock adjustment';

              return DataRow(
                cells: [
                  DataCell(Text(formattedDate, style: GoogleFonts.outfit(fontSize: 12))),
                  DataCell(Text(prodName, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataCell(Text('$qty units', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red))),
                  DataCell(Text(notes, style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54))),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
