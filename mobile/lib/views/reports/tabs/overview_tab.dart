import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:convert';
import '../../../providers/currency_provider.dart';
import '../../../providers/expenses_provider.dart';
import '../../../providers/staff_provider.dart';
import '../../../providers/ledger_provider.dart';
import '../../../utils/format_helper.dart';
import '../widgets/report_metric_card.dart';

const _kDark = Color(0xFF1E293B);
const _kPrimary = Color(0xFF6366F1);

class OverviewTabWidget extends ConsumerWidget {
  final Map<String, dynamic> data;
  final double salesSum;
  final double commissionSum;
  final List<dynamic> sales;
  final bool isStaff;
  final String? myStaffId;
  final String? salonId;
  final DateTime startDate;
  final DateTime endDate;

  const OverviewTabWidget({
    super.key,
    required this.data,
    required this.salesSum,
    required this.commissionSum,
    required this.sales,
    required this.isStaff,
    required this.myStaffId,
    required this.salonId,
    required this.startDate,
    required this.endDate,
  });

  static bool _isEntryOnline(dynamic entry) {
    if (entry == null) return false;
    final notes = (entry['notes']?.toString() ?? '').trim();
    String pMethod = (entry['paymentMethod']?.toString() ?? '').toUpperCase();

    if (notes.startsWith('{') && notes.endsWith('}')) {
      try {
        final struct = jsonDecode(notes);
        if (struct['paymentMethod'] != null && struct['paymentMethod'].toString().isNotEmpty) {
          pMethod = struct['paymentMethod'].toString().toUpperCase();
        }
        if (struct['userNotes'] != null) {
          final u = struct['userNotes'].toString().toUpperCase();
          if (u.contains('ONLINE') || u.contains('CARD') || u.contains('UPI') || u.contains('BANK') || u.contains('DIGITAL') || u.contains('CHECK') || u.contains('CHEQUE') || u.contains('CHQ')) {
            pMethod = 'ONLINE';
          }
        }
      } catch (_) {}
    }

    final notesUpper = notes.toUpperCase();
    if (pMethod.isEmpty || pMethod == 'CASH') {
      if (notesUpper.contains('ONLINE') ||
          notesUpper.contains('CARD') ||
          notesUpper.contains('UPI') ||
          notesUpper.contains('BANK') ||
          notesUpper.contains('DIGITAL') ||
          notesUpper.contains('CHECK') ||
          notesUpper.contains('CHEQUE') ||
          notesUpper.contains('CHQ')) {
        pMethod = 'ONLINE';
      }
    }

    return ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(pMethod);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffListAsync = salonId != null
        ? ref.watch(staffForSalonProvider(salonId!))
        : ref.watch(staffProvider);
    final expensesAsync = ref.watch(expensesProvider(ExpenseFilter(start: startDate, end: endDate, salonId: salonId)));

    if (staffListAsync.isLoading || expensesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    final currency = ref.watch(currencyProvider);
    final totalBillings = double.tryParse(data['totalBillings']?.toString() ?? '0') ?? 0.0;
    final totalExpenses = double.tryParse(data['totalExpenses']?.toString() ?? '0') ?? 0.0;
    final totalInventoryCost = double.tryParse(data['totalInventoryCost']?.toString() ?? '0') ?? 0.0;
    final baseSalary = double.tryParse(data['baseSalary']?.toString() ?? '0') ?? 0.0;
    final salaryDeductions = double.tryParse(data['salaryDeductions']?.toString() ?? '0') ?? 0.0;
    final advances = double.tryParse(data['advances']?.toString() ?? '0') ?? 0.0;
    final netEarnings = double.tryParse(data['netEarnings']?.toString() ?? '0') ?? 0.0;
    final profit = double.tryParse(data['profit']?.toString() ?? '0') ?? 0.0;

    final ledgerAsync = ref.watch(ledgerProvider(LedgerParams(salonId: salonId, limit: 1000, includeOnline: true)));
    final List<dynamic> entries = ledgerAsync.value?['entries'] ?? [];

    double cashVal = 0;
    double onlineVal = 0;
    final startM = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final endM = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

    for (var sale in sales) {
      final saleId = sale['id']?.toString() ?? '';
      final List<dynamic> salePayments = sale['payments'] as List<dynamic>? ?? [];
      double cashSum = 0;
      double onlineSum = 0;
      
      if (salePayments.isNotEmpty) {
        for (var p in salePayments) {
          final pDateStr = p['date']?.toString() ?? '';
          final pDate = DateTime.tryParse(pDateStr);
          if (pDate == null) continue;
          final localPDate = pDate.toLocal();
          if (localPDate.isBefore(startM) || localPDate.isAfter(endM)) continue;

          final amt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
          final isOnline = _isEntryOnline(p);

          if (isOnline) {
            onlineSum += amt;
          } else {
            cashSum += amt;
          }
        }
      } else {
        final saleEntries = entries.where((e) => e['saleId']?.toString() == saleId && e['category'] == 'PAYMENT').toList();
        for (var se in saleEntries) {
          final amt = double.tryParse(se['amount']?.toString() ?? '0') ?? 0.0;
          final isOnline = _isEntryOnline(se);
          if (isOnline) {
            onlineSum += amt;
          } else {
            cashSum += amt;
          }
        }
      }
      
      double cashRatio = 1.0;
      double onlineRatio = 0.0;
      final totalFromEntries = cashSum + onlineSum;
      
      if (totalFromEntries > 0) {
        cashRatio = cashSum / totalFromEntries;
        onlineRatio = onlineSum / totalFromEntries;
      } else {
        final method = sale['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
        if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL'].contains(method)) {
          cashRatio = 0.0;
          onlineRatio = 1.0;
        }
      }

      double rangePaid = totalFromEntries;
      if (rangePaid <= 0) {
        final dateStr = sale['createdAt']?.toString() ?? sale['date']?.toString() ?? '';
        final saleDate = DateTime.tryParse(dateStr);
        if (saleDate != null) {
          final localSaleDate = saleDate.toLocal();
          if (!localSaleDate.isBefore(startM) && !localSaleDate.isAfter(endM)) {
            rangePaid = double.tryParse(sale['amountPaid']?.toString() ?? '0') ?? 0.0;
          }
        }
      }

      if (rangePaid <= 0) continue;

      cashVal += rangePaid * cashRatio;
      onlineVal += rangePaid * onlineRatio;
    }

    final totalPayment = cashVal + onlineVal;
    final suggestedDeductions = double.tryParse(data['suggestedAttendanceDeductions']?.toString() ?? '0') ?? 0.0;
    final suggestedList = data['suggestedDeductionsList'] as List<dynamic>? ?? [];

    if (isStaff) {
      double myServicesSales = 0;
      double myProductSales = 0;
      double myExpectedComm = 0;

      if (myStaffId != null) {
        final staffList = staffListAsync.value ?? [];
        final myStaffRec = staffList.cast<dynamic>().firstWhere(
          (s) => s['id']?.toString() == myStaffId,
          orElse: () => null,
        );
        final commissionRate = double.tryParse(myStaffRec?['commissionPercentage']?.toString() ?? myStaffRec?['commissionRate']?.toString() ?? '10') ?? 10.0;

        final staffSales = sales.where((sale) {
          if (sale['status'] != 'ACTIVE') return false;
          final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
          return items.any((item) {
            final itemStaffId = item['staffId'] ?? sale['staffId'];
            return itemStaffId?.toString() == myStaffId;
          });
        }).toList();

        for (var sale in staffSales) {
          final saleTotal = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
          if (saleTotal <= 0) continue;

          final List<dynamic> payments = sale['payments'] as List<dynamic>? ?? [];
          double rangePaid = 0.0;

          if (payments.isNotEmpty) {
            final startM = DateTime(startDate.year, startDate.month, startDate.day);
            final endM = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
            for (var p in payments) {
              final pDateStr = p['date']?.toString() ?? '';
              final pDate = DateTime.tryParse(pDateStr);
              if (pDate == null) continue;
              final localPDate = pDate.toLocal();
              if (!localPDate.isBefore(startM) && !localPDate.isAfter(endM)) {
                rangePaid += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
              }
            }
          } else {
            rangePaid = double.tryParse(sale['amountPaid']?.toString() ?? sale['total']?.toString() ?? '0') ?? 0.0;
          }

          if (rangePaid <= 0) continue;
          final ratio = (rangePaid / saleTotal).clamp(0.0, 1.0);

          final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
          for (var item in items) {
            final itemStaffId = item['staffId'] ?? sale['staffId'];
            if (itemStaffId?.toString() != myStaffId) continue;

            final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
            final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
            final discountAmt = double.tryParse(item['discountAmount']?.toString() ?? '0') ?? 0.0;
            final commAmt = double.tryParse(item['commissionAmount']?.toString() ?? '0') ?? 0.0;

            final netRevenue = ((price * qty) - discountAmt) * ratio;
            if (commAmt > 0) {
              myExpectedComm += commAmt * ratio;
            } else {
              myExpectedComm += netRevenue * (commissionRate / 100);
            }

            final isProduct = item['productId'] != null || (item['serviceId']?.toString() ?? '').startsWith('inv_');
            if (isProduct) {
              myProductSales += netRevenue;
            } else {
              myServicesSales += netRevenue;
            }
          }
        }
      }

      final displayNetSales = myStaffId != null ? (myServicesSales + myProductSales) : salesSum;
      final displayCommission = myStaffId != null ? myExpectedComm : commissionSum;

      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          Row(
            children: [
              Expanded(child: ReportMetricCard(title: 'My Net Sales', value: '$currency ${formatAmount(displayNetSales)}', icon: LucideIcons.receipt, color: Colors.indigo)),
              const SizedBox(width: 12),
              Expanded(child: ReportMetricCard(title: 'Commissions Earned', value: '$currency ${formatAmount(displayCommission)}', icon: LucideIcons.award, color: Colors.teal)),
            ],
          ),
          const SizedBox(height: 24),
          if (totalPayment > 0) ...[
            Text('My Sales Channels', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _kDark)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withValues(alpha: 0.05))),
              child: Column(
                children: [
                  ReportProgressBar(label: 'Cash Sales', value: cashVal / totalPayment, displayValue: '${(cashVal / totalPayment * 100).toStringAsFixed(0)}%', color: Colors.amber),
                  const SizedBox(height: 12),
                  ReportProgressBar(label: 'Online / Card Sales', value: onlineVal / totalPayment, displayValue: '${(onlineVal / totalPayment * 100).toStringAsFixed(0)}%', color: Colors.blueAccent),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text('Financial Summary Statement', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withValues(alpha: 0.05))),
            child: Column(
              children: [
                _buildSimpleTableRow('Base Salary', '$currency ${formatAmount(baseSalary)}'),
                _buildSimpleTableRow('Commissions Earned', '$currency ${formatAmount(commissionSum)}'),
                if (salaryDeductions > 0)
                  _buildSimpleTableRow('Deductions Applied', '- $currency ${formatAmount(salaryDeductions)}', valueColor: Colors.red),
                if (advances > 0)
                  _buildSimpleTableRow('Advances Paid', '- $currency ${formatAmount(advances)}', valueColor: Colors.orange),
                _buildSimpleTableRow('My Net Expected Earnings', '$currency ${formatAmount(netEarnings)}', isBold: true, valueColor: Colors.green),
              ],
            ),
          ),
          if (suggestedDeductions > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.alertTriangle, color: Colors.amber.shade800, size: 18),
                      const SizedBox(width: 8),
                      Text('Suggested Attendance Deductions', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900)),
                      const Spacer(),
                      Text('$currency ${formatAmount(suggestedDeductions)}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'These deductions are suggested due to late check-ins or early exits, but they are NOT automatically applied unless confirmed by the owner.',
                    style: GoogleFonts.outfit(fontSize: 11, color: Colors.amber.shade900.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: suggestedList.map<Widget>((sd) {
                      final reason = sd['reason']?.toString() ?? 'Late/Early Exit';
                      final date = sd['date']?.toString() ?? '';
                      final amount = double.tryParse(sd['amount']?.toString() ?? '0') ?? 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text('• $reason ($date)', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black54))),
                            Text('-$currency ${formatAmount(amount)}', style: GoogleFonts.outfit(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }

    final backendOnline = double.tryParse(data['onlinePayments']?.toString() ?? '0') ?? 0.0;
    final backendClient = double.tryParse(data['clientPayments']?.toString() ?? '0') ?? 0.0;
    final backendCash = (backendClient - backendOnline).clamp(0.0, double.infinity);

    final topOnlinePayments = backendOnline > 0 ? backendOnline : (onlineVal > 0 ? onlineVal : 0.0);
    final cashPayments = backendClient > 0 ? (backendClient - topOnlinePayments).clamp(0.0, double.infinity) : (cashVal > 0 ? cashVal : 0.0);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        Row(
          children: [
            Expanded(child: ReportMetricCard(title: 'Total Billings', value: '$currency ${formatAmount(totalBillings)}', icon: LucideIcons.receipt, color: Colors.indigo)),
            const SizedBox(width: 12),
            Expanded(child: ReportMetricCard(title: 'Net Profit', value: '$currency ${formatAmount(profit)}', icon: LucideIcons.award, color: profit >= 0 ? Colors.teal : Colors.red, textColor: profit >= 0 ? Colors.teal : Colors.red)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: ReportMetricCard(title: 'Total Cash Collected', value: '$currency ${formatAmount(cashPayments)}', icon: LucideIcons.trendingUp, color: Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: ReportMetricCard(title: 'Online Collected', value: '$currency ${formatAmount(topOnlinePayments)}', icon: LucideIcons.creditCard, color: Colors.blue)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: ReportMetricCard(title: 'Operating Expenses', value: '$currency ${formatAmount(totalExpenses)}', icon: LucideIcons.trendingDown, color: Colors.pink)),
            const SizedBox(width: 12),
            Expanded(child: ReportMetricCard(title: 'Product COGS', value: '$currency ${formatAmount(totalInventoryCost)}', icon: LucideIcons.shoppingBag, color: Colors.orange)),
          ],
        ),
      ],
    );
  }

  static Widget _buildSimpleTableRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Colors.black54,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: valueColor ?? _kDark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
