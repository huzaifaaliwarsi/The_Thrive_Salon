import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import '../../../providers/currency_provider.dart';
import '../../../utils/format_helper.dart';

const _kDark = Color(0xFF1E293B);

class TaxTabWidget extends ConsumerWidget {
  final String? salonId;
  final List<dynamic> salesList;
  final Map<String, dynamic> data;
  final DateTime startDate;
  final DateTime endDate;

  const TaxTabWidget({
    super.key,
    required this.salonId,
    required this.salesList,
    required this.data,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);

    final startM = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final endM = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

    double netServiceSales = 0;
    double netProductSales = 0;
    double totalDiscounts = 0;
    double fallbackTotalBillings = 0;

    for (var sale in salesList) {
      if (sale['status'] == 'VOID') continue;

      final dateStr = sale['createdAt']?.toString() ?? sale['date']?.toString() ?? '';
      final saleDate = DateTime.tryParse(dateStr);
      bool isCreatedInRange = false;
      if (saleDate != null) {
        final localSaleDate = saleDate.toLocal();
        isCreatedInRange = !localSaleDate.isBefore(startM) && !localSaleDate.isAfter(endM);
      }

      if (!isCreatedInRange) continue;

      final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
      fallbackTotalBillings += total;

      final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
      for (var item in items) {
        final isInternal = item['isInternal'] == true || item['isInternal']?.toString() == 'true';
        if (isInternal) continue;

        final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
        final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
        final discountAmount = double.tryParse(item['discountAmount']?.toString() ?? '0') ?? 0.0;
        
        totalDiscounts += discountAmount;
        final netPrice = (price * qty) - discountAmount;

        final isProduct = item['productId'] != null || (item['serviceId']?.toString() ?? '').startsWith('inv_');
        if (isProduct) {
          netProductSales += netPrice;
        } else {
          netServiceSales += netPrice;
        }
      }
    }

    final totalRevenue = netServiceSales + netProductSales;

    double cashPayments = 0;
    double onlinePayments = 0;
    double fallbackCollectedTax = 0;

    for (var sale in salesList) {
      if (sale['status'] == 'VOID') continue;

      final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
      final taxAmount = double.tryParse(sale['taxAmount']?.toString() ?? '0') ?? 0.0;
      final List<dynamic> payments = sale['payments'] as List<dynamic>? ?? [];

      for (var p in payments) {
        final pDateStr = p['date']?.toString() ?? '';
        final pDate = DateTime.tryParse(pDateStr);
        if (pDate == null) continue;
        final localPDate = pDate.toLocal();
        if (localPDate.isBefore(startM) || localPDate.isAfter(endM)) continue;

        final amt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
        String pMethod = p['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
        final n = p['notes']?.toString() ?? '';
        try {
          final trimmed = n.trim();
          if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            final struct = jsonDecode(trimmed);
            final pm = struct['paymentMethod']?.toString().toUpperCase();
            if (pm != null && pm.isNotEmpty) pMethod = pm;
          }
        } catch (_) {}

        if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(pMethod)) {
          onlinePayments += amt;
        } else {
          cashPayments += amt;
        }

        if (total > 0) {
          fallbackCollectedTax += taxAmount * (amt / total);
        }
      }
    }

    final backendTotalBillings = double.tryParse(data['totalBillings']?.toString() ?? '0') ?? 0.0;
    final backendCollectedTax = double.tryParse(data['collectedTax']?.toString() ?? '0') ?? 0.0;
    final collectedTax = backendCollectedTax > 0 ? backendCollectedTax : fallbackCollectedTax;
    final totalBillings = data.containsKey('totalBillings') ? backendTotalBillings : (fallbackTotalBillings > 0 ? fallbackTotalBillings : totalRevenue);
    final totalExpenses = double.tryParse(data['totalExpenses']?.toString() ?? '0') ?? 0.0;
    final productCogs = double.tryParse(data['productCogs']?.toString() ?? data['totalInventoryCost']?.toString() ?? '0') ?? 0.0;
    final totalPurchaseVolume = double.tryParse(data['totalPurchaseVolume']?.toString() ?? '0') ?? 0.0;
    final totalCommissionsVal = double.tryParse(data['commission']?.toString() ?? '0') ?? 0.0;
    final netProfit = double.tryParse(data['profit']?.toString() ?? '0') ?? (totalRevenue - totalExpenses - productCogs - totalCommissionsVal);

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
              Text('Profit & Tax Compliance Report', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
              Text('Financial profit & loss summary and VAT collected for selected date range.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  children: [
                    _buildSimpleTableRow('Net Service Sales', '$currency ${formatAmount(netServiceSales)}'),
                    _buildSimpleTableRow('Net Product Sales', '$currency ${formatAmount(netProductSales)}'),
                    if (totalDiscounts > 0) _buildSimpleTableRow('Total Discount Given', '- $currency ${formatAmount(totalDiscounts)}', valueColor: Colors.orange.shade700),
                    _buildSimpleTableRow('Total Billings (with Tax)', '$currency ${formatAmount(totalBillings)}', isBold: true),
                    _buildSimpleTableRow('Cash Collected (Inflow)', '$currency ${formatAmount(cashPayments)}', isBold: true, valueColor: Colors.teal.shade700),
                    _buildSimpleTableRow('Online Collected (Inflow)', '$currency ${formatAmount(onlinePayments)}', isBold: true, valueColor: Colors.blue.shade700),
                    _buildSimpleTableRow('VAT / Tax Collected', '- $currency ${formatAmount(collectedTax)}', valueColor: Colors.red.shade700),
                    _buildSimpleTableRow('Product & Consumables COGS', '- $currency ${formatAmount(productCogs)}', valueColor: Colors.deepOrange.shade700),
                    if (totalCommissionsVal > 0) _buildSimpleTableRow('Staff Commissions', '- $currency ${formatAmount(totalCommissionsVal)}', valueColor: Colors.purple.shade700),
                    _buildSimpleTableRow('Operating Expenses', '- $currency ${formatAmount(totalExpenses)}', valueColor: Colors.red.shade700),
                    _buildSimpleTableRow('Stock Purchases (Inventory Inflow)', '$currency ${formatAmount(totalPurchaseVolume)}', valueColor: Colors.blueGrey.shade700),
                    _buildSimpleTableRow(
                      'Net Operating Profit',
                      '$currency ${formatAmount(netProfit)}',
                      isBold: true,
                      valueColor: netProfit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
