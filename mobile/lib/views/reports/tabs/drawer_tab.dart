import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:convert';
import 'dart:math' as math;
import '../../../providers/currency_provider.dart';
import '../../../providers/ledger_provider.dart';
import '../../../models/payment_account.dart';
import '../../../providers/payment_accounts_provider.dart';
import '../../../utils/format_helper.dart';

const _kDark = Color(0xFF1E293B);
const _kPrimary = Color(0xFF6366F1);

class DrawerTabWidget extends ConsumerWidget {
  final List<dynamic> salesList;
  final DateTime startDate;
  final DateTime endDate;
  final String? salonId;
  final Map<String, dynamic>? backendDrawerBalances;

  const DrawerTabWidget({
    super.key,
    required this.salesList,
    required this.startDate,
    required this.endDate,
    this.salonId,
    this.backendDrawerBalances,
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
    final currency = ref.watch(currencyProvider);
    final ledgerAsync = ref.watch(ledgerProvider(LedgerParams(salonId: salonId, limit: 1000, includeOnline: true)));

    return ledgerAsync.when(
      data: (ledgerData) {
        final List<dynamic> allLedgerEntries = ledgerData['entries'] ?? [];
        final entries = allLedgerEntries.where((entry) {
          final dateStr = entry['date']?.toString() ?? entry['createdAt']?.toString() ?? '';
          final entryDate = DateTime.tryParse(dateStr);
          if (entryDate == null) return false;
          final localEntryDate = entryDate.toLocal();
          return (localEntryDate.isAfter(startDate) || localEntryDate.isAtSameMomentAs(startDate)) &&
                 (localEntryDate.isBefore(endDate) || localEntryDate.isAtSameMomentAs(endDate));
        }).toList();

        double serviceCash = 0;
        double serviceOnline = 0;
        double serviceReceivable = 0;

        double productCash = 0;
        double productOnline = 0;
        double productReceivable = 0;

        double discountCash = 0;
        double discountOnline = 0;
        double discountReceivable = 0;

        double vatCash = 0;
        double vatOnline = 0;
        double vatReceivable = 0;

        final startM = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
        final endM = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

        for (var sale in salesList) {
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
          
          double cashRatioForSale = 1.0;
          double onlineRatioForSale = 0.0;
          final totalFromEntries = cashSum + onlineSum;
          final method = sale['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
          final isSaleOnlineMethod = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(method);

          if (totalFromEntries > 0) {
            cashRatioForSale = (cashSum / totalFromEntries).clamp(0.0, 1.0);
            onlineRatioForSale = (onlineSum / totalFromEntries).clamp(0.0, 1.0);
          } else if (isSaleOnlineMethod) {
            cashRatioForSale = 0.0;
            onlineRatioForSale = 1.0;
          } else {
            cashRatioForSale = 1.0;
            onlineRatioForSale = 0.0;
          }

          final discount = double.tryParse(sale['discount']?.toString() ?? '0') ?? 0.0;
          final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;

          final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
          
          double servSub = 0.0;
          double prodSub = 0.0;
          for (var item in items) {
            final isInternal = item['isInternal'] == true || item['isInternal']?.toString() == 'true';
            if (isInternal) continue;
            final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
            final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
            final isProduct = item['productId'] != null || (item['serviceId']?.toString() ?? '').startsWith('inv_');
            if (isProduct) {
              prodSub += price * qty;
            } else {
              servSub += price * qty;
            }
          }

          double totalSub = servSub + prodSub;
          double servRatio = 1.0;
          if (totalSub > 0) {
            servRatio = servSub / totalSub;
          }

          final taxAmount = double.tryParse(sale['taxAmount']?.toString() ?? '0') ?? 0.0;

          double grossServ = servSub;
          double grossProd = prodSub;

          double discServ = discount * servRatio;
          double discProd = discount * (1.0 - servRatio);

          double netServ = grossServ - discServ;
          double netProd = grossProd - discProd;
          double totalNetSale = netServ + netProd;

          double rangePaid = totalFromEntries;
          if (rangePaid <= 0) {
            final dateStr = sale['createdAt']?.toString() ?? sale['date']?.toString() ?? '';
            final saleDate = DateTime.tryParse(dateStr);
            if (saleDate != null) {
              final localSaleDate = saleDate.toLocal();
              final dateM = DateTime(localSaleDate.year, localSaleDate.month, localSaleDate.day);
              final startM = DateTime(startDate.year, startDate.month, startDate.day);
              final endM = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
              if (!dateM.isBefore(startM) && !dateM.isAfter(endM)) {
                rangePaid = double.tryParse(sale['amountPaid']?.toString() ?? '0') ?? 0.0;
              }
            }
          }

          if (rangePaid <= 0) continue;

          final amountPaid = rangePaid;
          final totalBillInclusive = total > 0 ? total : (totalNetSale + taxAmount);
          final payRatio = totalBillInclusive > 0 ? (amountPaid / totalBillInclusive).clamp(0.0, 1.0) : 1.0;

          double paidGrossServ = grossServ * payRatio;
          double paidGrossProd = grossProd * payRatio;
          double paidDiscount = discount * payRatio;
          double paidTax = taxAmount * payRatio;

          double totalPaidUpToRangeEnd = 0.0;
          final List<dynamic> payments = sale['payments'] as List<dynamic>? ?? [];
          if (payments.isNotEmpty) {
            final endM = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
            for (var p in payments) {
              final pDateStr = p['date']?.toString() ?? '';
              final pDate = DateTime.tryParse(pDateStr);
              if (pDate == null) continue;
              final localPDate = pDate.toLocal();
              if (!localPDate.isAfter(endM)) {
                totalPaidUpToRangeEnd += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
              }
            }
          } else {
            totalPaidUpToRangeEnd = double.tryParse(sale['amountPaid']?.toString() ?? '0') ?? 0.0;
          }

          final unpaidAmount = math.max(0.0, totalBillInclusive - totalPaidUpToRangeEnd);
          final unpaidRatio = totalBillInclusive > 0 ? (unpaidAmount / totalBillInclusive).clamp(0.0, 1.0) : 0.0;

          double unpaidGrossServ = grossServ * unpaidRatio;
          double unpaidGrossProd = grossProd * unpaidRatio;
          double unpaidDiscount = discount * unpaidRatio;
          double unpaidTax = taxAmount * unpaidRatio;

          serviceOnline += paidGrossServ * onlineRatioForSale;
          productOnline += paidGrossProd * onlineRatioForSale;
          discountOnline += paidDiscount * onlineRatioForSale;
          vatOnline += paidTax * onlineRatioForSale;

          serviceCash += paidGrossServ * cashRatioForSale;
          productCash += paidGrossProd * cashRatioForSale;
          discountCash += paidDiscount * cashRatioForSale;
          vatCash += paidTax * cashRatioForSale;

          serviceReceivable += unpaidGrossServ;
          productReceivable += unpaidGrossProd;
          discountReceivable += unpaidDiscount;
          vatReceivable += unpaidTax;
        }

        double expenseCash = 0;
        double expenseOnline = 0;
        
        for (var entry in entries) {
          final isExpense = entry['category'] == 'EXPENSE';
          final isAnonPurchase = entry['category'] == 'PURCHASE' && entry['vendorId'] == null && entry['type'] == 'DEBIT';
          if (isExpense || isAnonPurchase) {
            final amt = double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
            if (amt <= 0) continue;
            final isOnline = _isEntryOnline(entry);
            if (isOnline) {
              expenseOnline += amt;
            } else {
              expenseCash += amt;
            }
          }
        }

        double supplierCash = 0;
        double supplierOnline = 0;

        for (var entry in entries) {
          final isVendorPayment = (entry['category'] == 'PAYMENT' || entry['category'] == 'PURCHASE') && entry['vendorId'] != null && entry['type'] == 'DEBIT';
          if (isVendorPayment) {
            final amt = double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
            if (amt <= 0) continue;
            final isOnline = _isEntryOnline(entry);
            if (isOnline) {
              supplierOnline += amt;
            } else {
              supplierCash += amt;
            }
          }
        }

        double salaryCash = 0;
        double salaryOnline = 0;

        for (var entry in entries) {
          final cat = entry['category']?.toString().toUpperCase();
          final isSalaryOrAdvance = (cat == 'STAFF_ADVANCE' || cat == 'SALARY' || cat == 'STAFF_PAYMENT' || cat == 'PAYROLL') && entry['type'] == 'DEBIT';
          if (isSalaryOrAdvance) {
            final amt = double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
            if (amt <= 0) continue;
            final isOnline = _isEntryOnline(entry);
            if (isOnline) {
              salaryOnline += amt;
            } else {
              salaryCash += amt;
            }
          }
        }

        double collectedReceivablesCash = 0;
        double collectedReceivablesOnline = 0;

        for (var entry in entries) {
          if (entry['category'] == 'PAYMENT' && entry['clientId'] != null && entry['vendorId'] == null && entry['type'] == 'DEBIT') {
            final notes = entry['notes']?.toString().trim() ?? '';
            Map<String, dynamic>? struct;
            try {
              if (notes.startsWith('{') && notes.endsWith('}')) {
                struct = jsonDecode(notes);
              }
            } catch (_) {}

            final userNotes = struct?['userNotes']?.toString() ?? notes;
            if (userNotes.contains('Amount Paid at Sale') && entry['saleId'] != null) {
              continue;
            }

            final amt = double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
            if (amt <= 0) continue;
            final isOnline = _isEntryOnline(entry);
            
            if (isOnline) {
              collectedReceivablesOnline += amt;
            } else {
              collectedReceivablesCash += amt;
            }
          }
        }

        double voidReversalCash = 0;
        double voidReversalOnline = 0;

        for (var entry in entries) {
          if (entry['category'] == 'VOID_REVERSAL' && entry['type'] == 'CREDIT') {
            final amt = double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
            if (amt <= 0) continue;
            final isOnline = _isEntryOnline(entry);

            if (isOnline) {
              voidReversalOnline += amt;
            } else {
              voidReversalCash += amt;
            }
          }
        }

        double reconSurplusCash = 0;
        double reconShortageCash = 0;

        for (var entry in entries) {
          if (entry['category'] == 'RECONCILIATION_ADJUSTMENT') {
            final amt = double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
            if (amt <= 0) continue;
            if (entry['type'] == 'CREDIT') {
              reconSurplusCash += amt;
            } else if (entry['type'] == 'DEBIT') {
              reconShortageCash += amt;
            }
          }
        }

        final double grossCash = serviceCash + productCash;
        final double grossOnline = serviceOnline + productOnline;
        final double grossRec = serviceReceivable + productReceivable;
        
        final double netCash = grossCash - discountCash;
        final double netOnline = grossOnline - discountOnline;
        final double netRec = grossRec - discountReceivable;

        final double balCash = netCash + vatCash + collectedReceivablesCash + reconSurplusCash - expenseCash - supplierCash - salaryCash - voidReversalCash - reconShortageCash;
        final double balOnline = netOnline + vatOnline + collectedReceivablesOnline - expenseOnline - supplierOnline - salaryOnline - voidReversalOnline;
        final double balRec = netRec + vatReceivable - (collectedReceivablesCash + collectedReceivablesOnline);

        final isWide = MediaQuery.of(context).size.width > 900;

        final mainReportCard = Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Daily Cash and Online Report', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
                        Text('This is the main report for salon owner. It shows what came in, what went out, and what is left.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _kDark, borderRadius: BorderRadius.circular(8)),
                    child: Text('Main', style: GoogleFonts.outfit(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.grey.shade100),
                  child: DataTable(
                    columnSpacing: isWide ? 40 : 20,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 44,
                    columns: [
                      DataColumn(label: Text('Transaction Detail', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 13))),
                      DataColumn(label: Text('Cash Amount', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 13))),
                      DataColumn(label: Text('Online Amount', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 13))),
                      DataColumn(label: Text('Receivable Amount', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 13))),
                      DataColumn(label: Text('Total Flow', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 13))),
                    ],
                    rows: [
                      _buildDataRow('Service Sales (Gross)', serviceCash, serviceOnline, serviceReceivable, currency),
                      _buildDataRow('Product Sales (Gross)', productCash, productOnline, productReceivable, currency),
                      _buildDataRow('Discount Given', -discountCash, -discountOnline, -discountReceivable, currency, isNegative: true),
                      _buildDataRow('Net Sales', netCash, netOnline, netRec, currency, isBold: true),
                      _buildDataRow('VAT/Tax Collected', vatCash, vatOnline, vatReceivable, currency),
                      _buildDataRow('Operating Expenses', -expenseCash, -expenseOnline, 0, currency, isNegative: true),
                      _buildDataRow('Supplier Payments', -supplierCash, -supplierOnline, 0, currency, isNegative: true),
                      if (salaryCash > 0 || salaryOnline > 0)
                        _buildDataRow('Staff Salaries & Advances', -salaryCash, -salaryOnline, 0, currency, isNegative: true),
                      _buildDataRow('Old Receivables Collected', collectedReceivablesCash, collectedReceivablesOnline, -(collectedReceivablesCash + collectedReceivablesOnline), currency),
                      if (voidReversalCash > 0 || voidReversalOnline > 0)
                        _buildDataRow('Refunds & Void Reversals', -voidReversalCash, -voidReversalOnline, 0, currency, isNegative: true),
                      if (reconSurplusCash > 0)
                        _buildDataRow('Reconciliation Surplus', reconSurplusCash, 0, 0, currency),
                      if (reconShortageCash > 0)
                        _buildDataRow('Reconciliation Shortage', -reconShortageCash, 0, 0, currency, isNegative: true),
                      _buildBalanceRow('Net Remaining Balance', balCash, balOnline, balRec, currency),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        final balanceCards = Row(
          children: [
            Expanded(
              child: _buildDrawerBalanceCard(
                'Physical Cash Drawer',
                balCash,
                currency,
                const Color(0xFF10B981),
                LucideIcons.wallet,
                'Inflow: $currency ${formatAmount(netCash + vatCash + collectedReceivablesCash + reconSurplusCash)} | Outflow: $currency ${formatAmount(expenseCash + supplierCash + salaryCash + voidReversalCash + reconShortageCash)}',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDrawerBalanceCard(
                'Online Account Balance',
                balOnline,
                currency,
                _kPrimary,
                LucideIcons.creditCard,
                'Inflow: $currency ${formatAmount(netOnline + vatOnline + collectedReceivablesOnline)} | Outflow: $currency ${formatAmount(expenseOnline + supplierOnline + salaryOnline + voidReversalOnline)}',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDrawerBalanceCard(
                'Pending Receivables',
                balRec,
                currency,
                const Color(0xFFF59E0B),
                LucideIcons.clock,
                'Total uncollected balance across customer accounts',
              ),
            ),
          ],
        );

        final activeAccounts = ref.watch(activePaymentAccountsProvider);
        final Map<String, dynamic> onlineBreakdownMap =
            (backendDrawerBalances?['onlineBreakdown'] as Map<String, dynamic>?) ?? {};

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            if (isWide) balanceCards else Column(
              children: [
                _buildDrawerBalanceCard(
                  'Physical Cash Drawer',
                  balCash,
                  currency,
                  const Color(0xFF10B981),
                  LucideIcons.wallet,
                  'Inflow: $currency ${formatAmount(netCash + vatCash + collectedReceivablesCash + reconSurplusCash)} | Outflow: $currency ${formatAmount(expenseCash + supplierCash + salaryCash + voidReversalCash + reconShortageCash)}',
                ),
                const SizedBox(height: 12),
                _buildDrawerBalanceCard(
                  'Online Account Balance',
                  balOnline,
                  currency,
                  _kPrimary,
                  LucideIcons.creditCard,
                  'Inflow: $currency ${formatAmount(netOnline + vatOnline + collectedReceivablesOnline)} | Outflow: $currency ${formatAmount(expenseOnline + supplierOnline + salaryOnline + voidReversalOnline)}',
                ),
                const SizedBox(height: 12),
                _buildDrawerBalanceCard(
                  'Pending Receivables',
                  balRec,
                  currency,
                  const Color(0xFFF59E0B),
                  LucideIcons.clock,
                  'Total uncollected balance across customer accounts',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildOnlineAccountsSection(
              context,
              currency,
              activeAccounts,
              onlineBreakdownMap,
              balOnline,
              isWide,
            ),
            const SizedBox(height: 20),
            mainReportCard,
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error loading Galla Drawer: $err')),
    );
  }

  static Widget _buildOnlineAccountsSection(
    BuildContext context,
    String currency,
    List<PaymentAccount> accounts,
    Map<String, dynamic> backendBreakdown,
    double totalOnlineBalance,
    bool isWide,
  ) {
    final Map<String, double> mergedBalances = {};
    for (final acc in accounts) {
      double bal = 0.0;
      if (backendBreakdown.containsKey(acc.accountName)) {
        bal = (backendBreakdown[acc.accountName] as num?)?.toDouble() ?? 0.0;
      } else if (backendBreakdown.containsKey(acc.id)) {
        bal = (backendBreakdown[acc.id] as num?)?.toDouble() ?? 0.0;
      }
      mergedBalances[acc.id] = bal;
    }

    final List<Map<String, dynamic>> displayItems = [];
    for (final acc in accounts) {
      displayItems.add({
        'name': acc.accountName,
        'type': acc.type,
        'subtitle': '${acc.accountTitle ?? ''} ${acc.accountNumber ?? ''}'.trim(),
        'balance': mergedBalances[acc.id] ?? 0.0,
      });
    }

    for (final entry in backendBreakdown.entries) {
      final name = entry.key;
      final exists = displayItems.any((item) => item['name'] == name);
      if (!exists) {
        displayItems.add({
          'name': name,
          'type': 'ONLINE',
          'subtitle': 'Historical Channel',
          'balance': (entry.value as num?)?.toDouble() ?? 0.0,
        });
      }
    }

    if (displayItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(LucideIcons.landmark, color: _kPrimary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No Online Accounts Configured', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark)),
                  Text('Add Meezan, JazzCash, or bank accounts under Salon Settings to track individual balances.', style: GoogleFonts.outfit(fontSize: 11.5, color: Colors.black45)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final int crossAxisCount = isWide ? math.min(displayItems.length, 4) : 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.landmark, size: 18, color: _kPrimary),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Online Accounts Breakdown',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: _kDark),
                      ),
                      Text(
                        'Live balance distributed across active bank accounts & wallets',
                        style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '${displayItems.length} Accounts',
                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              if (crossAxisCount == 1) {
                return Column(
                  children: displayItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildAccountCardItem(item, currency, totalOnlineBalance),
                    );
                  }).toList(),
                );
              }
              final cardWidth = (constraints.maxWidth - (crossAxisCount - 1) * 12) / crossAxisCount;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: displayItems.map((item) {
                  return SizedBox(
                    width: cardWidth,
                    child: _buildAccountCardItem(item, currency, totalOnlineBalance),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  static Widget _buildAccountCardItem(
    Map<String, dynamic> item,
    String currency,
    double totalOnlineBalance,
  ) {
    final name = item['name']?.toString() ?? 'Account';
    final type = item['type']?.toString() ?? 'BANK';
    final subtitle = item['subtitle']?.toString() ?? '';
    final balance = (item['balance'] as num?)?.toDouble() ?? 0.0;
    final isWallet = type.toUpperCase().contains('WALLET') || name.toLowerCase().contains('jazz') || name.toLowerCase().contains('easy');
    final icon = isWallet ? LucideIcons.smartphone : LucideIcons.landmark;
    final accent = isWallet ? const Color(0xFFF97316) : _kPrimary;
    final share = totalOnlineBalance > 0 && balance > 0 ? (balance / totalOnlineBalance) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: _kDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.black12),
                ),
                child: Text(
                  type,
                  style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.outfit(fontSize: 10.5, color: Colors.black45),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$currency ${formatAmount(balance)}',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: balance < 0 ? Colors.redAccent : _kDark,
                ),
              ),
              if (share > 0)
                Text(
                  '${share.toStringAsFixed(0)}% of total',
                  style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w600, color: _kPrimary),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static DataRow _buildDataRow(String label, double cash, double online, double rec, String currency, {bool isBold = false, bool isNegative = false}) {
    final total = cash + online + rec;
    final textStyle = GoogleFonts.outfit(
      fontSize: 12,
      fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
      color: isNegative ? Colors.red.shade700 : _kDark,
    );
    return DataRow(cells: [
      DataCell(Text(label, style: textStyle)),
      DataCell(Text(cash == 0 ? '-' : (isNegative && cash > 0 ? '- $currency ${formatAmount(cash)}' : '$currency ${formatAmount(cash)}'), style: textStyle)),
      DataCell(Text(online == 0 ? '-' : (isNegative && online > 0 ? '- $currency ${formatAmount(online)}' : '$currency ${formatAmount(online)}'), style: textStyle)),
      DataCell(Text(rec == 0 ? '-' : (isNegative && rec > 0 ? '- $currency ${formatAmount(rec)}' : '$currency ${formatAmount(rec)}'), style: textStyle)),
      DataCell(Text(total == 0 ? '-' : (isNegative && total > 0 ? '- $currency ${formatAmount(total)}' : '$currency ${formatAmount(total)}'), style: textStyle.copyWith(fontWeight: FontWeight.bold))),
    ]);
  }

  static DataRow _buildBalanceRow(String label, double cash, double online, double rec, String currency) {
    final total = cash + online + rec;
    final textStyle = GoogleFonts.outfit(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: _kPrimary,
    );
    return DataRow(
      color: WidgetStateProperty.all(const Color(0xFFEEF2FF)),
      cells: [
        DataCell(Text(label, style: textStyle)),
        DataCell(Text('$currency ${formatAmount(cash)}', style: textStyle.copyWith(color: const Color(0xFF10B981)))),
        DataCell(Text('$currency ${formatAmount(online)}', style: textStyle.copyWith(color: _kPrimary))),
        DataCell(Text('$currency ${formatAmount(rec)}', style: textStyle.copyWith(color: const Color(0xFFF59E0B)))),
        DataCell(Text('$currency ${formatAmount(total)}', style: textStyle.copyWith(color: _kDark))),
      ],
    );
  }

  static Widget _buildDrawerBalanceCard(String title, double amount, String currency, Color color, IconData icon, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: _kDark)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$currency ${formatAmount(amount)}', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.outfit(fontSize: 10.5, color: Colors.black45)),
        ],
      ),
    );
  }
}
