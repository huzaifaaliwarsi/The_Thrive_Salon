import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../providers/ledger_provider.dart';
import '../providers/clients_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/staff_provider.dart' as sp;
import '../providers/currency_provider.dart';
import '../providers/reports_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/salons_provider.dart';
import '../view_models/dashboard_view_model.dart';
import '../utils/format_helper.dart';
import 'package:share_plus/share_plus.dart';

final clientUnpaidSalesProvider = FutureProvider.family<List<dynamic>, String>((ref, clientId) async {
  return await ref.read(apiServiceProvider).getClientUnpaidSales(clientId);
});

const _kPrimary = Color(0xFF6A11CB);
const _kDark = Color(0xFF1B1B3A);
const _kBg = Color(0xFFF4F6FB);

class LedgerView extends ConsumerStatefulWidget {
  final String? clientId;
  final String? vendorId;
  final String? staffId;
  final String? salonId;
  final String? title;

  const LedgerView(
      {super.key,
      this.clientId,
      this.vendorId,
      this.staffId,
      this.salonId,
      this.title});

  @override
  ConsumerState<LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends ConsumerState<LedgerView> {
  int _limit = 100;
  String _activeTab = 'SALON'; // SALON, CLIENTS, VENDORS
  String? _filterClientId;
  String? _filterVendorId;
  String? _filterStaffId;
  bool _isSaving = false;
  bool _showGroupedBills = true;
  String _searchBillQuery = '';

  @override
  void initState() {
    super.initState();
    _filterClientId = widget.clientId;
    _filterVendorId = widget.vendorId;
    _filterStaffId = widget.staffId;

    if (_filterClientId != null)
      _activeTab = 'CLIENTS';
    else if (_filterVendorId != null)
      _activeTab = 'VENDORS';
    else if (_filterStaffId != null) _activeTab = 'STAFF';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    ref.watch(purchasesProvider);
    if (user?['role'] == 'STAFF') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
            child: Text('You do not have permission to view the ledger.')),
      );
    }

    final ledgerAsync = ref.watch(ledgerProvider(LedgerParams(
      clientId: _filterClientId,
      vendorId: _filterVendorId,
      staffId: _filterStaffId,
      salonId: widget.salonId,
      limit: _limit,
      offset: 0,
    )));

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(
            _filterClientId != null ||
                    _filterVendorId != null ||
                    _filterStaffId != null
                ? 'Filtered Ledger'
                : (widget.title ?? 'Ledger Book'),
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        leading: (_filterClientId != null ||
                    _filterVendorId != null ||
                    _filterStaffId != null) &&
                (widget.clientId == null && widget.vendorId == null)
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => setState(() {
                      _filterClientId = null;
                      _filterVendorId = null;
                      _filterStaffId = null;
                      // Reset to appropriate tab based on what was filtered
                      if (_activeTab == 'SALON') _activeTab = 'CLIENTS';
                    }))
            : null,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _kDark,
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(ledgerProvider),
            icon: const Icon(LucideIcons.refreshCcw, size: 18),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (widget.clientId == null && widget.vendorId == null)
            _buildTypeSelector(),
          if (_activeTab == 'SALON' ||
              _filterClientId != null ||
              _filterVendorId != null ||
              _filterStaffId != null) ...[
            _buildSummaryCard(ledgerAsync),
            if (_filterVendorId != null || _filterClientId != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text('Grouped Bills', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                      selected: _showGroupedBills,
                      onSelected: (val) {
                        if (val) setState(() => _showGroupedBills = true);
                      },
                      selectedColor: _kPrimary,
                      labelStyle: TextStyle(color: _showGroupedBills ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: Text('Transactions Log', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                      selected: !_showGroupedBills,
                      onSelected: (val) {
                        if (val) setState(() => _showGroupedBills = false);
                      },
                      selectedColor: _kPrimary,
                      labelStyle: TextStyle(color: !_showGroupedBills ? Colors.white : Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: (_filterVendorId != null && _showGroupedBills)
                  ? ref.watch(purchasesProvider).when(
                        data: (purchases) {
                          final vendorPurchases = purchases.where((p) {
                            if (p['vendorId'] != _filterVendorId) return false;
                            if (_searchBillQuery.isNotEmpty) {
                              final idStr = p['id']?.toString().toLowerCase() ?? '';
                              if (!idStr.contains(_searchBillQuery.toLowerCase())) return false;
                            }
                            return true;
                          }).toList();
                          final entries = ledgerAsync.valueOrNull?['entries'] as List<dynamic>? ?? [];

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: TextField(
                                  decoration: InputDecoration(
                                    labelText: 'Search Bill by ID',
                                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) => setState(() => _searchBillQuery = val),
                                ),
                              ),
                              if (vendorPurchases.isEmpty)
                                Expanded(
                                  child: Center(
                                    child: Text('No bills found for this supplier.', style: GoogleFonts.outfit(color: Colors.black38)),
                                  ),
                                )
                              else
                                Expanded(
                                  child: Scrollbar(
                                    thumbVisibility: true,
                                    child: ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                                      itemCount: vendorPurchases.length,
                                      itemBuilder: (ctx, idx) {
                                        final p = vendorPurchases[idx];
                                        return _buildGroupedBillTile(p, entries);
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                      )
                  : (_filterClientId != null && _showGroupedBills)
                      ? ref.watch(clientUnpaidSalesProvider(_filterClientId!)).when(
                          data: (clientSales) {
                            final entries = ledgerAsync.valueOrNull?['entries'] as List<dynamic>? ?? [];
                            final filteredSales = clientSales.where((s) {
                              if (_searchBillQuery.isNotEmpty) {
                                final idStr = s['id']?.toString().toLowerCase() ?? '';
                                if (!idStr.contains(_searchBillQuery.toLowerCase())) return false;
                              }
                              return true;
                            }).toList();

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      labelText: 'Search Bill by ID',
                                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                    ),
                                    onChanged: (val) => setState(() => _searchBillQuery = val),
                                  ),
                                ),
                                if (filteredSales.isEmpty)
                                  Expanded(
                                    child: Center(
                                      child: Text('No unpaid bills found for this client.', style: GoogleFonts.outfit(color: Colors.black38)),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: Scrollbar(
                                      thumbVisibility: true,
                                      child: ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                                        itemCount: filteredSales.length,
                                        itemBuilder: (ctx, idx) {
                                          final s = filteredSales[idx];
                                          return _buildGroupedSaleTile(s, entries);
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                        )
                  : ledgerAsync.when(
                      data: (data) {
                  final entries = data['entries'] as List<dynamic>;
                  if (entries.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.bookOpen,
                              size: 48, color: Colors.black12),
                          const SizedBox(height: 16),
                          Text('No transactions found',
                              style: GoogleFonts.outfit(color: Colors.black38)),
                        ],
                      ),
                    );
                  }
                  return Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                      itemCount:
                          entries.length + (entries.length >= _limit ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == entries.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: TextButton(
                              onPressed: () => setState(() => _limit += 100),
                              child: Text('Load More Transactions...',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: _kPrimary)),
                            ),
                          );
                        }
                        final entry = entries[index];
                        return _buildEntryTile(entry);
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ] else if (_activeTab == 'CLIENTS')
            Expanded(child: _buildClientList())
          else if (_activeTab == 'VENDORS')
            Expanded(child: _buildVendorList())
          else if (_activeTab == 'STAFF')
            Expanded(child: _buildStaffList()),
        ],
      ),
      floatingActionButton: (_activeTab == 'SALON' ||
              _filterClientId != null ||
              _filterVendorId != null ||
              _filterStaffId != null)
          ? FloatingActionButton.extended(
              onPressed: () => _showPaymentDialog(null, _filterVendorId != null ? 'PURE_PAYMENT' : null),
              label: Text('Record Transaction',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              icon: const Icon(LucideIcons.plus, color: Colors.white),
              backgroundColor: _kDark,
            )
          : null,
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.white,
      child: Row(
        children: [
          _typeBtn('General', 'SALON'),
          const SizedBox(width: 8),
          _typeBtn('Clients', 'CLIENTS'),
          const SizedBox(width: 8),
          _typeBtn('Vendors', 'VENDORS'),
          const SizedBox(width: 8),
          _typeBtn('Staff', 'STAFF'),
        ],
      ),
    );
  }

  Widget _typeBtn(String label, String type) {
    final isActive = _activeTab == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTab = type;
            _filterClientId = null;
            _filterVendorId = null;
            _filterStaffId = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? _kPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? _kPrimary : Colors.black12),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                color: isActive ? Colors.white : Colors.black54,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

   Widget _buildClientList() {
    final clientsAsync = ref.watch(clientsProvider);
    return clientsAsync.when(
      data: (clients) => Scrollbar(
        thumbVisibility: true,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: clients.length,
          itemBuilder: (ctx, i) {
            final client = clients[i];
            final balance =
                double.tryParse(client['balance']?.toString() ?? '0') ?? 0;
            return _entityTile(
                client['name'],
                client['phone'] ?? 'No phone',
                balance,
                () => setState(() {
                      _filterClientId = client['id'];
                      _activeTab = 'SALON'; // Show ledger for this client
                    }),
                onRepayment: () async {
                  setState(() {
                    _filterClientId = client['id'];
                    _filterVendorId = null;
                    _filterStaffId = null;
                  });
                  List<dynamic>? unpaidSales;
                  try {
                     unpaidSales = await ref.read(apiServiceProvider).getClientUnpaidSales(client['id']);
                  } catch(e) {
                     debugPrint('Could not fetch unpaid sales: $e');
                  }
                  if (mounted) {
                     _showPaymentDialog(null, 'PURE_PAYMENT', null, unpaidSales);
                  }
                });
          },
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildVendorList() {
    final vendorsAsync = ref.watch(vendorsProvider);
    return vendorsAsync.when(
      data: (vendors) => Scrollbar(
        thumbVisibility: true,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: vendors.length,
          itemBuilder: (ctx, i) {
            final vendor = vendors[i];
            final balance =
                double.tryParse(vendor['balance']?.toString() ?? '0') ?? 0;
            return _entityTile(
                vendor['name'],
                vendor['phone'] ?? 'No phone',
                balance,
                () => setState(() {
                      _filterVendorId = vendor['id'];
                      _activeTab = 'SALON'; // Show ledger for this vendor
                    }),
                onRepayment: () {
                  setState(() {
                    _filterClientId = null;
                    _filterVendorId = vendor['id'];
                    _filterStaffId = null;
                  });
                  _showPaymentDialog(null, 'PURE_PAYMENT');
                });
          },
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildStaffList() {
    final staffAsync = ref.watch(sp.staffProvider);
    return staffAsync.when(
      data: (staffList) => Scrollbar(
        thumbVisibility: true,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: staffList.length,
          itemBuilder: (ctx, i) {
            final s = staffList[i];
            final balance = double.tryParse(s.balance?.toString() ?? '0') ?? 0;
            return _entityTile(
                s.name ?? 'Unknown',
                s.salaryType ?? '',
                balance,
                () => setState(() {
                      _filterStaffId = s.id;
                      _activeTab = 'SALON';
                    }),
                onRepayment: () {
                  setState(() {
                    _filterClientId = null;
                    _filterVendorId = null;
                    _filterStaffId = s.id;
                  });
                  _showPaymentDialog(null, 'PURE_PAYMENT');
                });
          },
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading staff: $e')),
    );
  }

  Widget _entityTile(
      String name, String sub, double balance, VoidCallback onTap, {VoidCallback? onRepayment}) {
    final currency = ref.watch(currencyProvider);

    String balanceLabel = 'Balance';
    String displayBalanceStr = '$currency ${formatAmount(balance)}';
    Color balanceColor = Colors.black26;

    if (_activeTab == 'VENDORS') {
      final payableDue = balance.abs();
      if (balance != 0) {
        balanceLabel = 'Payable Due';
        displayBalanceStr = '$currency ${formatAmount(payableDue)}';
        balanceColor = Colors.orange.shade800;
      } else {
        balanceLabel = 'Settled';
        displayBalanceStr = '$currency 0.00';
        balanceColor = Colors.green;
      }
    } else if (_activeTab == 'CLIENTS') {
      if (balance > 0) {
        balanceLabel = 'Receivable';
        displayBalanceStr = '$currency ${formatAmount(balance)}';
        balanceColor = Colors.red.shade700;
      } else if (balance < 0) {
        balanceLabel = 'Advance';
        displayBalanceStr = '$currency ${formatAmount(balance.abs())}';
        balanceColor = Colors.green.shade700;
      } else {
        balanceLabel = 'Settled';
        displayBalanceStr = '$currency 0.00';
        balanceColor = Colors.black26;
      }
    } else {
      if (balance > 0) {
        balanceLabel = 'Advances';
        balanceColor = Colors.orange.shade800;
      } else if (balance < 0) {
        balanceLabel = 'Due to Staff';
        balanceColor = Colors.green.shade700;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _kPrimary.withValues(alpha: 0.1),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.outfit(
                  color: _kPrimary, fontWeight: FontWeight.bold)),
        ),
        title: Text(name,
            style:
                GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
        subtitle: Text(sub, style: GoogleFonts.outfit(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(balanceLabel,
                    style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w500)),
                Text(
                  displayBalanceStr,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: balanceColor),
                ),
              ],
            ),
            if (onRepayment != null) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onRepayment,
                icon: const Icon(LucideIcons.banknote, size: 12, color: Colors.teal),
                label: Text('Repay', style: GoogleFonts.outfit(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.teal),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(AsyncValue<Map<String, dynamic>> ledgerAsync) {
    final currency = ref.watch(currencyProvider);
    return ledgerAsync.maybeWhen(
      data: (data) {
        final summary = data['summary'];
        final totalCredit =
            double.tryParse(summary['totalCredit'].toString()) ?? 0;
        final totalDebit =
            double.tryParse(summary['totalDebit'].toString()) ?? 0;
        final rawBalance = double.tryParse(summary['balance'].toString()) ?? 0;

        final isVendor = _filterVendorId != null;
        final isClient = _filterClientId != null;
        final isStaff = _filterStaffId != null;
        final isGeneral = !isVendor && !isClient && !isStaff;

        // For vendor, payable debt is positive amount we owe
        final displayBalance = isVendor ? rawBalance.abs() : rawBalance;

        String cardTitle = 'Drawer Cash Balance';
        String badgeText = '';
        Color badgeBg = Colors.white24;
        Color badgeTextColor = Colors.white;

        if (isVendor) {
          cardTitle = 'Vendor Payable Balance';
          if (displayBalance <= 0.01) {
            badgeText = 'Fully Settled';
            badgeBg = Colors.green.shade600;
          } else {
            badgeText = 'Payable Due to Supplier';
            badgeBg = Colors.amber.shade700;
          }
        } else if (isClient) {
          cardTitle = 'Customer Balance';
          if (rawBalance <= 0.01 && rawBalance >= -0.01) {
            badgeText = 'Fully Settled';
            badgeBg = Colors.green.shade600;
          } else if (rawBalance > 0) {
            badgeText = 'Receivable Pending';
            badgeBg = Colors.amber.shade700;
          } else {
            badgeText = 'Advance Deposit';
            badgeBg = Colors.teal.shade600;
          }
        } else if (isStaff) {
          cardTitle = 'Staff Advance Balance';
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kPrimary, Color(0xFF2575FC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _kPrimary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Title & Action Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              cardTitle,
                              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            if (badgeText.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  badgeText,
                                  style: GoogleFonts.outfit(color: badgeTextColor, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '$currency ${formatAmount(displayBalance)}',
                            style: GoogleFonts.outfit(
                              color: isGeneral && rawBalance < 0 ? Colors.red.shade200 : Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isGeneral)
                    ElevatedButton.icon(
                      onPressed: () => _showReconciliationDialog(context, rawBalance),
                      icon: const Icon(LucideIcons.checkSquare, size: 13, color: _kPrimary),
                      label: Text('Reconcile', style: GoogleFonts.outfit(color: _kPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _showPaymentDialog(null, 'PURE_PAYMENT'),
                      icon: const Icon(LucideIcons.banknote, size: 13, color: _kPrimary),
                      label: Text(
                        isVendor ? 'Pay Vendor' : 'Repayment',
                        style: GoogleFonts.outfit(color: _kPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              if (isGeneral && rawBalance < 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 13),
                      const SizedBox(width: 6),
                      Text(
                        'Warning: Drawer is Negative - Cash Deficit',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            isVendor
                                ? 'Purchases: '
                                : (isClient
                                    ? 'Sales: '
                                    : (isStaff ? 'Advances: ' : 'Total In: ')),
                            style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70),
                          ),
                          Flexible(
                            child: Text(
                              '$currency ${formatAmount(totalCredit)}',
                              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 16, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            isVendor
                                ? 'Paid: '
                                : (isClient
                                    ? 'Paid: '
                                    : (isStaff ? 'Deductions: ' : 'Total Out: ')),
                            style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70),
                          ),
                          Flexible(
                            child: Text(
                              '$currency ${formatAmount(totalDebit)}',
                              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  void _showReconciliationDialog(BuildContext context, double expectedBalance) {
    final currency = ref.read(currencyProvider);
    final physicalController = TextEditingController();
    final notesController = TextEditingController();
    bool isSavingRecon = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Reconcile Drawer Cash',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expected Cash: $currency ${formatAmount(expectedBalance)}',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: physicalController,
                  keyboardType: TextInputType.number,
                  enabled: !isSavingRecon,
                  decoration: InputDecoration(
                    labelText: 'Physical Cash Counted ($currency)',
                    hintText: 'Enter exact amount in register',
                    labelStyle: GoogleFonts.outfit(),
                  ),
                  onChanged: (val) {
                    setDialogState(() {}); // Recalculate variance dynamically
                  },
                ),
                const SizedBox(height: 12),
                () {
                  final physical =
                      double.tryParse(physicalController.text) ?? 0;
                  final variance = physical - expectedBalance;
                  if (physicalController.text.isEmpty)
                    return const SizedBox.shrink();

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: variance == 0
                          ? Colors.green.shade50
                          : (variance > 0
                              ? Colors.blue.shade50
                              : Colors.red.shade50),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          variance == 0
                              ? LucideIcons.checkCircle
                              : (variance > 0
                                  ? LucideIcons.arrowUpCircle
                                  : LucideIcons.arrowDownCircle),
                          color: variance == 0
                              ? Colors.green.shade700
                              : (variance > 0
                                  ? Colors.blue.shade700
                                  : Colors.red.shade700),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            variance == 0
                                ? 'Perfect Match! No variance.'
                                : 'Variance: $currency ${formatAmount(variance)} (${variance > 0 ? 'Surplus' : 'Shortage'})',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: variance == 0
                                  ? Colors.green.shade700
                                  : (variance > 0
                                      ? Colors.blue.shade700
                                      : Colors.red.shade700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }(),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  enabled: !isSavingRecon,
                  decoration: InputDecoration(
                    labelText: 'Notes',
                    hintText: 'e.g., EOD count shift A',
                    labelStyle: GoogleFonts.outfit(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSavingRecon ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: isSavingRecon
                  ? null
                  : () async {
                      final physical = double.tryParse(physicalController.text);
                      if (physical == null || physical < 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter a valid cash count')),
                        );
                        return;
                      }

                      setDialogState(() => isSavingRecon = true);

                      try {
                        final variance = physical - expectedBalance;

                        if (variance != 0) {
                          // Record a reconciliation adjustment entry to the backend
                          await ref
                              .read(apiServiceProvider)
                              .postReconciliation({
                            'amount': variance.abs(),
                            'type': variance > 0 ? 'CREDIT' : 'DEBIT',
                            'notes': notesController.text.trim().isEmpty
                                ? 'Cash reconciliation adjustment (${variance > 0 ? 'Surplus' : 'Shortage'})'
                                : notesController.text.trim(),
                          });
                        }

                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Reconciliation saved successfully!')),
                          );
                          Navigator.pop(ctx);

                          // Invalidate the ledger provider with appropriate params
                          final params = LedgerParams(
                            clientId: _filterClientId,
                            vendorId: _filterVendorId,
                            staffId: _filterStaffId,
                            salonId: widget.salonId,
                            limit: _limit,
                            offset: 0,
                          );
                          ref.invalidate(ledgerProvider(params));
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Failed to reconcile: $e')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => isSavingRecon = false);
                        }
                      }
                    },
              child: isSavingRecon
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text('Reconcile',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceCol(String label, double val, Color color) {
    final currency = ref.watch(currencyProvider);
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.outfit(
                color: color.withValues(alpha: 0.7), fontSize: 12)),
        Text('$currency ${formatAmount(val)}',
            style: GoogleFonts.outfit(
                color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildEntryTile(dynamic entry) {
    final currency = ref.watch(currencyProvider);
    final date =
        (DateTime.tryParse(entry['date']?.toString() ?? '') ?? DateTime.now())
            .toLocal();
    final hasLink = entry['saleId'] != null || entry['purchaseId'] != null;

    // For Vendors: CREDIT is Debt (-), DEBIT is Payment (+)
    // For Clients: CREDIT is Sale (+), DEBIT is Payment (-)
    bool isPositive = false;
    if (_filterVendorId != null) {
      isPositive =
          entry['type'] != 'CREDIT'; // DEBIT is positive for vendor balance
    } else if (_filterClientId != null) {
      isPositive = entry['type'] ==
          'CREDIT'; // CREDIT (Sale) is positive for client balance
    } else if (_filterStaffId != null) {
      isPositive = entry['type'] ==
          'DEBIT'; // DEBIT (Advance) is positive for staff balance (they owe us)
    } else {
      isPositive = entry['type'] == 'CREDIT'; // Default
    }

    // Try parsing structured notes JSON
    Map<String, dynamic>? struct;
    try {
      final n = entry['notes']?.toString() ?? '';
      if (n.startsWith('{') && n.endsWith('}')) {
        struct = jsonDecode(n);
      }
    } catch (_) {}

    if (struct != null) {
      final serviceName = struct['serviceName'] ?? 'Transaction';
      final totalAmount =
          double.tryParse(struct['totalAmount']?.toString() ?? '0') ?? 0;
      final paidAmount =
          double.tryParse(struct['paidAmount']?.toString() ?? '0') ?? 0;
      final remainingAmount =
          double.tryParse(struct['remainingAmount']?.toString() ?? '0') ?? 0;
      final status = struct['status'] ?? 'PAID';
      final method = struct['paymentMethod'] ?? 'CASH';
      final userNotes = struct['userNotes'] ?? '';

      final saleStatus = entry['sale']?['status']?.toString() ?? '';
      final isVoid = saleStatus == 'VOID' || entry['category'] == 'VOID_REVERSAL';

      Color statusBg = Colors.green.withValues(alpha: 0.1);
      Color statusText = Colors.green;
      String statusLabel = 'Paid';
      double effectiveRemaining = remainingAmount;

      if (isVoid) {
        statusBg = Colors.grey.withValues(alpha: 0.15);
        statusText = Colors.grey.shade700;
        statusLabel = 'Voided';
        effectiveRemaining = 0;
      } else if (entry['sale'] != null) {
        final sTotal = double.tryParse(entry['sale']['total']?.toString() ?? '0') ?? totalAmount;
        final sPaid = double.tryParse(entry['sale']['amountPaid']?.toString() ?? '0') ?? paidAmount;
        effectiveRemaining = (sTotal - sPaid) > 0 ? (sTotal - sPaid) : 0;
        if (effectiveRemaining <= 0.01) {
          statusBg = Colors.green.withValues(alpha: 0.1);
          statusText = Colors.green;
          statusLabel = 'Paid';
        } else if (sPaid > 0) {
          statusBg = Colors.orange.withValues(alpha: 0.1);
          statusText = Colors.orange.shade800;
          statusLabel = 'Partial Paid';
        } else {
          statusBg = Colors.red.withValues(alpha: 0.1);
          statusText = Colors.red;
          statusLabel = 'Unpaid';
        }
      } else {
        final bool isFullySettled = (totalAmount > 0 && paidAmount >= totalAmount - 0.01) || remainingAmount <= 0.01;
        if (!isFullySettled && status == 'PARTIAL') {
          statusBg = Colors.orange.withValues(alpha: 0.1);
          statusText = Colors.orange.shade800;
          statusLabel = 'Partial Paid';
        } else if (!isFullySettled && status == 'UNPAID') {
          statusBg = Colors.red.withValues(alpha: 0.1);
          statusText = Colors.red;
          statusLabel = 'Unpaid';
        }
      }

      return InkWell(
        onTap: entry['purchaseId'] != null ? () => _showPurchaseBillDetailsDialog(entry['purchaseId'].toString()) : null,
        onLongPress: () => _showEntryOptions(entry),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)
            ],
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isPositive ? Colors.green : Colors.red)
                          .withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPositive
                          ? LucideIcons.arrowDownLeft
                          : LucideIcons.arrowUpRight,
                      color: isPositive ? Colors.green : Colors.red,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serviceName,
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: _kDark,
                              fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusLabel,
                                style: GoogleFonts.outfit(
                                    color: statusText,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (method == 'ONLINE' || method == 'CARD' || method == 'BANK_TRANSFER' || method == 'UPI' || method == 'DIGITAL' || method == 'CHECK' || method == 'CHEQUE' || method == 'CHQ')
                                  ? 'Online'
                                  : 'Offline',
                              style: GoogleFonts.outfit(
                                  color: Colors.black38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${entry['amount']}',
                        style: GoogleFonts.outfit(
                          color: entry['type'] == 'CREDIT'
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Net Balance Shift',
                        style: GoogleFonts.outfit(
                            color: Colors.black26,
                            fontSize: 9,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Date & Day  ',
                          style: GoogleFonts.outfit(
                              color: Colors.black38, fontSize: 11)),
                      IconButton(
                        icon: const Icon(LucideIcons.edit2, size: 12, color: Colors.indigo),
                        onPressed: () => _showPaymentDialog(entry),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Edit',
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(LucideIcons.trash2, size: 12, color: Colors.redAccent),
                        onPressed: () => _confirmDelete(entry['id']),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Delete',
                      ),
                      if (entry['client'] != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(LucideIcons.share2, size: 12, color: Colors.green),
                          onPressed: () => _shareReceipt(entry),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Share Receipt',
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${DateFormat('EEEE').format(date)} - ${DateFormat('MMM dd, yyyy').format(date)}',
                    style: GoogleFonts.outfit(
                        color: _kDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Invoice Total',
                      style: GoogleFonts.outfit(
                          color: Colors.black38, fontSize: 11)),
                  Text(
                    '$currency ${formatAmount(totalAmount)}',
                    style: GoogleFonts.outfit(
                        color: _kDark,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    struct?['transactionType'] == 'PURE_PAYMENT'
                        ? 'This Installment'
                        : 'Amount Paid',
                    style: GoogleFonts.outfit(
                        color: Colors.black38, fontSize: 11)),
                  Text(
                    '$currency ${formatAmount(paidAmount)}',
                    style: GoogleFonts.outfit(
                        color: Colors.green.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (effectiveRemaining > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Remaining Balance',
                        style: GoogleFonts.outfit(
                            color: Colors.black38, fontSize: 11)),
                    Text(
                      '$currency ${formatAmount(effectiveRemaining)}',
                      style: GoogleFonts.outfit(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
              if (userNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _kBg, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.stickyNote,
                          size: 12, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          userNotes,
                          style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Colors.black54,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: entry['purchaseId'] != null ? () => _showPurchaseBillDetailsDialog(entry['purchaseId'].toString()) : null,
      onLongPress: () => _showEntryOptions(entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isPositive ? Colors.green : Colors.red)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPositive
                    ? LucideIcons.arrowDownLeft
                    : LucideIcons.arrowUpRight,
                color: isPositive ? Colors.green : Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry['notes'] ?? entry['category'] ?? 'Transaction',
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold, color: _kDark),
                        ),
                      ),
                      if (hasLink) ...[
                        const SizedBox(width: 4),
                        Icon(LucideIcons.link,
                            size: 12,
                            color: Colors.blue.withValues(alpha: 0.6)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (entry['client'] != null) ...[
                        _tag(LucideIcons.user, entry['client']['name'],
                            Colors.indigo),
                      ],
                      if (entry['vendor'] != null) ...[
                        _tag(LucideIcons.truck, entry['vendor']['name'],
                            Colors.orange),
                      ],
                      if (entry['staff'] != null) ...[
                        _tag(LucideIcons.contact, entry['staff']['name'],
                            Colors.teal),
                      ],
                      if (entry['client'] == null &&
                          entry['vendor'] == null &&
                          entry['staff'] == null) ...[
                        _tag(LucideIcons.wallet, 'General', Colors.blueGrey),
                      ],
                      Text(
                        entry['type'] == 'CREDIT'
                            ? (_filterVendorId != null
                                ? 'Payable (Debt)'
                                : (_filterClientId != null
                                    ? 'Receivable (Debt)'
                                    : 'Credit (In)'))
                            : (_filterVendorId != null
                                ? 'Paid (Out)'
                                : (_filterClientId != null
                                    ? 'Received (In)'
                                    : 'Debit (Out)')),
                        style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: entry['type'] == 'CREDIT'
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (entry['purchaseId'] != null) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _showPurchaseBillDetailsDialog(entry['purchaseId'].toString()),
                      child: Text(
                        "View full bill details & installments",
                        style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('MMM dd, yyyy - hh:mm a').format(date),
                          style: GoogleFonts.outfit(
                              color: Colors.black38, fontSize: 11)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.edit2, size: 12, color: Colors.indigo),
                            onPressed: () => _showPaymentDialog(entry),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Edit',
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(LucideIcons.trash2, size: 12, color: Colors.redAccent),
                            onPressed: () => _confirmDelete(entry['id']),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Delete',
                          ),
                          if (entry['client'] != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(LucideIcons.share2, size: 12, color: Colors.green),
                              onPressed: () => _shareReceipt(entry),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Share Receipt',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${entry['amount']}',
              style: GoogleFonts.outfit(
                color: entry['type'] == 'CREDIT' ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.outfit(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _showEntryOptions(dynamic entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(LucideIcons.edit2, color: Colors.blue),
              title: Text('Edit Transaction',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _showPaymentDialog(entry);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Colors.red),
              title: Text('Delete Record',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600, color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(entry['id']);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Record?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
            'Are you sure you want to permanently delete this financial record?',
            style: GoogleFonts.outfit()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(apiServiceProvider).deleteLedgerPayment(id);
                ref.invalidate(ledgerProvider);
                if (mounted) Navigator.pop(ctx);
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Failed: $e')));
              }
            },
            child: const Text('Delete',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _shareReceipt(dynamic entry) {
    final currency = ref.read(currencyProvider);
    final date = (DateTime.tryParse(entry['date']?.toString() ?? '') ?? DateTime.now()).toLocal();
    final dateStr = DateFormat('EEEE, MMM dd, yyyy - hh:mm a').format(date);
    final amount = entry['amount']?.toString() ?? '0';

    Map<String, dynamic>? struct;
    try {
      final n = entry['notes']?.toString() ?? '';
      if (n.startsWith('{') && n.endsWith('}')) {
        struct = jsonDecode(n);
      }
    } catch (_) {}

    String serviceName = 'Accounts Transaction';
    String notesText = '';
    String paidStatus = 'PAID';
    String paymentMethod = 'CASH';

    if (struct != null) {
      serviceName = struct['serviceName'] ?? 'Accounts Transaction';
      notesText = struct['userNotes'] ?? '';
      paidStatus = struct['status'] ?? 'PAID';
      paymentMethod = struct['paymentMethod'] ?? 'CASH';
    } else {
      notesText = entry['notes'] ?? '';
    }

    final String clientName = entry['client']?['name'] ?? 'Walk-in Client';
    final String clientPhone = entry['client']?['phone'] ?? 'N/A';
    final String salonName = ref.read(authProvider)?['salon']?['name'] ?? 'Salon Pro';

    String message = "------ *OFFICIAL TRANSACTION RECEIPT* ------\n";
    message += "--------\n";
    message += "*Salon:* $salonName\n";
    message += "*Client:* $clientName ($clientPhone)\n";
    message += "*Date:* $dateStr\n";
    message += "--------\n";
    message += "*Details:* $serviceName\n";
    message += "*Payment Method:* $paymentMethod\n";
    message += "*Status:* $paidStatus\n";
    if (notesText.isNotEmpty) {
      message += "*Notes:* $notesText\n";
    }
    message += "--------\n";
    message += "*Amount:* $currency $amount\n";
    message += "--------\n";
    message += "Thank you for choosing $salonName! Have a beautiful day! --";

    Share.share(message, subject: 'Payment Receipt from $salonName');
  }

  void _shareBill(dynamic purchase, List<dynamic> payments) {
    final currency = ref.read(currencyProvider);
    final salonName = ref.read(authProvider)?['salon']?['name'] ?? 'Salon Pro';
    
    final id = purchase['id']?.toString() ?? '';
    final total = double.tryParse(purchase['total']?.toString() ?? '0') ?? 0.0;
    
    double amountPaid = double.tryParse(purchase['amountPaid']?.toString() ?? '0') ?? 0.0;
    if (payments.isNotEmpty) {
      double calc = 0;
      for (final p in payments) {
        calc += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
      }
      if (calc > 0) amountPaid = calc;
    }
    
    final remaining = total - amountPaid;
    final date = purchase['date'] != null
        ? DateTime.tryParse(purchase['date'])?.toLocal() ?? DateTime.now()
        : DateTime.now();
    final dateStr = DateFormat('EEEE, MMM dd, yyyy').format(date);
    
    String statusLabel = 'Unpaid';
    if (remaining <= 0.01) {
      statusLabel = 'Fully Settled';
    } else if (amountPaid > 0) {
      statusLabel = 'Partially Paid';
    }

    String message = "-- *SUPPLIER BILL RECEIPT* --\n";
    message += "--------\n";
    message += "*Salon:* $salonName\n";
    message += "*Bill #:* ${id.substring(0, 8).toUpperCase()}\n";
    message += "*Date:* $dateStr\n";
    message += "--------\n";
    message += "*Total Invoice Value:* $currency ${formatAmount(total)}\n";
    message += "*Amount Paid:* $currency ${formatAmount(amountPaid)}\n";
    message += "*Outstanding Balance:* $currency ${formatAmount(remaining)}\n";
    message += "*Status:* $statusLabel\n";
    
    if (purchase['notes'] != null && purchase['notes']!.toString().isNotEmpty) {
      message += "*Notes:* ${purchase['notes']}\n";
    }
    
    if (payments.isNotEmpty) {
      message += "--------\n";
      message += "*Payment History:*\n";
      for (int i = 0; i < payments.length; i++) {
        final p = payments[i];
        final pDate = DateTime.tryParse(p['date']?.toString() ?? '')?.toLocal() ?? DateTime.now();
        final amt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
        message += "   ${i + 1}. ${DateFormat('dd MMM yyyy').format(pDate)} - $currency ${formatAmount(amt)}\n";
      }
    }
    
    message += "--------\n";
    message += "Thank you for your business! --";

    Share.share(message, subject: 'Bill #${id.substring(0, 8).toUpperCase()} from $salonName');
  }

  Widget _buildGroupedBillTile(dynamic purchase, List<dynamic> ledgerEntries) {
    final currency = ref.watch(currencyProvider);
    final id = purchase['id']?.toString() ?? '';
    final total = double.tryParse(purchase['total']?.toString() ?? '0') ?? 0.0;

    // Find all ledger entries/payments made specifically towards this purchase
    final payments = ledgerEntries.where((entry) => entry['purchaseId']?.toString() == id && entry['category'] == 'PAYMENT').toList()
      ..sort((a, b) {
        final dA = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
        final dB = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
        return dA.compareTo(dB);
      });

    double amountPaid = double.tryParse(purchase['amountPaid']?.toString() ?? '0') ?? 0.0;
    if (payments.isNotEmpty) {
      double calc = 0;
      for (final p in payments) {
        calc += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
      }
      if (calc > 0) amountPaid = calc;
    }

    final remaining = total - amountPaid;

    final date = purchase['date'] != null
        ? DateTime.tryParse(purchase['date'])?.toLocal() ?? DateTime.now()
        : DateTime.now();

    Color statusColor = Colors.red;
    String statusLabel = 'Unpaid';
    if (remaining <= 0.01) {
      statusColor = Colors.green;
      statusLabel = 'Fully Settled';
    } else if (amountPaid > 0) {
      statusColor = Colors.orange;
      statusLabel = 'Partially Paid';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
      ),
      elevation: 0,
      color: Colors.white,
      child: ExpansionTile(
        title: Text(
          'Bill #${id.substring(0, 8).toUpperCase()}',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 15),
        ),
        subtitle: Text(
          'Date: ${DateFormat('MMM dd, yyyy').format(date)}',
          style: GoogleFonts.outfit(color: Colors.black38, fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statusLabel,
            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.withValues(alpha: 0.9)),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                _billDetailRow('Total Invoice Value:', '$currency ${formatAmount(total)}'),
                _billDetailRow('Amount Paid to Date:', '$currency ${formatAmount(amountPaid)}', color: Colors.green),
                _billDetailRow('Outstanding Balance:', '$currency ${formatAmount(remaining)}', color: remaining > 0 ? Colors.red : Colors.green, isBold: true),
                const SizedBox(height: 12),
                if (purchase['notes'] != null && purchase['notes']!.toString().isNotEmpty) ...[
                  Text('Notes:', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black45)),
                  Text(purchase['notes'], style: GoogleFonts.outfit(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 12),
                ],
                // Payments breakdown list
                Text('Payments History / Installments:', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kPrimary)),
                const SizedBox(height: 4),
                if (payments.isEmpty)
                  Text('No payments registered yet for this bill.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: payments.length,
                    itemBuilder: (context, idx) {
                      final p = payments[idx];
                      final pDate = DateTime.tryParse(p['date']?.toString() ?? '')?.toLocal() ?? DateTime.now();
                      final pNotes = p['notes']?.toString() ?? '';
                      Map<String, dynamic>? pStruct;
                      try {
                        if (pNotes.startsWith('{') && pNotes.endsWith('}')) {
                          pStruct = jsonDecode(pNotes);
                        }
                      } catch (_) {}
                      String pm = pStruct?['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
                      if (pm == 'CASH') {
                        final upper = pNotes.toUpperCase();
                        if (upper.contains('ONLINE') || upper.contains('CARD') || upper.contains('BANK') || upper.contains('UPI') || upper.contains('CHECK') || upper.contains('CHEQUE') || upper.contains('CHQ')) {
                          pm = 'ONLINE';
                        }
                      }
                      final isOnline = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(pm);

                      return Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Installment #${idx + 1}',
                                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.blue.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isOnline ? 'Online' : 'Offline',
                                    style: GoogleFonts.outfit(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isOnline ? Colors.blue.shade800 : Colors.black54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${DateFormat('dd MMM yyyy').format(pDate)})',
                                  style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38),
                                ),
                              ],
                            ),
                            Text(
                              '$currency ${formatAmount(double.tryParse(p['amount']?.toString() ?? '0') ?? 0)}',
                              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),
                if (remaining > 0.01)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _showPaymentDialog(null, 'PURE_PAYMENT', id);
                      },
                      icon: const Icon(LucideIcons.banknote, size: 14, color: Colors.white),
                      label: Text('Settle / Pay Installment', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGroupedSaleTile(dynamic sale, List<dynamic> ledgerEntries) {
    final currency = ref.watch(currencyProvider);
    final id = sale['id']?.toString() ?? '';
    final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;

    // Find all ledger entries/payments made specifically towards this sale
    final payments = ledgerEntries.where((entry) => entry['saleId']?.toString() == id && entry['category'] == 'PAYMENT').toList()
      ..sort((a, b) {
        final dA = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
        final dB = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
        return dA.compareTo(dB);
      });

    double amountPaid = double.tryParse(sale['amountPaid']?.toString() ?? '0') ?? 0.0;
    if (payments.isNotEmpty) {
      double calc = 0;
      for (final p in payments) {
        calc += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
      }
      if (calc > 0) amountPaid = calc;
    }
    
    final remaining = total - amountPaid;

    final date = sale['createdAt'] != null
        ? DateTime.tryParse(sale['createdAt'])?.toLocal() ?? DateTime.now()
        : DateTime.now();

    Color statusColor = Colors.red;
    String statusLabel = 'Unpaid';
    if (remaining <= 0.01) {
      statusColor = Colors.green;
      statusLabel = 'Fully Settled';
    } else if (amountPaid > 0) {
      statusColor = Colors.orange;
      statusLabel = 'Partially Paid';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
      ),
      elevation: 0,
      color: Colors.white,
      child: ExpansionTile(
        title: Text(
          'Bill #${id.substring(0, 8).toUpperCase()}',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 15),
        ),
        subtitle: Text(
          'Date: ${DateFormat('MMM dd, yyyy').format(date)}',
          style: GoogleFonts.outfit(color: Colors.black38, fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statusLabel,
            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.withValues(alpha: 0.9)),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                _billDetailRow('Total Invoice Value:', '$currency ${formatAmount(total)}'),
                _billDetailRow('Amount Paid to Date:', '$currency ${formatAmount(amountPaid)}', color: Colors.green),
                _billDetailRow('Outstanding Balance:', '$currency ${formatAmount(remaining)}', color: remaining > 0 ? Colors.red : Colors.green, isBold: true),
                const SizedBox(height: 12),
                if (sale['notes'] != null && sale['notes']!.toString().isNotEmpty) ...[
                  Text('Notes:', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black45)),
                  Text(sale['notes'], style: GoogleFonts.outfit(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 12),
                ],
                // Payments breakdown list
                Text('Payments History / Installments:', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kPrimary)),
                const SizedBox(height: 4),
                if (payments.isEmpty)
                  Text('No payments registered yet for this bill.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: payments.length,
                    itemBuilder: (context, idx) {
                      final p = payments[idx];
                      final pDate = DateTime.tryParse(p['date']?.toString() ?? '')?.toLocal() ?? DateTime.now();
                      final pNotes = p['notes']?.toString() ?? '';
                      Map<String, dynamic>? pStruct;
                      try {
                        if (pNotes.startsWith('{') && pNotes.endsWith('}')) {
                          pStruct = jsonDecode(pNotes);
                        }
                      } catch (_) {}
                      String pm = pStruct?['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
                      if (pm == 'CASH') {
                        final upper = pNotes.toUpperCase();
                        if (upper.contains('ONLINE') || upper.contains('CARD') || upper.contains('BANK') || upper.contains('UPI') || upper.contains('CHECK') || upper.contains('CHEQUE') || upper.contains('CHQ')) {
                          pm = 'ONLINE';
                        }
                      }
                      final isOnline = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(pm);

                      return Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Installment #${idx + 1}',
                                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.blue.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isOnline ? 'Online' : 'Offline',
                                    style: GoogleFonts.outfit(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isOnline ? Colors.blue.shade800 : Colors.black54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${DateFormat('dd MMM yyyy').format(pDate)})',
                                  style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38),
                                ),
                              ],
                            ),
                            Text(
                              '$currency ${formatAmount(double.tryParse(p['amount']?.toString() ?? '0') ?? 0)}',
                              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),
                if (remaining > 0.01)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _showPaymentDialog(null, 'PURE_PAYMENT', null, [sale], id);
                      },
                      icon: const Icon(LucideIcons.banknote, size: 14, color: Colors.white),
                      label: Text('Settle / Pay Installment', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  )
              ],
            ),
          )
        ],
      ),
    );
  }
  
  Widget _billDetailRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54)),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? _kDark,
            ),
          ),
        ],
      ),
    );
  }

  void _showPurchaseBillDetailsDialog(String purchaseId) {
    final purchasesAsync = ref.read(purchasesProvider);
    final ledgerAsync = ref.read(ledgerProvider(LedgerParams(salonId: widget.salonId, limit: 1000)));

    purchasesAsync.whenData((purchases) {
      final purchase = purchases.firstWhere((p) => p['id']?.toString() == purchaseId, orElse: () => null);
      if (purchase == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill details not found.')),
        );
        return;
      }

      final entries = ledgerAsync.valueOrNull?['entries'] as List<dynamic>? ?? [];
      final id = purchase['id']?.toString() ?? '';
      final total = double.tryParse(purchase['total']?.toString() ?? '0') ?? 0.0;
      final amountPaid = double.tryParse(purchase['amountPaid']?.toString() ?? '0') ?? 0.0;
      final remaining = total - amountPaid;
      final date = purchase['date'] != null
          ? DateTime.tryParse(purchase['date'])?.toLocal() ?? DateTime.now()
          : DateTime.now();

      final payments = entries.where((entry) => entry['purchaseId']?.toString() == id && entry['category'] == 'PAYMENT').toList()
        ..sort((a, b) {
          final dA = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
          final dB = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
          return dA.compareTo(dB);
        });
      final currency = ref.read(currencyProvider);

      Color statusColor = Colors.red;
      String statusLabel = 'Unpaid';
      if (remaining <= 0.01) {
        statusColor = Colors.green;
        statusLabel = 'Fully Settled';
      } else if (amountPaid > 0) {
        statusColor = Colors.orange;
        statusLabel = 'Partially Paid';
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Bill #${id.substring(0, 8).toUpperCase()}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _shareBill(purchase, payments),
                    child: Icon(LucideIcons.share, size: 20, color: _kPrimary),
                  )
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Date: ${DateFormat('MMM dd, yyyy').format(date)}', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 12)),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  _billDetailRow('Total Invoice Value:', '$currency ${formatAmount(total)}'),
                  _billDetailRow('Amount Paid to Date:', '$currency ${formatAmount(amountPaid)}', color: Colors.green),
                  _billDetailRow('Outstanding Balance:', '$currency ${formatAmount(remaining)}', color: remaining > 0 ? Colors.red : Colors.green, isBold: true),
                  const SizedBox(height: 16),
                  if (purchase['notes'] != null && purchase['notes']!.toString().isNotEmpty) ...[
                    Text('Notes:', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black45)),
                    Text(purchase['notes'], style: GoogleFonts.outfit(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 16),
                  ],
                  Text('Payments History / Installments:', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kPrimary)),
                  const SizedBox(height: 8),
                  if (payments.isEmpty)
                    Text('No payments registered yet for this bill.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38))
                  else
                    ...payments.asMap().entries.map((item) {
                      final idx = item.key;
                      final p = item.value;
                      final pDate = DateTime.tryParse(p['date']?.toString() ?? '')?.toLocal() ?? DateTime.now();
                      final pNotes = p['notes']?.toString() ?? '';
                      Map<String, dynamic>? pStruct;
                      try {
                        if (pNotes.startsWith('{') && pNotes.endsWith('}')) {
                          pStruct = jsonDecode(pNotes);
                        }
                      } catch (_) {}
                      String pm = pStruct?['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
                      if (pm == 'CASH') {
                        final upper = pNotes.toUpperCase();
                        if (upper.contains('ONLINE') || upper.contains('CARD') || upper.contains('BANK') || upper.contains('UPI') || upper.contains('CHECK') || upper.contains('CHEQUE') || upper.contains('CHQ')) {
                          pm = 'ONLINE';
                        }
                      }
                      final isOnline = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(pm);

                      return Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Installment #${idx + 1}',
                                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.blue.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isOnline ? 'Online' : 'Offline',
                                    style: GoogleFonts.outfit(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isOnline ? Colors.blue.shade800 : Colors.black54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${DateFormat('dd MMM yyyy').format(pDate)})',
                                  style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38),
                                ),
                              ],
                            ),
                            Text(
                              '$currency ${formatAmount(double.tryParse(p['amount']?.toString() ?? '0') ?? 0)}',
                              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                            )
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
            if (remaining > 0.01)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showPaymentDialog(null, 'PURE_PAYMENT', id);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                child: Text('Settle Balance', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      );
    });
  }

  void _showPaymentDialog([dynamic entry, String? defaultTransactionType, String? defaultPurchaseId, List<dynamic>? clientUnpaidSales, String? defaultSaleId]) {
    final currency = ref.read(currencyProvider);
    final isEdit = entry != null;

    Map<String, dynamic>? struct;
    try {
      if (isEdit) {
        final n = entry['notes']?.toString() ?? '';
        if (n.startsWith('{') && n.endsWith('}')) {
          struct = jsonDecode(n);
        }
      }
    } catch (_) {}

    final purchasesList = ref.read(purchasesProvider).valueOrNull ?? [];
    String? selectedPurchaseId = defaultPurchaseId ?? (struct != null ? struct['purchaseId']?.toString() : entry?['purchaseId']?.toString());
    String? selectedSaleId = defaultSaleId ?? (struct != null ? struct['saleId']?.toString() : entry?['saleId']?.toString());

    double initialRemaining = 0.0;
    if (selectedPurchaseId != null && !isEdit) {
      final pRecord = purchasesList.firstWhere((p) => p['id']?.toString() == selectedPurchaseId, orElse: () => null);
      if (pRecord != null) {
        final total = double.tryParse(pRecord['total']?.toString() ?? '0') ?? 0.0;
        final amountPaid = double.tryParse(pRecord['amountPaid']?.toString() ?? '0') ?? 0.0;
        initialRemaining = total - amountPaid;
      }
    } else if (selectedSaleId != null && !isEdit && clientUnpaidSales != null) {
      final sRecord = clientUnpaidSales.firstWhere((s) => s['id']?.toString() == selectedSaleId, orElse: () => null);
      if (sRecord != null) {
        final total = double.tryParse(sRecord['total']?.toString() ?? '0') ?? 0.0;
        final amountPaid = double.tryParse(sRecord['amountPaid']?.toString() ?? '0') ?? 0.0;
        initialRemaining = total - amountPaid;
      }
    }

    final serviceNameC = TextEditingController(
        text: struct != null ? struct['serviceName'] : (defaultPurchaseId != null ? 'Settle Bill #${defaultPurchaseId.substring(0, 8).toUpperCase()}' : (defaultSaleId != null ? 'Settle Bill #${defaultSaleId.substring(0, 8).toUpperCase()}' : '')));
    final totalAmountC = TextEditingController(
        text: struct != null
            ? struct['totalAmount']?.toString()
            : (isEdit ? entry['amount']?.toString() : (initialRemaining > 0 ? initialRemaining.toStringAsFixed(2) : '')));
    final paidAmountC = TextEditingController(
        text: struct != null
            ? struct['paidAmount']?.toString()
            : (isEdit ? entry['amount']?.toString() : (initialRemaining > 0 ? initialRemaining.toStringAsFixed(2) : '')));
    final notesC = TextEditingController(
        text: struct != null
            ? struct['userNotes']
            : (isEdit ? entry['notes'] : ''));

    String transactionType = defaultTransactionType ?? (struct != null
        ? (struct['transactionType'] ?? (_filterVendorId != null ? 'PURE_PAYMENT' : 'SALE_PURCHASE'))
        : (_filterVendorId != null ? 'PURE_PAYMENT' : 'SALE_PURCHASE'));
    String status = struct != null ? (struct['status'] ?? 'PAID') : 'PAID';
    String paymentMethod =
        struct != null ? (struct['paymentMethod'] ?? 'CASH') : 'CASH';
    String type =
        isEdit ? entry['type'] : (_filterClientId != null ? 'DEBIT' : 'DEBIT');
    DateTime selectedDate =
        isEdit ? DateTime.parse(entry['date']).toLocal() : DateTime.now();

    final vendorPurchases = purchasesList.where((p) {
      final vendorMatch = p['vendorId'] == _filterVendorId;
      if (!vendorMatch) return false;
      if (isEdit && p['id'] == entry['purchaseId']) return true;
      final total = double.tryParse(p['total']?.toString() ?? '0') ?? 0.0;
      final amountPaid = double.tryParse(p['amountPaid']?.toString() ?? '0') ?? 0.0;
      final remaining = total - amountPaid;
      return remaining > 0;
    }).toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalVal = double.tryParse(totalAmountC.text) ?? 0;
          double paidVal = double.tryParse(paidAmountC.text) ?? 0;
          if (transactionType == 'PURE_PAYMENT') {
            paidVal = totalVal;
          } else {
            if (status == 'PAID') {
              paidVal = totalVal;
            } else if (status == 'UNPAID') {
              paidVal = 0;
            }
          }
          final remainingVal = totalVal - paidVal;

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(
                isEdit ? 'Edit Accounts Finance' : 'Record Accounts Finance',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Transaction Type Selector
                    DropdownButtonFormField<String>(
                      value: transactionType,
                      style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                      decoration: InputDecoration(
                          labelText: 'Transaction Type',
                          prefixIcon: Icon(LucideIcons.fileText, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: _kBg,
                          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38)),
                      items: const [
                        DropdownMenuItem(
                            value: 'SALE_PURCHASE',
                            child: Text('New Sale / Purchase')),
                        DropdownMenuItem(
                            value: 'PURE_PAYMENT',
                            child: Text('Pure Payment / Settle Debt')),
                      ],
                      onChanged: (v) => setDialogState(() {
                        transactionType = v!;
                        if (transactionType == 'PURE_PAYMENT') {
                          status = 'PAID';
                          paidAmountC.text = totalAmountC.text;
                        }
                      }),
                    ),
                    const SizedBox(height: 12),

                    if (_filterVendorId != null) ...[
                      DropdownButtonFormField<String?>(
                        value: selectedPurchaseId,
                        style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                        decoration: InputDecoration(
                          labelText: 'Select Supplier Bill to Settle',
                          prefixIcon: Icon(LucideIcons.fileSpreadsheet, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: _kBg,
                          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                        ),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('No Bill (General Payment)', style: GoogleFonts.outfit())),
                          ...vendorPurchases.map<DropdownMenuItem<String?>>((p) {
                            final total = double.tryParse(p['total']?.toString() ?? '0') ?? 0.0;
                            final amountPaid = double.tryParse(p['amountPaid']?.toString() ?? '0') ?? 0.0;
                            final remaining = total - amountPaid;
                            final formattedDate = p['date'] != null
                                ? DateFormat('yyyy-MM-dd').format(DateTime.parse(p['date']))
                                : '';
                            return DropdownMenuItem<String?>(
                              value: p['id']?.toString(),
                              child: Text(
                                'Bill #${p['id']?.toString().substring(0, 8)} ($formattedDate) - Rem: $currency ${formatAmount(remaining)}',
                                style: GoogleFonts.outfit(fontSize: 12),
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (v) => setDialogState(() {
                          selectedPurchaseId = v;
                          if (selectedPurchaseId != null) {
                            final selectedPurchase = vendorPurchases.firstWhere((p) => p['id'] == selectedPurchaseId);
                            final total = double.tryParse(selectedPurchase['total']?.toString() ?? '0') ?? 0.0;
                            final amountPaid = double.tryParse(selectedPurchase['amountPaid']?.toString() ?? '0') ?? 0.0;
                            final remaining = total - amountPaid;
                            
                            totalAmountC.text = remaining.toString();
                            paidAmountC.text = remaining.toString();
                            
                            serviceNameC.text = 'Settle Bill #${selectedPurchase['id']?.toString().substring(0, 8)}';
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 6.5 Sale Bill Selection (Client Only)
                    if (_filterClientId != null && transactionType == 'PURE_PAYMENT' && clientUnpaidSales != null && clientUnpaidSales.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        value: selectedSaleId,
                        style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                        decoration: InputDecoration(
                          labelText: 'Select Specific Bill (Optional - FIFO by default)',
                          prefixIcon: Icon(LucideIcons.fileText, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: _kBg,
                          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                        ),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('No Bill (Auto-Allocate FIFO)', style: GoogleFonts.outfit())),
                          ...clientUnpaidSales.map<DropdownMenuItem<String?>>((s) {
                            final total = double.tryParse(s['total']?.toString() ?? '0') ?? 0.0;
                            final amountPaid = double.tryParse(s['amountPaid']?.toString() ?? '0') ?? 0.0;
                            final remaining = total - amountPaid;
                            final formattedDate = s['createdAt'] != null
                                ? DateFormat('MMM dd').format(DateTime.parse(s['createdAt']).toLocal())
                                : '';
                            return DropdownMenuItem<String?>(
                              value: s['id']?.toString(),
                              child: Text(
                                'Sale $formattedDate - Rem: $currency ${formatAmount(remaining)}',
                                style: GoogleFonts.outfit(fontSize: 12),
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (v) => setDialogState(() {
                          selectedSaleId = v;
                          if (selectedSaleId != null) {
                            final selectedSale = clientUnpaidSales.firstWhere((s) => s['id'] == selectedSaleId);
                            final total = double.tryParse(selectedSale['total']?.toString() ?? '0') ?? 0.0;
                            final amountPaid = double.tryParse(selectedSale['amountPaid']?.toString() ?? '0') ?? 0.0;
                            final remaining = total - amountPaid;
                            
                            totalAmountC.text = remaining.toString();
                            paidAmountC.text = remaining.toString();
                            
                            serviceNameC.text = 'Settle Bill #${selectedSale['id']?.toString().substring(0, 8)}';
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 2. Service / Product Name (Only for Sale / Purchase)
                    if (transactionType == 'SALE_PURCHASE') ...[
                      TextField(
                        controller: serviceNameC,
                        style: GoogleFonts.outfit(fontSize: 14),
                        decoration: InputDecoration(
                            labelText: 'Service / Product Name',
                            prefixIcon: Icon(LucideIcons.shoppingBag, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: _kBg,
                            contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38)),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 3. Amount Field
                    TextField(
                      controller: totalAmountC,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.outfit(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: transactionType == 'PURE_PAYMENT'
                            ? 'Payment Amount'
                            : 'Total Bill Amount',
                        prefixText: '$currency ',
                        prefixIcon: Icon(LucideIcons.banknote, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: _kBg,
                        contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          if (transactionType == 'PURE_PAYMENT' ||
                              status == 'PAID') {
                            paidAmountC.text = val;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    // 4. Status Option (Only for Sale / Purchase)
                    if (transactionType == 'SALE_PURCHASE') ...[
                      DropdownButtonFormField<String>(
                        value: status,
                        style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                        decoration: InputDecoration(
                            labelText: 'Payment Status',
                            prefixIcon: Icon(LucideIcons.checkCircle, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: _kBg,
                            contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38)),
                        items: const [
                          DropdownMenuItem(
                              value: 'PAID', child: Text('Paid (Full)')),
                          DropdownMenuItem(
                              value: 'PARTIAL', child: Text('Partial Paid')),
                          DropdownMenuItem(
                              value: 'UNPAID', child: Text('Unpaid')),
                        ],
                        onChanged: (v) => setDialogState(() {
                          status = v!;
                          if (status == 'PAID') {
                            paidAmountC.text = totalAmountC.text;
                          } else if (status == 'UNPAID') {
                            paidAmountC.text = '0';
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 5. Paid Amount (Only for Partial status)
                    if (transactionType == 'SALE_PURCHASE' &&
                        status == 'PARTIAL') ...[
                      TextField(
                        controller: paidAmountC,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.outfit(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Paid Amount',
                          prefixText: '$currency ',
                          prefixIcon: Icon(LucideIcons.wallet, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: _kBg,
                          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                        ),
                        onChanged: (val) {
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 6. Remaining / Balance summary
                    if (transactionType == 'SALE_PURCHASE') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: remainingVal > 0
                              ? Colors.red.withValues(alpha: 0.05)
                              : Colors.green.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  (remainingVal > 0 ? Colors.red : Colors.green)
                                      .withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Remaining / Balance:',
                                style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    color: remainingVal > 0
                                        ? Colors.red.shade900
                                        : Colors.green.shade900)),
                            Text(
                              '$currency ${formatAmount(remainingVal)}',
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: remainingVal > 0
                                      ? Colors.red.shade900
                                      : Colors.green.shade900),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 7. Cash / Online Selection (Offline / Online)
                    DropdownButtonFormField<String>(
                      value: (paymentMethod == 'ONLINE' || paymentMethod == 'CARD' || paymentMethod == 'BANK_TRANSFER' || paymentMethod == 'UPI' || paymentMethod == 'DIGITAL' || paymentMethod == 'CHECK' || paymentMethod == 'CHEQUE' || paymentMethod == 'CHQ') ? 'ONLINE' : 'CASH',
                      style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                      decoration: InputDecoration(
                          labelText: 'Payment Method',
                          prefixIcon: Icon(LucideIcons.creditCard, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: _kBg,
                          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38)),
                      items: const [
                        DropdownMenuItem(value: 'CASH', child: Text('Offline / Cash')),
                        DropdownMenuItem(
                            value: 'ONLINE', child: Text('Online / Bank')),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => paymentMethod = v!),
                    ),
                    const SizedBox(height: 12),

                    // 8. General credit/debit switcher (only visible for General tab)
                    if (_filterClientId == null &&
                        _filterVendorId == null &&
                        _filterStaffId == null) ...[
                      DropdownButtonFormField<String>(
                        value: type,
                        style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                        items: const [
                          DropdownMenuItem(
                              value: 'CREDIT',
                              child: Text('General Income (Money In)')),
                          DropdownMenuItem(
                              value: 'DEBIT',
                              child: Text('General Expense (Money Out)')),
                        ],
                        onChanged: (v) => setDialogState(() => type = v!),
                        decoration: InputDecoration(
                            labelText: 'Type',
                            prefixIcon: Icon(LucideIcons.arrowRightLeft, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: _kBg,
                            contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38)),
                      ),
                      const SizedBox(height: 12),
                    ],

                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(selectedDate),
                          );
                          if (time != null) {
                            setDialogState(() {
                              selectedDate = DateTime(date.year, date.month,
                                  date.day, time.hour, time.minute);
                            });
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: _kBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.calendar, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Date & Time', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${DateFormat('EEEE').format(selectedDate)} - ${DateFormat('MMM dd, yyyy - hh:mm a').format(selectedDate)}',
                                    style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        color: _kPrimary,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: notesC,
                      maxLines: 2,
                      style: GoogleFonts.outfit(fontSize: 14),
                      decoration: InputDecoration(
                          labelText: 'Additional Notes / Remarks',
                          prefixIcon: Icon(LucideIcons.fileText, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: _kBg,
                          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38)),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.w600))),
              Consumer(
                builder: (context, ref, _) {
                  final ledgerAsync = ref.watch(ledgerProvider(const LedgerParams()));
                  final cashBalance = ledgerAsync.maybeWhen(
                    data: (d) => double.tryParse(d['summary']?['balance']?.toString() ?? '0') ?? 0.0,
                    orElse: () => 0.0,
                  );
                  return ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () async {
                             if (totalAmountC.text.trim().isEmpty) {
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                 content: Text('Amount is required'),
                                 backgroundColor: Colors.redAccent,
                                 behavior: SnackBarBehavior.floating,
                                ));
                               return;
                             }
                             
                             final totalVal = double.tryParse(totalAmountC.text
                                     .replaceAll(',', '')
                                     .trim()) ??
                                 0;
                             double paidVal = double.tryParse(paidAmountC.text
                                     .replaceAll(',', '')
                                     .trim()) ??
                                 0;
                             if (transactionType == 'PURE_PAYMENT') {
                               paidVal = totalVal;
                             } else {
                               if (status == 'PAID') {
                                 paidVal = totalVal;
                               } else if (status == 'UNPAID') {
                                 paidVal = 0;
                               }
                             }

                             if (totalVal <= 0) {
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                 content: Text('Transaction amount must be greater than zero'),
                                 backgroundColor: Colors.redAccent,
                                 behavior: SnackBarBehavior.floating,
                               ));
                               return;
                             }

                             if (transactionType == 'SALE_PURCHASE' && status == 'PARTIAL') {
                               if (paidVal < 0) {
                                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                   content: Text('Paid amount cannot be negative'),
                                   backgroundColor: Colors.redAccent,
                                   behavior: SnackBarBehavior.floating,
                                 ));
                                 return;
                               }
                               if (paidVal >= totalVal) {
                                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                   content: Text('Paid amount must be less than total bill for partial payments'),
                                   backgroundColor: Colors.redAccent,
                                   behavior: SnackBarBehavior.floating,
                                 ));
                                 return;
                               }
                             }

                             final remainingVal = totalVal - paidVal;

                             double dbAmount = 0;
                             String dbType = 'DEBIT'; // Default

                             if (transactionType == 'PURE_PAYMENT') {
                               dbAmount = paidVal;
                               dbType = 'DEBIT'; // Reduces debt
                             } else {
                               if (status == 'PAID') {
                                 dbAmount = totalVal;
                                 dbType = 'DEBIT';
                               } else {
                                 dbAmount = remainingVal;
                                 dbType = 'CREDIT';
                               }
                             }

                             if (_filterClientId == null &&
                                 _filterVendorId == null &&
                                 _filterStaffId == null) {
                               dbAmount = status == 'PAID' ? totalVal : paidVal;
                               dbType = type;
                             }

                            // Check negative cash balance drawer outflow:
                            double cashDiff = 0;
                            if (_filterClientId != null) {
                              cashDiff = paidVal;
                            } else if (_filterVendorId != null) {
                              cashDiff = -paidVal;
                            } else {
                              cashDiff = dbType == 'CREDIT' ? dbAmount : -dbAmount;
                              if (cashDiff < 0 && cashDiff.abs() > cashBalance) {
                                final shortfall = cashDiff.abs() - cashBalance;
                                final cur = ref.read(currencyProvider);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                    'Warning: Drawer will go negative by $cur ${shortfall.toStringAsFixed(2)}. Saved anyway.',
                                  ),
                                  backgroundColor: Colors.orange.shade800,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 4),
                                ));
                              }
                            }

                            setDialogState(() => _isSaving = true);
                            try {
                              final Map<String, dynamic> structuredNotes = {
                                'serviceName': serviceNameC.text.isEmpty
                                    ? (transactionType == 'PURE_PAYMENT'
                                        ? 'Settle Debt'
                                        : 'General Transaction')
                                    : serviceNameC.text,
                                'totalAmount': totalVal,
                                'paidAmount': paidVal,
                                'remainingAmount': remainingVal,
                                'status': status,
                                'paymentMethod': paymentMethod,
                                'transactionType': transactionType,
                                'purchaseId': selectedPurchaseId,
                                'saleId': selectedSaleId,
                                'userNotes': notesC.text,
                              };

                              final data = {
                                'clientId': _filterClientId,
                                'vendorId': _filterVendorId,
                                'salonId': widget.salonId,
                                'purchaseId': selectedPurchaseId,
                                'saleId': selectedSaleId,
                                'amount': dbAmount.toString(),
                                'type': dbType,
                                'paymentMethod': paymentMethod,
                                'notes': jsonEncode(structuredNotes),
                                'date': selectedDate.toUtc().toIso8601String(),
                              };

                              if (isEdit) {
                                await ref
                                    .read(apiServiceProvider)
                                    .updateLedgerPayment(entry['id'], data);
                              } else {
                                if (_filterVendorId != null && transactionType == 'SALE_PURCHASE' && selectedPurchaseId == null) {
                                  final purchaseData = {
                                    'vendorId': _filterVendorId,
                                    'total': totalVal,
                                    'amountPaid': paidVal,
                                    'paymentMethod': paymentMethod,
                                    'notes': notesC.text.isNotEmpty ? notesC.text : 'Manual Bill Entry',
                                    'date': selectedDate.toUtc().toIso8601String(),
                                  };
                                  await ref.read(apiServiceProvider).createPurchase(purchaseData);
                                } else {
                                  await ref
                                      .read(apiServiceProvider)
                                      .createLedgerPayment(data);
                                }
                              }

                              ref.invalidate(ledgerProvider);
                              ref.invalidate(purchasesProvider);
                              ref.invalidate(reportsProvider);
                              ref.invalidate(salonsProvider);
                              ref.invalidate(dashboardViewModelProvider);
                              ref.invalidate(dashboardMetricsProvider);
                              if (_filterClientId != null) {
                                ref.invalidate(clientsProvider);
                              }
                              if (_filterVendorId != null) {
                                ref.invalidate(vendorsProvider);
                              }
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())));
                            } finally {
                              if (mounted) setDialogState(() => _isSaving = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(isEdit ? 'Update' : 'Save',
                            style: GoogleFonts.outfit(
                                color: Colors.white, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}





