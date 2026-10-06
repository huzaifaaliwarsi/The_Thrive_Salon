import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../providers/reports_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/staff_provider.dart';
import '../providers/services_provider.dart';
import '../providers/clients_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/expenses_provider.dart';
import '../providers/attendance_provider.dart';

import 'reports/tabs/overview_tab.dart';
import 'reports/tabs/drawer_tab.dart';
import 'reports/tabs/sales_tab.dart';
import 'reports/tabs/receivables_tab.dart';
import 'reports/tabs/expenses_tab.dart';
import 'reports/tabs/inventory_tab.dart';
import 'reports/tabs/tax_tab.dart';
import 'reports/tabs/staff_tab.dart';
import 'reports/widgets/report_csv_exporter.dart';

const _kPrimary  = Color(0xFF6A11CB);
const _kDark     = Color(0xFF1B1B3A);
const _kBg       = Color(0xFFF4F6FB);

class ReportsView extends ConsumerStatefulWidget {
  final String? salonId;
  final String? salonName;
  const ReportsView({super.key, this.salonId, this.salonName});

  @override
  ConsumerState<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends ConsumerState<ReportsView> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).subtract(const Duration(days: 30));
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59, 999);
  String? _selectedStaffId;
  String? _selectedItemFilterId;
  String _activeTab = 'Overview';

  // Caching variables for heavy computations
  Map<String, dynamic>? _cachedData;
  DateTime? _cachedStartDate;
  DateTime? _cachedEndDate;
  String? _cachedStaffId;
  String? _cachedItemFilterId;

  List<dynamic> _cachedFilteredSales = [];
  double _cachedAccrualSalesTotal = 0;
  double _cachedCashSalesTotal = 0;
  double _cachedOnlineSalesTotal = 0;
  double _cachedCreditSalesTotal = 0;
  double _cachedTotalCommissions = 0;

  void _computeTotals(Map<String, dynamic> data, String? effectiveStaffId) {
    if (_cachedData == data &&
        _cachedStartDate == _startDate &&
        _cachedEndDate == _endDate &&
        _cachedStaffId == effectiveStaffId &&
        _cachedItemFilterId == _selectedItemFilterId) {
      return; // Already computed
    }

    _cachedData = data;
    _cachedStartDate = _startDate;
    _cachedEndDate = _endDate;
    _cachedStaffId = effectiveStaffId;
    _cachedItemFilterId = _selectedItemFilterId;

    final List<dynamic> recentSales = data['recentSales'] ?? [];

    _cachedFilteredSales = recentSales.where((sale) {
      if (sale['status'] != 'ACTIVE') return false;
      
      final dateStr = sale['createdAt']?.toString() ?? '';
      final saleDate = DateTime.tryParse(dateStr);
      bool isCreatedInRange = false;
      if (saleDate != null) {
        final localSaleDate = saleDate.toLocal();
        isCreatedInRange = (localSaleDate.isAfter(_startDate) || localSaleDate.isAtSameMomentAs(_startDate)) &&
                           (localSaleDate.isBefore(_endDate) || localSaleDate.isAtSameMomentAs(_endDate));
      }

      bool hasPaymentInRange = false;
      final List<dynamic> salePayments = sale['payments'] ?? [];
      for (var p in salePayments) {
        final pDateStr = p['date']?.toString() ?? '';
        final pDate = DateTime.tryParse(pDateStr);
        if (pDate != null) {
          final localPDate = pDate.toLocal();
          if ((localPDate.isAfter(_startDate) || localPDate.isAtSameMomentAs(_startDate)) &&
              (localPDate.isBefore(_endDate) || localPDate.isAtSameMomentAs(_endDate))) {
            hasPaymentInRange = true;
            break;
          }
        }
      }

      if (!isCreatedInRange && !hasPaymentInRange) return false;

      if (effectiveStaffId != null) {
        final saleStaffMatch = sale['staffId'] == effectiveStaffId;
        final List<dynamic> saleItems = sale['saleItems'] ?? sale['items'] ?? [];
        final itemStaffMatch = saleItems.any((item) => item['staffId'] == effectiveStaffId);
        if (!saleStaffMatch && !itemStaffMatch) return false;
      }

      if (_selectedItemFilterId != null) {
        final isServiceFilter = _selectedItemFilterId!.startsWith('service_');
        final cleanFilterId = _selectedItemFilterId!.replaceFirst(isServiceFilter ? 'service_' : 'product_', '');
        final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
        final hasMatchingItem = items.any((item) {
          final itemId = item['serviceId']?.toString() ?? '';
          if (isServiceFilter) {
            return itemId == cleanFilterId && !itemId.startsWith('inv_');
          } else {
            return itemId == 'inv_$cleanFilterId';
          }
        });
        if (!hasMatchingItem) return false;
      }
      return true;
    }).toList();

    _cachedAccrualSalesTotal = 0;
    _cachedCashSalesTotal = 0;
    _cachedOnlineSalesTotal = 0;
    _cachedCreditSalesTotal = 0;
    _cachedTotalCommissions = 0;

    for (var sale in _cachedFilteredSales) {
      final dateStr = sale['createdAt']?.toString() ?? sale['date']?.toString() ?? '';
      final saleDate = DateTime.tryParse(dateStr);
      bool isCreatedInRange = false;
      if (saleDate != null) {
        final localSaleDate = saleDate.toLocal();
        final startM = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
        final endM = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59, 999);
        isCreatedInRange = !localSaleDate.isBefore(startM) && !localSaleDate.isAfter(endM);
      }

      final method = sale['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
      final commissionRate = double.tryParse(sale['commissionRate']?.toString() ?? '0') ?? 0.0;
      final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
      double saleSum = 0;
      if (_selectedItemFilterId != null) {
        final isServiceFilter = _selectedItemFilterId!.startsWith('service_');
        final cleanFilterId = _selectedItemFilterId!.replaceFirst(isServiceFilter ? 'service_' : 'product_', '');
        for (var item in items) {
          final isInternal = item['isInternal'] == true || item['isInternal']?.toString() == 'true';
          if (isInternal) continue;
          
          if (effectiveStaffId != null) {
            final itemStaffId = item['staffId']?.toString() ?? sale['staffId']?.toString();
            if (itemStaffId != effectiveStaffId) continue;
          }

          final itemId = item['serviceId']?.toString() ?? '';
          final itemPrice = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          final itemQty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
          final isMatch = isServiceFilter 
              ? (itemId == cleanFilterId && !itemId.startsWith('inv_'))
              : (itemId == 'inv_$cleanFilterId');
          if (isMatch) saleSum += itemPrice * itemQty;
        }
      } else {
        double nonInternalSum = 0.0;
        for (var item in items) {
          final isInternal = item['isInternal'] == true || item['isInternal']?.toString() == 'true';
          if (isInternal) continue;

          if (effectiveStaffId != null) {
            final itemStaffId = item['staffId']?.toString() ?? sale['staffId']?.toString();
            if (itemStaffId != effectiveStaffId) continue;
          }

          final itemPrice = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          final itemQty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
          nonInternalSum += itemPrice * itemQty;
        }
        
        final discount = double.tryParse(sale['discount']?.toString() ?? '0') ?? 0.0;
        final subtotal = double.tryParse(sale['subtotal']?.toString() ?? '0') ?? 0.0;
        if (subtotal > 0) {
          saleSum = nonInternalSum * (1.0 - (discount / subtotal));
        } else {
          saleSum = nonInternalSum;
        }
      }
      if (isCreatedInRange) {
        _cachedAccrualSalesTotal += saleSum;
      }

      final paidAmt = double.tryParse(sale['amountPaid']?.toString() ?? '') ?? saleSum;
      final actualPaid = paidAmt > saleSum ? saleSum : paidAmt;
      final debtAmt = saleSum - actualPaid;

      final saleEntries = (sale['ledgerEntries'] as List<dynamic>?) ?? [];
      double cashEntrySum = 0;
      double onlineEntrySum = 0;

      for (var se in saleEntries) {
        if (se['category'] != 'PAYMENT' || se['type'] != 'DEBIT') continue;
        final amt = double.tryParse(se['amount']?.toString() ?? '0') ?? 0.0;
        String pMethod = 'CASH';
        final n = se['notes']?.toString().trim() ?? '';
        if (n.startsWith('{')) {
          try { pMethod = jsonDecode(n)['paymentMethod']?.toString().toUpperCase() ?? 'CASH'; } catch (_) {}
        }
        if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(pMethod)) {
          onlineEntrySum += amt;
        } else {
          cashEntrySum += amt;
        }
      }

      double cashRatio = 1.0;
      double onlineRatio = 0.0;
      final totalEntrySum = cashEntrySum + onlineEntrySum;

      if (totalEntrySum > 0) {
        cashRatio = cashEntrySum / totalEntrySum;
        onlineRatio = onlineEntrySum / totalEntrySum;
      } else {
        if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(method)) {
          cashRatio = 0.0;
          onlineRatio = 1.0;
        }
      }

      _cachedOnlineSalesTotal += actualPaid * onlineRatio;
      _cachedCashSalesTotal += actualPaid * cashRatio;

      if (debtAmt > 0) {
        _cachedCreditSalesTotal += debtAmt;
      }

      double saleCommission = 0;
      for (var item in items) {
        final isInternal = item['isInternal'] == true || item['isInternal']?.toString() == 'true';
        if (isInternal) continue;

        final itemStaffId = item['staffId']?.toString() ?? sale['staffId']?.toString();
        if (effectiveStaffId != null && itemStaffId != effectiveStaffId) continue;

        final itemPrice = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
        final itemQty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
        final discountAmt = double.tryParse(item['discountAmount']?.toString() ?? '0') ?? 0.0;
        final commAmt = double.tryParse(item['commissionAmount']?.toString() ?? '0') ?? 0.0;

        final itemNet = (itemPrice * itemQty) - discountAmt;
        if (commAmt > 0) {
          saleCommission += commAmt;
        } else {
          double itemCommRate = commissionRate;
          if (item['staff'] != null) {
            itemCommRate = double.tryParse(item['staff']['commissionPercentage']?.toString() ?? item['staff']['commissionRate']?.toString() ?? '0') ?? commissionRate;
          } else if (sale['staff'] != null) {
            itemCommRate = double.tryParse(sale['staff']['commissionPercentage']?.toString() ?? sale['staff']['commissionRate']?.toString() ?? '0') ?? commissionRate;
          }
          if (itemCommRate > 0 && itemCommRate <= 100) {
            saleCommission += itemNet * (itemCommRate / 100);
          }
        }
      }
      _cachedTotalCommissions += saleCommission * (saleSum > 0 ? (actualPaid / saleSum) : 1.0);
    }
  }

  Future<void> _exportCsv() async {
    await ReportCsvExporter.exportCsv(
      context: context,
      ref: ref,
      activeTab: _activeTab,
      salonId: widget.salonId,
      startDate: _startDate,
      endDate: _endDate,
      salesList: _cachedFilteredSales,
      cashSalesTotal: _cachedCashSalesTotal,
      onlineSalesTotal: _cachedOnlineSalesTotal,
      creditSalesTotal: _cachedCreditSalesTotal,
      selectedItemFilterId: _selectedItemFilterId,
    );
  }

  Future<void> _voidSale(String id, ReportParams params) async {
    try {
      await ref.read(apiServiceProvider).voidSale(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction voided successfully')));
        ref.invalidate(reportsProvider(params));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _showVoidConfirm(String id, ReportParams params) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Void Transaction?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: const Text('This will remove the sale from revenue and commission reports but keep it in the history for audit.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _voidSale(id, params);
            }, 
            child: const Text('Yes, Void', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isStaff = user?['role'] == 'STAFF';
    final staffListAsync = widget.salonId != null
        ? ref.watch(staffForSalonProvider(widget.salonId!))
        : ref.watch(staffProvider);

    String? myStaffId;
    if (isStaff && staffListAsync.hasValue) {
      final myStaff = staffListAsync.value!.cast<dynamic>().firstWhere(
        (s) => s['userId'] == user?['id'] || s['user']?['id'] == user?['id'],
        orElse: () => null,
      );
      if (myStaff != null) {
        myStaffId = myStaff['id']?.toString();
      }
    }

    final String? effectiveStaffId = isStaff ? myStaffId : _selectedStaffId;

    final params = ReportParams(
      start: _startDate, 
      end: _endDate, 
      groupBy: 'day', 
      staffId: effectiveStaffId,
      salonId: widget.salonId,
    );

    final reportAsync = ref.watch(reportsProvider(params));
    final isLoadingSummary = reportAsync.isLoading;
    final hasSummaryError = reportAsync.hasError;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.salonName != null ? 'Reports - ${widget.salonName}' : 'Financial Reports',
          style: GoogleFonts.outfit(color: _kDark, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(onPressed: _exportCsv, icon: const Icon(LucideIcons.download, size: 20, color: _kPrimary)),
          IconButton(
            onPressed: () {
              ref.invalidate(reportsProvider(params));
              ref.invalidate(allInventoryTransactionsProvider);
              ref.invalidate(clientsProvider);
              ref.invalidate(servicesProvider);
              ref.invalidate(inventoryProvider);
              ref.invalidate(expensesProvider);
              ref.invalidate(attendanceProvider);
              ref.invalidate(ledgerProvider);
              ref.invalidate(staffProvider);
              if (widget.salonId != null) {
                ref.invalidate(staffForSalonProvider(widget.salonId!));
              }
            }, 
            icon: const Icon(LucideIcons.refreshCcw, size: 20, color: Colors.black38)
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (isLoadingSummary) {
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          }
          if (hasSummaryError) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.alertCircle, size: 64, color: Colors.redAccent),
                    const SizedBox(height: 16),
                    Text('Failed to Load Report', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
                    const SizedBox(height: 8),
                    Text(reportAsync.error.toString(), textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 13, color: Colors.black54)),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        ref.invalidate(reportsProvider(params));
                      },
                      child: Text('Retry', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = reportAsync.value ?? {};
          
          _computeTotals(data, effectiveStaffId);

          final isOwner = user?['role'] == 'OWNER' || user?['role'] == 'SUPER_ADMIN';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDatePickerRow(),
                    const SizedBox(height: 12),
                    if (isOwner) ...[
                      _FilterRowWidget(
                        salonId: widget.salonId,
                        selectedStaffId: _selectedStaffId,
                        selectedItemFilterId: _selectedItemFilterId,
                        onStaffChanged: (val) => setState(() => _selectedStaffId = val),
                        onItemChanged: (val) => setState(() => _selectedItemFilterId = val),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildTabsSelector(isStaff),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Expanded(
                child: _buildActiveTabContent(
                  _activeTab,
                  data,
                  _cachedFilteredSales,
                  _cachedAccrualSalesTotal,
                  _cachedCashSalesTotal,
                  _cachedOnlineSalesTotal,
                  _cachedCreditSalesTotal,
                  _cachedTotalCommissions,
                  params,
                  isStaff,
                  myStaffId,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDatePickerRow() {
    return Row(
      children: [
        Expanded(
          child: _buildDatePickerBox(
            label: 'From Date',
            value: _startDate,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                final newStart = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
                setState(() {
                  _startDate = newStart;
                  if (_startDate.isAfter(_endDate)) {
                    _endDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Start Date was after End Date. End Date adjusted automatically.'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                });
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDatePickerBox(
            label: 'To Date',
            value: _endDate,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                final newEnd = DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999);
                setState(() {
                  _endDate = newEnd;
                  if (_endDate.isBefore(_startDate)) {
                    _startDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('End Date was before Start Date. Start Date adjusted automatically.'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDatePickerBox({required String label, required DateTime value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(LucideIcons.calendar, size: 14, color: _kPrimary),
                const SizedBox(width: 6),
                Text(
                  DateFormat('MMM dd, yyyy').format(value),
                  style: GoogleFonts.outfit(fontSize: 12, color: _kDark, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabsSelector(bool isStaff) {
    final tabs = isStaff 
        ? ['Overview', 'Sales', 'Attendance', 'Salary & Commission']
        : [
            'Overview',
            'Galla / Drawer',
            'Sales',
            'Receivables',
            'Expenses',
            'Staff',
            'Inventory',
            'Stock Adjust',
            'Profit',
            'Attendance',
          ];

    if (!tabs.contains(_activeTab)) {
      _activeTab = 'Overview';
    }

    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tabName = tabs[index];
          final isSelected = _activeTab == tabName;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(
                tabName,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black54,
                ),
              ),
              selected: isSelected,
              selectedColor: _kPrimary,
              backgroundColor: Colors.white,
              checkmarkColor: Colors.white,
              showCheckmark: false,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: isSelected ? _kPrimary : Colors.black.withValues(alpha: 0.05)),
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _activeTab = tabName;
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveTabContent(
    String activeTab,
    Map<String, dynamic> data,
    List<dynamic> filteredSales,
    double accrualSalesTotal,
    double cashSalesTotal,
    double onlineSalesTotal,
    double creditSalesTotal,
    double totalCommissions,
    ReportParams params,
    bool isStaff,
    String? myStaffId,
  ) {
    switch (activeTab) {
      case 'Overview':
        return OverviewTabWidget(
          data: data,
          salesSum: accrualSalesTotal,
          commissionSum: totalCommissions,
          sales: filteredSales,
          isStaff: isStaff,
          myStaffId: myStaffId,
          salonId: widget.salonId,
          startDate: _startDate,
          endDate: _endDate,
        );
      case 'Galla / Drawer':
        return DrawerTabWidget(
          salesList: filteredSales,
          startDate: _startDate,
          endDate: _endDate,
          salonId: params.salonId,
          backendDrawerBalances: data['drawerBalances'] as Map<String, dynamic>?,
        );
      case 'Sales':
        return SalesTabWidget(
          sales: filteredSales,
          salonId: widget.salonId,
          onVoidConfirm: (saleId) => _showVoidConfirm(saleId, params),
          onExport: _exportCsv,
        );
      case 'Receivables':
        return ReceivablesTabWidget(
          salesList: filteredSales,
          salonId: widget.salonId,
        );
      case 'Expenses':
        return ExpensesTabWidget(
          salonId: widget.salonId,
          startDate: _startDate,
          endDate: _endDate,
          salesList: filteredSales,
        );
      case 'Staff':
        return StaffTabWidget(
          salonId: widget.salonId,
          sales: filteredSales,
          data: data,
          selectedStaffId: _selectedStaffId,
          onStaffSelected: (val) => setState(() => _selectedStaffId = val),
          startDate: _startDate,
          endDate: _endDate,
        );
      case 'Inventory':
        return InventoryTabWidget(
          salonId: widget.salonId,
          startDate: _startDate,
          endDate: _endDate,
          selectedStaffId: _selectedStaffId,
          selectedItemFilterId: _selectedItemFilterId,
          salesList: filteredSales,
        );
      case 'Stock Adjust':
        return StockAdjustmentTabWidget(
          salonId: widget.salonId,
          startDate: _startDate,
          endDate: _endDate,
          selectedStaffId: _selectedStaffId,
          selectedItemFilterId: _selectedItemFilterId,
        );
      case 'Profit':
      case 'Tax & Compliance':
        return TaxTabWidget(
          salonId: widget.salonId,
          salesList: filteredSales,
          data: data,
          startDate: _startDate,
          endDate: _endDate,
        );
      case 'Attendance':
        return AttendanceTabWidget(
          salonId: widget.salonId,
          startDate: _startDate,
          endDate: _endDate,
          isStaff: isStaff,
          myStaffId: myStaffId,
          selectedStaffId: _selectedStaffId,
          data: data,
        );
      case 'Salary & Commission':
        return StaffTabWidget(
          salonId: widget.salonId,
          sales: filteredSales,
          data: data,
          selectedStaffId: myStaffId,
          onStaffSelected: (_) {},
          startDate: _startDate,
          endDate: _endDate,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _FilterRowWidget extends ConsumerWidget {
  final String? salonId;
  final String? selectedStaffId;
  final String? selectedItemFilterId;
  final ValueChanged<String?> onStaffChanged;
  final ValueChanged<String?> onItemChanged;

  const _FilterRowWidget({
    required this.salonId,
    required this.selectedStaffId,
    required this.selectedItemFilterId,
    required this.onStaffChanged,
    required this.onItemChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = salonId != null
        ? ref.watch(staffForSalonProvider(salonId!))
        : ref.watch(staffProvider);
    final servicesAsync = salonId != null
        ? ref.watch(servicesForSalonProvider(salonId))
        : ref.watch(servicesProvider);
    final productsAsync = salonId != null
        ? ref.watch(inventoryForSalonProvider(salonId))
        : ref.watch(inventoryProvider);

    final staffList = staffAsync.value ?? [];
    final servicesList = servicesAsync.value ?? [];
    final productsList = productsAsync.value ?? [];

    final List<DropdownMenuItem<String>> staffItems = [
      DropdownMenuItem(value: null, child: Text('All Staff', style: GoogleFonts.outfit(fontSize: 12))),
      ...staffList.map((s) => DropdownMenuItem(
        value: s['id']?.toString(),
        child: Text(s['name']?.toString() ?? 'Staff', style: GoogleFonts.outfit(fontSize: 12)),
      )),
    ];

    final List<DropdownMenuItem<String>> filterItems = [
      DropdownMenuItem(value: null, child: Text('All Items', style: GoogleFonts.outfit(fontSize: 12))),
      ...servicesList.map((s) => DropdownMenuItem(
        value: 'service_${s.id}',
        child: Text('[Service] ${s.name}', style: GoogleFonts.outfit(fontSize: 12)),
      )),
      ...productsList.map((p) => DropdownMenuItem(
        value: 'product_${p['id']}',
        child: Text('[Product] ${p['name']}', style: GoogleFonts.outfit(fontSize: 12)),
      )),
    ];

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            ),
            child: DropdownButtonFormField<String>(
              value: selectedStaffId,
              items: staffItems,
              onChanged: onStaffChanged,
              style: GoogleFonts.outfit(fontSize: 12, color: _kDark, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Filter by Staff',
                labelStyle: GoogleFonts.outfit(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w500),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              isExpanded: true,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            ),
            child: DropdownButtonFormField<String>(
              value: selectedItemFilterId,
              items: filterItems,
              onChanged: onItemChanged,
              style: GoogleFonts.outfit(fontSize: 12, color: _kDark, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Filter by Item',
                labelStyle: GoogleFonts.outfit(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w500),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              isExpanded: true,
            ),
          ),
        ),
      ],
    );
  }
}
