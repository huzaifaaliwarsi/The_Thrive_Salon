import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:convert';
import '../../../providers/currency_provider.dart';
import '../../../providers/expenses_provider.dart';
import '../../../providers/inventory_provider.dart';
import '../../../providers/ledger_provider.dart';
import '../../../utils/format_helper.dart';

const _kDark = Color(0xFF1E293B);
const _kPrimary = Color(0xFF6366F1);

class ExpensesTabWidget extends ConsumerStatefulWidget {
  final String? salonId;
  final DateTime startDate;
  final DateTime endDate;
  final List<dynamic> salesList;

  const ExpensesTabWidget({
    super.key,
    required this.salonId,
    required this.startDate,
    required this.endDate,
    required this.salesList,
  });

  @override
  ConsumerState<ExpensesTabWidget> createState() => _ExpensesTabWidgetState();
}

class _ExpensesTabWidgetState extends ConsumerState<ExpensesTabWidget> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final filter = ExpenseFilter(start: widget.startDate, end: widget.endDate, salonId: widget.salonId);
    final expensesAsync = ref.watch(expensesProvider(filter));

    final ledgerAsync = ref.watch(ledgerProvider(LedgerParams(salonId: widget.salonId, limit: 1000, includeOnline: true)));
    final purchasesAsync = ref.watch(purchasesProvider);

    if (expensesAsync.isLoading || ledgerAsync.isLoading || purchasesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    final rawExpenses = expensesAsync.value ?? [];
    final List<dynamic> expenses = List.from(rawExpenses);

    // Pull internally used products from salesList and add them as virtual expenses
    for (var sale in widget.salesList) {
      if (sale['status'] == 'VOID') continue;
      final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
      final dateStr = sale['createdAt']?.toString() ?? '';

      for (var item in items) {
        final isInternal = item['isInternal'] == true || item['isInternal']?.toString() == 'true';
        if (isInternal) {
          final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
          final totalCost = price * qty;
          final name = item['serviceName'] ?? item['productName'] ?? item['name'] ?? 'Salon Product';

          expenses.add({
            'id': 'internal_${item['id'] ?? item['productId']}',
            'name': 'Internal Use: $name (Qty: $qty)',
            'amount': totalCost,
            'category': 'Salon Use',
            'date': dateStr,
          });
        }
      }
    }

    final ledgerEntries = ledgerAsync.value?['entries'] ?? [];

    for (var entry in ledgerEntries) {
      if (entry['type'] == 'DEBIT' && (entry['category'] == 'PURCHASE' || (entry['category'] == 'PAYMENT' && entry['vendorId'] != null))) {
        final dateStr = entry['date']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr);
        if (date != null) {
          final localDate = date.toLocal();
          final dateMidnight = DateTime(localDate.year, localDate.month, localDate.day);
          final startMidnight = DateTime(widget.startDate.year, widget.startDate.month, widget.startDate.day);
          final endMidnight = DateTime(widget.endDate.year, widget.endDate.month, widget.endDate.day);
          if (dateMidnight.isBefore(startMidnight) || dateMidnight.isAfter(endMidnight)) {
            continue;
          }
        }
        
        final amt = double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
        final notes = entry['notes']?.toString() ?? '';
        final vendorName = entry['vendor']?['name']?.toString() ?? 'Supplier';
        final isPurchase = entry['category'] == 'PURCHASE';

        String pMethod = 'Cash';
        String userNote = notes;
        Map<String, dynamic>? struct;
        try {
          if (notes.startsWith('{') && notes.endsWith('}')) {
            struct = jsonDecode(notes);
          }
        } catch (_) {}
        if (struct != null) {
          final pm = struct['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
          pMethod = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(pm) ? 'Online' : 'Cash';
          if (struct['userNotes'] != null && struct['userNotes'].toString().isNotEmpty) {
            userNote = struct['userNotes'].toString();
          }
        } else {
          final upperNotes = notes.toUpperCase();
          if (upperNotes.contains('ONLINE') || upperNotes.contains('CARD') || upperNotes.contains('BANK') || upperNotes.contains('UPI') || upperNotes.contains('CHECK') || upperNotes.contains('CHEQUE') || upperNotes.contains('CHQ')) {
            pMethod = 'Online';
          }
        }

        expenses.add({
          'id': 'ledger_${entry['id']}',
          'name': isPurchase ? (userNote.isNotEmpty ? userNote : 'Stock Purchase') : 'Payment to $vendorName',
          'amount': amt,
          'category': isPurchase ? 'Inventory Stock-In' : 'Vendor Payment',
          'date': dateStr,
          'paymentFrom': pMethod,
        });
      }
    }

    if (expenses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.folderOpen, size: 40, color: Colors.black12),
            const SizedBox(height: 12),
            Text('No expenses found', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 13)),
          ],
        ),
      );
    }

    double totalPaidExpenses = 0.0;
    for (var e in expenses) {
      final amt = double.tryParse(e['amount']?.toString() ?? '0') ?? 0.0;
      totalPaidExpenses += amt;
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Expenses Report', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
              Text('Only paid expenses are deducted from drawer balance.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
              const SizedBox(height: 20),
              Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.grey.shade100),
                    child: DataTable(
                      columnSpacing: 24,
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                      headingRowHeight: 40,
                      dataRowMinHeight: 44,
                      dataRowMaxHeight: 52,
                      columns: [
                        DataColumn(label: Text('DATE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                        DataColumn(label: Text('EXPENSE NAME', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                        DataColumn(label: Text('CATEGORY', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                        DataColumn(label: Text('PAYMENT FROM', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                        DataColumn(label: Text('AMOUNT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                        DataColumn(label: Text('NOTES', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                      ],
                      rows: [
                        ...List.generate(expenses.length, (idx) {
                          final e = expenses[idx];
                          final name = e['name'] ?? 'General Expense';
                          final category = e['category'] ?? 'General';
                          final amt = double.tryParse(e['amount']?.toString() ?? '0') ?? 0.0;
                          
                          final dateStr = e['date']?.toString() ?? '';
                          final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                          final formattedDate = DateFormat('dd MMM').format(date);

                          final matchingLedger = ledgerEntries.firstWhere(
                            (l) => l['expenseId'] == e['id'],
                            orElse: () => null,
                          );

                          String paymentFrom = 'Cash';
                          String rawNotes = '';
                          if (category == 'Salon Use') {
                            paymentFrom = 'Stock';
                          } else if (category == 'Inventory Stock-In' || category == 'Vendor Payment') {
                            paymentFrom = e['paymentFrom'] ?? 'Cash';
                          } else if (matchingLedger != null) {
                            rawNotes = matchingLedger['notes'] ?? '';
                            final notesStr = matchingLedger['notes']?.toString() ?? '';
                            Map<String, dynamic>? struct;
                            try {
                              if (notesStr.startsWith('{') && notesStr.endsWith('}')) {
                                struct = jsonDecode(notesStr);
                              }
                            } catch (_) {}

                            if (struct != null) {
                              final pm = struct['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
                              paymentFrom = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(pm) ? 'Online' : 'Cash';
                            } else {
                              final upper = notesStr.toUpperCase();
                              paymentFrom = (upper.contains('ONLINE') || upper.contains('CARD') || upper.contains('BANK') || upper.contains('UPI') || upper.contains('CHECK') || upper.contains('CHEQUE') || upper.contains('CHQ')) ? 'Online' : 'Cash';
                            }
                          }

                          final finalNotes = getExpenseNotes(name, rawNotes);
                          final cellStyle = GoogleFonts.outfit(fontSize: 13, color: _kDark);

                          return DataRow(
                            cells: [
                              DataCell(Text(formattedDate, style: cellStyle)),
                              DataCell(Text(name, style: cellStyle.copyWith(fontWeight: FontWeight.w600))),
                              DataCell(Text(category, style: cellStyle.copyWith(color: Colors.black54))),
                              DataCell(Text(paymentFrom, style: cellStyle)),
                              DataCell(Text('$currency ${formatAmount(amt)}', style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: Colors.red.shade700))),
                              DataCell(Text(finalNotes, style: cellStyle.copyWith(color: Colors.black45))),
                            ],
                          );
                        }),
                        DataRow(
                          cells: [
                            DataCell(Text('Total Paid Expenses', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kDark))),
                            const DataCell(SizedBox()),
                            const DataCell(SizedBox()),
                            const DataCell(SizedBox()),
                            DataCell(Text('$currency ${formatAmount(totalPaidExpenses)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700))),
                            const DataCell(SizedBox()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String getExpenseNotes(String name, String fallback) {
    final lName = name.toLowerCase();
    if (lName.contains('electricity') || lName.contains('bill')) return 'Monthly bill';
    if (lName.contains('cleaning') || lName.contains('material')) return 'Salon cleaning';
    if (lName.contains('instagram') || lName.contains('ads') || lName.contains('marketing')) return 'Campaign payment';
    if (lName.contains('salary') || lName.contains('staff')) return 'Paid amount only';
    return fallback.length > 30 ? name : (fallback.isEmpty ? 'Paid expense' : fallback);
  }
}
