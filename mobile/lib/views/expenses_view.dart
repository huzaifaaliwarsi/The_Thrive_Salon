import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../providers/expenses_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/ledger_provider.dart';
import '../models/payment_account.dart';
import '../providers/payment_accounts_provider.dart';

const _kPrimary  = Color(0xFF6A11CB);
const _kDark     = Color(0xFF1B1B3A);
const _kBg       = Color(0xFFF4F6FB);
 
class ExpensesView extends ConsumerStatefulWidget {
  const ExpensesView({super.key});

  @override
  ConsumerState<ExpensesView> createState() => _ExpensesViewState();
}

class _ExpensesViewState extends ConsumerState<ExpensesView> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  List<String> get _dynamicCategories {
    final defaultCat = {'Salary', 'Wages', 'Bills', 'Rent', 'Supplies', 'Other'};
    final filter = ExpenseFilter(start: _startDate, end: _endDate);
    final expenses = ref.read(expensesProvider(filter)).valueOrNull ?? [];
    final existingCat = expenses.map((e) => e['category']?.toString() ?? 'Other').toSet();
    return {...defaultCat, ...existingCat, '+ Add Custom'}.toList();
  }

  void _showAddExpenseDialog([Map<String, dynamic>? expense]) {
    final isEditing = expense != null;
    final nameController = TextEditingController(text: expense?['name'] ?? '');
    final amountController = TextEditingController(text: expense?['amount']?.toString() ?? '');
    
    final cats = _dynamicCategories;
    String selectedCategory = expense != null && cats.contains(expense['category']) 
        ? expense['category'] 
        : cats[0];
    
    bool isCustomCategory = false;
    final customCategoryCtrl = TextEditingController();
    DateTime selectedDate = expense?['date'] != null ? DateTime.parse(expense!['date']).toLocal() : DateTime.now();
    bool isSubmitting = false;
    String paymentMethod = (expense?['paymentMethod']?.toString() ?? 'CASH').toUpperCase();
    String? selectedPaymentAccountId = expense?['paymentAccountId']?.toString() ?? expense?['paymentAccount']?['id']?.toString();

    final ledgerEntriesList = ref.read(ledgerProvider(const LedgerParams())).valueOrNull?['entries'] as List<dynamic>? ?? [];
    if (expense != null) {
      final matchingLedger = ledgerEntriesList.firstWhere(
        (e) => e['expenseId'] == expense['id'],
        orElse: () => null,
      );
      if (matchingLedger != null && matchingLedger['notes'] != null) {
        try {
          final struct = jsonDecode(matchingLedger['notes']);
          if (struct['paymentMethod'] != null) {
            paymentMethod = struct['paymentMethod'].toString().toUpperCase();
          }
          if (struct['paymentAccountId'] != null && selectedPaymentAccountId == null) {
            selectedPaymentAccountId = struct['paymentAccountId'].toString();
          }
        } catch (_) {}
      }
    }

    final double initAmt = double.tryParse(expense?['amount']?.toString() ?? '') ?? 0;
    final cashPartController = TextEditingController(
      text: paymentMethod == 'SPLIT' && initAmt > 0 ? (initAmt / 2).toStringAsFixed(2) : '',
    );
    final onlinePartController = TextEditingController(
      text: paymentMethod == 'SPLIT' && initAmt > 0 ? (initAmt - (initAmt / 2)).toStringAsFixed(2) : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(isEditing ? 'Edit Expense' : 'Add Expense', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(nameController, 'Expense Name', LucideIcons.fileText, enabled: !isSubmitting),
                  _field(
                    amountController, 
                    'Amount (PKR)', 
                    LucideIcons.banknote, 
                    type: TextInputType.number, 
                    enabled: !isSubmitting,
                    onChanged: (val) {
                      if (paymentMethod == 'SPLIT') {
                        final total = double.tryParse(val) ?? 0;
                        cashPartController.text = (total / 2).toStringAsFixed(2);
                        onlinePartController.text = (total - (total / 2)).toStringAsFixed(2);
                      }
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                    onChanged: isSubmitting ? null : (v) {
                      setDialogState(() {
                        selectedCategory = v!;
                        isCustomCategory = v == '+ Add Custom';
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(LucideIcons.tag, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: _kBg,
                      contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                    ),
                    items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.outfit()))).toList(),
                  ),
                  if (isCustomCategory) ...[
                    const SizedBox(height: 12),
                    _field(customCategoryCtrl, 'Custom Category Name', LucideIcons.tag, enabled: !isSubmitting),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: (paymentMethod == 'ONLINE' || paymentMethod == 'SPLIT') ? paymentMethod : 'CASH',
                    style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                    onChanged: isSubmitting ? null : (v) {
                      setDialogState(() {
                        paymentMethod = v ?? 'CASH';
                        if (paymentMethod == 'SPLIT') {
                          final t = double.tryParse(amountController.text) ?? 0;
                          cashPartController.text = (t / 2).toStringAsFixed(2);
                          onlinePartController.text = (t - (t / 2)).toStringAsFixed(2);
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Payment Method *',
                      prefixIcon: Icon(LucideIcons.creditCard, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: _kBg,
                      contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CASH', child: Text('Cash Drawer')),
                      DropdownMenuItem(value: 'ONLINE', child: Text('Online / Bank / Wallet')),
                      DropdownMenuItem(value: 'SPLIT', child: Text('Split (Cash + Online)')),
                    ],
                  ),
                  if (paymentMethod == 'ONLINE' || paymentMethod == 'SPLIT') ...[
                    const SizedBox(height: 12),
                    Consumer(
                      builder: (context, ref, _) {
                        final accountsAsync = ref.watch(paymentAccountsProvider);
                        final accounts = accountsAsync.maybeWhen(
                          data: (list) => list.where((a) => a.isActive).toList(),
                          orElse: () => <PaymentAccount>[],
                        );

                        if (accounts.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(LucideIcons.alertTriangle, color: Color(0xFFD97706), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No active bank accounts found. Please configure in Settings > Payment Accounts.',
                                    style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF92400E)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        if (selectedPaymentAccountId == null && accounts.isNotEmpty) {
                          selectedPaymentAccountId = accounts.first.id;
                        }

                        return DropdownButtonFormField<String>(
                          value: selectedPaymentAccountId,
                          style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                          decoration: InputDecoration(
                            labelText: paymentMethod == 'SPLIT' ? 'Online Bank Account (for split portion) *' : 'Select Bank / Wallet Account *',
                            prefixIcon: Icon(LucideIcons.landmark, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: _kBg,
                            contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                          ),
                          items: accounts.map((a) {
                            final icon = a.type == 'WALLET' ? LucideIcons.smartphone : LucideIcons.landmark;
                            return DropdownMenuItem<String>(
                              value: a.id,
                              child: Row(
                                children: [
                                  Icon(icon, size: 14, color: _kPrimary),
                                  const SizedBox(width: 8),
                                  Text(
                                    a.accountNumber != null && a.accountNumber!.isNotEmpty
                                        ? '${a.accountName} (${a.accountNumber})'
                                        : a.accountName,
                                    style: GoogleFonts.outfit(fontSize: 13),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: isSubmitting ? null : (v) => setDialogState(() => selectedPaymentAccountId = v),
                        );
                      },
                    ),
                  ],
                  if (paymentMethod == 'SPLIT') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cashPartController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.outfit(fontSize: 13),
                            onChanged: (val) {
                              final total = double.tryParse(amountController.text) ?? 0;
                              final cash = double.tryParse(val) ?? 0;
                              onlinePartController.text = (total - cash).toStringAsFixed(2);
                            },
                            decoration: InputDecoration(
                              labelText: 'Cash Part',
                              prefixText: 'PKR ',
                              filled: true,
                              fillColor: _kBg,
                              contentPadding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                              labelStyle: GoogleFonts.outfit(fontSize: 12, color: Colors.black38),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: onlinePartController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.outfit(fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Online Part',
                              prefixText: 'PKR ',
                              filled: true,
                              fillColor: _kBg,
                              contentPadding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                              labelStyle: GoogleFonts.outfit(fontSize: 12, color: Colors.black38),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: isSubmitting ? null : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setDialogState(() => selectedDate = picked);
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
                            child: Text(
                              'Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.w600)),
            ),
            Consumer(
              builder: (context, ref, child) {
                final isLoading = ref.watch(expenseControllerProvider).isLoading;
                final ledgerAsync = ref.watch(ledgerProvider(const LedgerParams()));
                final cashBalance = ledgerAsync.maybeWhen(
                  data: (d) => double.tryParse(d['summary']?['balance']?.toString() ?? '0') ?? 0.0,
                  orElse: () => 0.0,
                );

                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          try {
                            final finalCat = isCustomCategory ? customCategoryCtrl.text.trim() : selectedCategory;
                            
                            if (nameController.text.trim().isEmpty) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please enter an expense name', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
                              return;
                            }
                            final amt = double.tryParse(amountController.text) ?? 0;
                            if (amt <= 0) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please enter a valid amount', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
                              return;
                            }
                            if (finalCat.isEmpty) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please enter a category name', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
                              return;
                            }

                            double cashAmt = amt;
                            double onlineAmt = 0;
                            if (paymentMethod == 'ONLINE') {
                              cashAmt = 0;
                              onlineAmt = amt;
                            } else if (paymentMethod == 'SPLIT') {
                              cashAmt = double.tryParse(cashPartController.text) ?? 0;
                              onlineAmt = double.tryParse(onlinePartController.text) ?? 0;
                              if (cashAmt + onlineAmt <= 0) {
                                cashAmt = amt / 2;
                                onlineAmt = amt - cashAmt;
                              }
                            }

                            if ((paymentMethod == 'ONLINE' || (paymentMethod == 'SPLIT' && onlineAmt > 0)) && (selectedPaymentAccountId == null || selectedPaymentAccountId!.isEmpty)) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                                  content: Text('Please select a bank or wallet account for the online payment.', style: TextStyle(color: Colors.white)),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ));
                              }
                              return;
                            }

                            if (cashAmt > cashBalance && cashAmt > 0) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                                  content: Text('Warning: Cash Drawer balance is lower than cash expense.', style: TextStyle(color: Colors.white)),
                                  backgroundColor: Colors.orangeAccent,
                                  behavior: SnackBarBehavior.floating,
                                ));
                              }
                            }
                            
                            final data = {
                              'name': nameController.text.trim(),
                              'amount': amt,
                              'category': finalCat,
                              'date': selectedDate.toIso8601String().split('T')[0],
                              'paymentMethod': paymentMethod,
                              'paymentAccountId': (paymentMethod == 'ONLINE' || (paymentMethod == 'SPLIT' && onlineAmt > 0)) ? selectedPaymentAccountId : null,
                              if (paymentMethod == 'SPLIT') 'cashAmount': cashAmt,
                              if (paymentMethod == 'SPLIT') 'onlineAmount': onlineAmt,
                            };
                            
                            if (isEditing) {
                              await ref.read(expenseControllerProvider.notifier).updateExpense(expense['id'], data);
                            } else {
                              await ref.read(expenseControllerProvider.notifier).addExpense(data);
                            }
                            // Also refresh ledger and payment accounts
                            ref.invalidate(ledgerProvider);
                            ref.invalidate(expensesProvider);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(isEditing ? 'Update' : 'Save', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    if (user?['role'] == 'STAFF') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(child: Text('You do not have permission to view expenses.')),
      );
    }

    final filter = ExpenseFilter(start: _startDate, end: _endDate);
    final expensesAsync = ref.watch(expensesProvider(filter));

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('Expense Management', style: GoogleFonts.outfit(color: _kDark, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(expensesProvider(filter)),
            icon: const Icon(LucideIcons.refreshCcw, size: 20, color: Colors.black38),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: expensesAsync.when(
              data: (data) => Column(
                children: [
                  _buildSummary(data),
                  Expanded(child: _buildList(data)),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator(color: _kPrimary)),
              error: (e, _) => Center(child: Text('Error: $e', style: GoogleFonts.outfit(color: Colors.redAccent))),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddExpenseDialog(),
        backgroundColor: _kPrimary,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: _dateChip(
              'From',
              _startDate,
              () async {
                final d = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime(2022), lastDate: DateTime.now());
                if (d != null) setState(() => _startDate = d);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _dateChip(
              'To',
              _endDate,
              () async {
                final d = await showDatePicker(context: context, initialDate: _endDate, firstDate: DateTime(2022), lastDate: DateTime.now());
                if (d != null) setState(() => _endDate = d);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateChip(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(LucideIcons.calendar, size: 14, color: _kPrimary),
                const SizedBox(width: 8),
                Text(DateFormat('MMM dd, yyyy').format(date), style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kDark)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(List data) {
    double total = 0;
    for (var e in data) {
      total += double.tryParse(e['amount']?.toString() ?? '0') ?? 0;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kDark,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: _kDark.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Monthly Expenses', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            'PKR ${total.toStringAsFixed(0)}',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildList(List data) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.receipt, size: 48, color: Colors.black12),
            const SizedBox(height: 16),
            Text('No expenses recorded yet', style: GoogleFonts.outfit(color: Colors.black38)),
          ],
        ),
      );
    }

    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? [];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        final expense = data[i];
        final amount = double.tryParse(expense['amount']?.toString() ?? '0') ?? 0;
        final date = DateTime.parse(expense['date']).toLocal();
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _getCategoryIcon(expense['category']),
            title: Text(expense['name'] ?? 'Unknown', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  '${expense['category']} • ${DateFormat('MMM dd, yyyy').format(date)}',
                  style: GoogleFonts.outfit(color: Colors.black38, fontSize: 12),
                ),
                const SizedBox(height: 4),
                _buildPaymentBadge(expense, accounts),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PKR ${amount.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(LucideIcons.edit2, size: 16, color: Colors.indigo),
                  onPressed: () => _showAddExpenseDialog(expense),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Edit',
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent),
                  onPressed: () => _confirmDelete(expense['id']),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ).animate().fadeIn(delay: (i * 50).ms).slideX(begin: 0.1);
      },
    );
  }

  Widget _getCategoryIcon(String? category) {
    IconData icon;
    Color color;
    switch (category) {
      case 'Salary':
        icon = LucideIcons.userCheck;
        color = Colors.blue;
        break;
      case 'Wages':
        icon = LucideIcons.banknote;
        color = Colors.teal;
        break;
      case 'Bills':
        icon = LucideIcons.lightbulb;
        color = Colors.orange;
        break;
      case 'Rent':
        icon = LucideIcons.home;
        color = Colors.purple;
        break;
      case 'Supplies':
        icon = LucideIcons.shoppingBag;
        color = Colors.indigo;
        break;
      default:
        icon = LucideIcons.moreHorizontal;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildPaymentBadge(Map<String, dynamic> expense, List<PaymentAccount> accounts) {
    final method = (expense['paymentMethod']?.toString() ?? 'CASH').toUpperCase();
    final accountId = expense['paymentAccountId']?.toString() ?? expense['paymentAccount']?['id']?.toString();
    String? accountName = expense['paymentAccount']?['accountName']?.toString();
    if (accountName == null && accountId != null) {
      final matched = accounts.where((a) => a.id == accountId).toList();
      if (matched.isNotEmpty) {
        accountName = matched.first.accountName;
      }
    }

    Color bg;
    Color fg;
    IconData icon;
    String label;

    if (method == 'SPLIT') {
      bg = Colors.purple.withValues(alpha: 0.1);
      fg = Colors.purple.shade700;
      icon = LucideIcons.split;
      label = accountName != null ? 'Split (Cash + $accountName)' : 'Split Payment';
    } else if (method == 'ONLINE' || method == 'CARD' || method == 'BANK_TRANSFER' || method == 'BANK') {
      bg = Colors.blue.withValues(alpha: 0.1);
      fg = Colors.blue.shade700;
      icon = LucideIcons.landmark;
      label = accountName ?? 'Online Bank';
    } else {
      bg = Colors.green.withValues(alpha: 0.1);
      fg = Colors.green.shade700;
      icon = LucideIcons.banknote;
      label = 'Cash Drawer';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete Expense?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
        content: SizedBox(
          width: 500,
          child: Text('Are you sure you want to remove this expense record?', style: GoogleFonts.outfit()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black45)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              ref.read(expenseControllerProvider.notifier).deleteExpense(id);
              Navigator.pop(ctx);
            },
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? type, bool enabled = true, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        enabled: enabled,
        onChanged: onChanged,
        style: GoogleFonts.outfit(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon:
              Icon(icon, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
          filled: true,
          fillColor: _kBg,
          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
        ),
      ),
    );
  }
}
