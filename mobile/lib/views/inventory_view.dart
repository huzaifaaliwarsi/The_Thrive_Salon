import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../providers/inventory_provider.dart';
import '../providers/auth_provider.dart';
import 'ledger_view.dart';
import '../providers/ledger_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/reports_provider.dart';
import '../view_models/dashboard_view_model.dart';

const _kPrimary = Color(0xFF6A11CB);
const _kDark = Color(0xFF1B1B3A);
const _kBg = Color(0xFFF4F6FB);

class InventoryView extends ConsumerStatefulWidget {
  const InventoryView({super.key});

  @override
  ConsumerState<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends ConsumerState<InventoryView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider);
    final isStaff = user?['role'] == 'STAFF';
    _tabController = TabController(length: isStaff ? 1 : 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isStaff = user?['role'] == 'STAFF';
    final tabCount = isStaff ? 1 : 2;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('Inventory & Stock'),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              const Tab(text: 'Products'),
              if (!isStaff) const Tab(text: 'Suppliers'),
            ],
          ),
          actions: [
            if (!isStaff)
              IconButton(
                icon: const Icon(LucideIcons.book, color: Colors.indigo),
                tooltip: 'Salon Ledger',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LedgerView(title: 'Salon Ledger')),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildStockTab(),
            if (!isStaff) _buildVendorsTab(),
          ],
        ),
        floatingActionButton: isStaff && tabCount == 1 
          ? null // Staff can only view stock, not add/manage vendors
          : FloatingActionButton(
              onPressed: () {
                if (isStaff) return; 

                if (_tabController.index == 0) {
                  _showAddItemDialog();
                } else {
                  _showAddVendorDialog();
                }
              },
              child: const Icon(LucideIcons.plus),
            ),
      ),
    );
  }

  Widget _buildStockTab() {
    final inventoryAsync = ref.watch(inventoryProvider);
    final user = ref.watch(authProvider);
    final isStaff = user?['role'] == 'STAFF';
    return inventoryAsync.when(
      data: (items) {
        if (items.isEmpty) return const Center(child: Text('No inventory items'));
        return RefreshIndicator(
          onRefresh: () => ref.read(inventoryProvider.notifier).fetchItems(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
          padding: const EdgeInsets.all(16),
          itemBuilder: (context, index) {
            final item = items[index];
            final qty = double.tryParse(item['stockQuantity'] ?? '0') ?? 0;
            return InkWell(
              onTap: () => _showTransactionDialog(item),
              onLongPress: () => isStaff ? null : _showAddItemDialog(item),
              borderRadius: BorderRadius.circular(16),
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(LucideIcons.package, color: _kPrimary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text('Supplier: ${item['vendor']?['name'] ?? 'None'}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Cost: ${item['unitPrice']}',
                                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Sell: ${item['sellingPrice']}',
                                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: (qty <= (double.tryParse(item['lowStockThreshold']?.toString() ?? '5') ?? 5) ? Colors.red : Colors.green).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              qty.toStringAsFixed(0),
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: qty <= (double.tryParse(item['lowStockThreshold']?.toString() ?? '5') ?? 5) ? Colors.red : Colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('In Stock', style: GoogleFonts.outfit(fontSize: 10, color: Colors.black26, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      if (!isStaff) ...[
                        const SizedBox(width: 16),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.arrowUpDown, size: 16, color: Colors.teal),
                              onPressed: () => _showTransactionDialog(item),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              tooltip: 'Transaction',
                            ),
                            const SizedBox(height: 8),
                            IconButton(
                              icon: const Icon(LucideIcons.edit2, size: 16, color: Colors.indigo),
                              onPressed: () => _showAddItemDialog(item),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              tooltip: 'Edit',
                            ),
                            const SizedBox(height: 8),
                            IconButton(
                              icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent),
                              onPressed: () => _showDeleteItemDialog(item),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
    loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildVendorsTab() {
    final vendorsAsync = ref.watch(vendorsProvider);
    return vendorsAsync.when(
      data: (vendors) {
        if (vendors.isEmpty) return const Center(child: Text('No vendors listed'));
        return RefreshIndicator(
          onRefresh: () => ref.refresh(vendorsProvider.future),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: vendors.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
            final vendor = vendors[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(LucideIcons.truck)),
                title: Text(vendor['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vendor['phone'] ?? 'No contact info'),
                    if (vendor['balance'] != null && double.parse(vendor['balance'].toString()) != 0)
                      Text(
                        'Payable: PKR ${vendor['balance']}',
                        style: TextStyle(
                          color: double.parse(vendor['balance'].toString()) > 0 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Consumer(builder: (context, ref, _) {
                      final items = ref.watch(inventoryProvider).value ?? [];
                      final vendorItems = items.where((i) => i['vendorId'] == vendor['id']).toList();
                      if (vendorItems.isEmpty) return const SizedBox();
                      return Text(
                        'Products: ${vendorItems.map((i) => i['name']).join(', ')}',
                        style: GoogleFonts.outfit(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    }),
                  ],
                ),
                trailing: Consumer(builder: (context, ref, _) {
                  final user = ref.watch(authProvider);
                  final isOwner = user?['role'] == 'OWNER';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.book, color: Colors.indigo, size: 20),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LedgerView(
                              vendorId: vendor['id'],
                              title: '${vendor['name']}\'s Ledger',
                            ),
                          ),
                        ),
                      ),
                      if (isOwner) ...[
                        IconButton(
                          icon: const Icon(LucideIcons.edit2, size: 18),
                          onPressed: () => _showAddVendorDialog(vendor),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                          onPressed: () => _showDeleteVendorDialog(vendor),
                        ),
                      ],
                    ],
                  );
                }),
              ),
            );
          },
        ),
      );
    },
    loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _showAddItemDialog([Map<String, dynamic>? existingItem]) {
    final isEdit = existingItem != null;
    final nameController = TextEditingController(text: existingItem?['name']);
    final unitController = TextEditingController(text: existingItem?['unit'] ?? 'units');
    final priceController = TextEditingController(text: existingItem?['unitPrice']?.toString());
    final sellingPriceController = TextEditingController(text: existingItem?['sellingPrice']?.toString());
    final stockController = TextEditingController(text: existingItem?['stockQuantity']?.toString() ?? '0');
    final thresholdController = TextEditingController(text: existingItem?['lowStockThreshold']?.toString() ?? '5');
    bool showInPOS = existingItem?['canBeSold']?.toString() == 'true';
    DateTime? selectedExpiry = existingItem?['expiryDate'] != null ? DateTime.parse(existingItem!['expiryDate']) : null;
    String? selectedVendorId = existingItem?['vendorId'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final vendorsAsync = ref.watch(vendorsProvider);
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(isEdit ? 'Edit Item' : 'New Inventory Item', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _field(nameController, 'Product Name', LucideIcons.package),
                      _field(unitController, 'Unit (e.g. ml, pcs, bottles)', LucideIcons.scale),
                      _field(priceController, 'Purchase Amount / Unit Price', LucideIcons.banknote, type: TextInputType.number),
                      _field(sellingPriceController, 'Selling Price (for POS)', LucideIcons.tag, type: TextInputType.number),
                      SwitchListTile(
                        title: Text('Show in POS', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                        value: showInPOS, 
                        onChanged: (val) => setDialogState(() => showInPOS = val),
                        activeColor: _kPrimary,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      if (!isEdit)
                        _field(stockController, 'Initial Stock', LucideIcons.archive, type: TextInputType.number),
                      _field(thresholdController, 'Low Stock Alert At', LucideIcons.alertTriangle, type: TextInputType.number),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedExpiry ?? DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedExpiry = picked);
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
                                child: Text(
                                  selectedExpiry == null
                                      ? 'Set Expiry Date'
                                      : 'Expiry: ${DateFormat('yyyy-MM-dd').format(selectedExpiry!)}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    color: selectedExpiry == null ? Colors.black38 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      vendorsAsync.when(
                        data: (vendors) => DropdownButtonFormField<String>(
                          value: selectedVendorId,
                          style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                          decoration: InputDecoration(
                            labelText: 'Supplier Name',
                            prefixIcon: Icon(LucideIcons.truck, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: _kBg,
                            contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                          ),
                          items: vendors.map<DropdownMenuItem<String>>((v) {
                            return DropdownMenuItem(value: v['id'], child: Text(v['name'], style: GoogleFonts.outfit()));
                          }).toList(),
                          onChanged: (val) => selectedVendorId = val,
                        ),
                        loading: () => const CircularProgressIndicator(),
                        error: (_, __) => const Text('Error loading suppliers'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: Text('Cancel', style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Product Name is required'),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }
                    final unitPrice = double.tryParse(priceController.text.replaceAll(',', '')) ?? 0;
                    final sellingPrice = double.tryParse(sellingPriceController.text.replaceAll(',', '')) ?? 0;
                    if (unitPrice < 0 || sellingPrice < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Prices cannot be negative'),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }
                    if (sellingPrice < unitPrice && showInPOS) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Selling price cannot be less than purchase unit price'),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }
                    try {
                      final data = {
                        'name': nameController.text,
                        'unit': unitController.text,
                        'unitPrice': double.tryParse(priceController.text.replaceAll(',', '')) ?? 0,
                        'sellingPrice': double.tryParse(sellingPriceController.text.replaceAll(',', '')) ?? 0,
                        'canBeSold': showInPOS ? 'true' : 'false',
                        'initialStock': double.tryParse(stockController.text.replaceAll(',', '')) ?? 0,
                        'lowStockThreshold': double.tryParse(thresholdController.text) ?? 5,
                        'expiryDate': selectedExpiry != null ? DateFormat('yyyy-MM-dd').format(selectedExpiry!) : null,
                        'vendorId': selectedVendorId,
                      };

                      if (isEdit) {
                        await ref.read(apiServiceProvider).updateInventoryItem(existingItem['id'], data);
                        ref.read(inventoryProvider.notifier).fetchItems();
                      } else {
                        await ref.read(inventoryProvider.notifier).addItem(data);
                      }
                      Navigator.pop(context);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text(
                    isEdit ? 'Save' : 'Add',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _showAddVendorDialog([Map<String, dynamic>? vendor]) {
    final nameController = TextEditingController(text: vendor?['name']);
    final phoneController = TextEditingController(text: vendor?['phone']);
    final personController = TextEditingController(text: vendor?['contactPerson']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(vendor == null ? 'Add Supplier' : 'Edit Supplier', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(nameController, 'Supplier Name', LucideIcons.truck),
              _field(personController, 'Contact Person / Representative', LucideIcons.user),
              _field(phoneController, 'Contact Number / Phone', LucideIcons.phone),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: Text('Cancel', style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Supplier Name is required'),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              try {
                final data = {
                  'name': nameController.text,
                  'contactPerson': personController.text,
                  'phone': phoneController.text,
                };
                if (vendor == null) {
                  await ref.read(apiServiceProvider).createVendor(data);
                } else {
                  await ref.read(apiServiceProvider).updateVendor(vendor['id'], data);
                }
                ref.invalidate(vendorsProvider);
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showTransactionDialog(Map<String, dynamic> item) {
    final qtyController = TextEditingController();
    final paidController = TextEditingController();
    final cashPartController = TextEditingController();
    final onlinePartController = TextEditingController();
    final notesController = TextEditingController();
    final oneTimeNameController = TextEditingController();
    final oneTimePhoneController = TextEditingController();
    final oneTimeDetailsController = TextEditingController();
    String type = 'IN';
    String paymentMethod = 'CASH';
    String? selectedVendorId = item['vendorId'];
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Stock Transaction: ${item['name']}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('Stock In (Purchase)')),
                    DropdownMenuItem(value: 'OUT', child: Text('Stock Out (Internal Use)')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v!),
                  decoration: InputDecoration(
                    labelText: 'Type *',
                    prefixIcon: Icon(LucideIcons.package, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: _kBg,
                    contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                  ),
                ),
                const SizedBox(height: 12),
                _field(qtyController, 'Quantity (${item['unit']})', LucideIcons.archive, type: TextInputType.number, onChanged: (_) => setDialogState(() {})),
                if (type == 'IN') ...[
                  const SizedBox(height: 12),
                  Consumer(builder: (context, ref, _) {
                    final vendors = ref.watch(vendorsProvider).value ?? [];
                    return DropdownButtonFormField<String>(
                      value: selectedVendorId,
                      style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                      decoration: InputDecoration(
                        labelText: 'Supplier Name',
                        prefixIcon: Icon(LucideIcons.truck, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: _kBg,
                        contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                      ),
                      items: [
                        DropdownMenuItem(value: null, child: Text('One-time / Cash Supplier', style: GoogleFonts.outfit())),
                        ...vendors.map<DropdownMenuItem<String>>((v) => DropdownMenuItem(value: v['id'], child: Text(v['name'], style: GoogleFonts.outfit()))).toList(),
                      ],
                      onChanged: (v) => setDialogState(() => selectedVendorId = v),
                    );
                  }),
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final qty = double.tryParse(qtyController.text) ?? 0;
                    final unitPrice = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
                    final total = qty * unitPrice;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated Total: PKR ${total.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: paidController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.outfit(fontSize: 14),
                            onChanged: (_) {
                              final pTotal = double.tryParse(paidController.text) ?? total;
                              if (paymentMethod == 'SPLIT') {
                                cashPartController.text = (pTotal / 2).toStringAsFixed(2);
                                onlinePartController.text = (pTotal - (pTotal / 2)).toStringAsFixed(2);
                              }
                              setDialogState(() {});
                            },
                            decoration: InputDecoration(
                              labelText: 'Amount Paid (Leave empty if fully paid)',
                              prefixText: 'PKR ',
                              prefixIcon: Icon(LucideIcons.banknote, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                              filled: true,
                              fillColor: _kBg,
                              contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                              labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: paymentMethod,
                    style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
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
                      DropdownMenuItem(value: 'ONLINE', child: Text('Online / Bank / Card')),
                      DropdownMenuItem(value: 'SPLIT', child: Text('Split (Cash + Online)')),
                    ],
                    onChanged: (v) {
                      setDialogState(() {
                        paymentMethod = v ?? 'CASH';
                        if (paymentMethod == 'SPLIT') {
                          final qty = double.tryParse(qtyController.text) ?? 0;
                          final unitPrice = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
                          final total = qty * unitPrice;
                          final pTotal = double.tryParse(paidController.text) ?? total;
                          cashPartController.text = (pTotal / 2).toStringAsFixed(2);
                          onlinePartController.text = (pTotal - (pTotal / 2)).toStringAsFixed(2);
                        }
                      });
                    },
                  ),
                  if (paymentMethod == 'SPLIT') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cashPartController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.outfit(fontSize: 13),
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
                  Builder(builder: (context) {
                    final qty = double.tryParse(qtyController.text) ?? 0;
                    final unitPrice = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
                    final total = qty * unitPrice;
                    final paidVal = double.tryParse(paidController.text) ?? total;
                    final isPartial = paidVal < total;
                    if (selectedVendorId == null && isPartial) {
                      return Column(
                        children: [
                          _field(oneTimeNameController, 'One-time Supplier Name *', LucideIcons.user),
                          _field(oneTimePhoneController, 'Supplier Phone', LucideIcons.phone, type: TextInputType.phone),
                          _field(oneTimeDetailsController, 'Supplier Details', LucideIcons.info),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                ],
                _field(notesController, 'Notes (Optional)', LucideIcons.fileText),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text('Cancel', style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.w600)),
            ),
            Consumer(
              builder: (context, ref, _) {
                final ledgerAsync = ref.watch(ledgerProvider(const LedgerParams()));
                final cashBalance = ledgerAsync.maybeWhen(
                  data: (d) => double.tryParse(d['summary']?['balance']?.toString() ?? '0') ?? 0.0,
                  orElse: () => 0.0,
                );
                final metricsAsync = ref.watch(dashboardMetricsProvider);
                final onlineBalance = metricsAsync.maybeWhen(
                  data: (m) => double.tryParse((m['onlineBalance'] ?? m['onlineDrawerBalance'])?.toString() ?? '0') ?? 0.0,
                  orElse: () => 0.0,
                );
                return ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    final qtyStr = qtyController.text.trim();
                    if (qtyStr.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Quantity is required'),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }
                    final qty = double.tryParse(qtyStr);
                    if (qty == null || qty <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Please enter a valid positive quantity'),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }

                    final unitPrice = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
                    final total = qty * unitPrice;
                    final amountPaid = double.tryParse(paidController.text) ?? total;
                    if (amountPaid < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Amount paid cannot be negative'),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }

                    double cashAmt = 0;
                    double onlineAmt = 0;
                    if (paymentMethod == 'SPLIT') {
                      cashAmt = double.tryParse(cashPartController.text) ?? (amountPaid / 2);
                      onlineAmt = double.tryParse(onlinePartController.text) ?? (amountPaid - cashAmt);
                    } else if (paymentMethod == 'ONLINE') {
                      onlineAmt = amountPaid;
                    } else {
                      cashAmt = amountPaid;
                    }

                    if (type == 'IN' && amountPaid > 0) {
                      if (cashAmt > 0 && cashAmt > cashBalance) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Warning: Cash Drawer balance is low / will go negative.'),
                          backgroundColor: Colors.orangeAccent,
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                      if (onlineAmt > 0 && onlineAmt > onlineBalance) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Warning: Online Drawer / Bank balance is low.'),
                          backgroundColor: Colors.orangeAccent,
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    }

                    setDialogState(() => isSaving = true);
                    try {
                      if (type == 'IN') {
                        String? finalVendorId = selectedVendorId;

                        if (finalVendorId == null && amountPaid < total) {
                          final oneTimeName = oneTimeNameController.text.trim();
                          if (oneTimeName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Please enter the one-time supplier name'),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                            ));
                            setDialogState(() => isSaving = false);
                            return;
                          }

                          final newVendor = await ref.read(apiServiceProvider).createVendor({
                            'name': oneTimeName,
                            'phone': oneTimePhoneController.text.trim(),
                            'contactPerson': oneTimeDetailsController.text.trim(),
                          });
                          finalVendorId = newVendor['id']?.toString();
                        }

                        final chosenPaymentMethod = amountPaid <= 0 ? 'CREDIT' : paymentMethod;

                        await ref.read(apiServiceProvider).createPurchase({
                          'vendorId': finalVendorId,
                          'total': total,
                          'amountPaid': amountPaid,
                          'paymentMethod': chosenPaymentMethod,
                          'cashAmount': cashAmt,
                          'onlineAmount': onlineAmt,
                          'notes': notesController.text.isEmpty ? 'Purchase of ${item['name']}' : notesController.text,
                          'items': [
                            {'id': item['id'], 'quantity': qty, 'unitPrice': unitPrice}
                          ]
                        });
                      } else {
                        await ref.read(inventoryProvider.notifier).addTransaction({
                          'itemId': item['id'],
                          'type': type,
                          'quantity': qty,
                          'notes': notesController.text.isEmpty ? 'Manual adjustment' : notesController.text,
                        });
                      }

                      ref.invalidate(vendorsProvider);
                      ref.invalidate(ledgerProvider);
                      ref.invalidate(purchasesProvider);
                      ref.invalidate(reportsProvider);
                      ref.invalidate(dashboardMetricsProvider);
                      ref.invalidate(dashboardViewModelProvider);
                      ref.read(inventoryProvider.notifier).fetchItems();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    } finally {
                      setDialogState(() => isSaving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: isSaving 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                      : Text('Confirm', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteVendorDialog(Map<String, dynamic> vendor) {
    final balance = double.tryParse(vendor['balance']?.toString() ?? '0') ?? 0;
    final hasBalance = balance != 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(hasBalance ? 'Cannot Delete Vendor' : 'Delete Vendor?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasBalance) ...[
              Text(
                'This vendor has an outstanding balance of PKR $balance.',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 12),
              Text('Please settle the ledger first by recording a payment or nulling the balance before deleting.', style: GoogleFonts.outfit()),
            ] else
              Text('Are you sure you want to delete ${vendor['name']}? This action cannot be undone.', style: GoogleFonts.outfit()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black45)),
          ),
          if (!hasBalance)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                try {
                  await ref.read(apiServiceProvider).deleteVendor(vendor['id']);
                  ref.invalidate(vendorsProvider);
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          if (hasBalance)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LedgerView(
                      vendorId: vendor['id'],
                      title: '${vendor['name']}\'s Ledger',
                    ),
                  ),
                );
              },
              child: Text('Go to Ledger', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? type, Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
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

  void _showDeleteItemDialog(dynamic item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete Product?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
        content: Text('Are you sure you want to delete ${item['name']}? This action cannot be undone.', style: GoogleFonts.outfit()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
            onPressed: () async {
              try {
                await ref.read(apiServiceProvider).deleteInventoryItem(item['id']);
                ref.invalidate(inventoryProvider);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

