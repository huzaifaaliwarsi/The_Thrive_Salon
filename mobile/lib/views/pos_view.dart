import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../repositories/sync_repository.dart';
import '../providers/services_provider.dart';
import '../providers/staff_provider.dart';
import '../view_models/pos_view_model.dart';
import '../widgets/pos_search_field.dart';
import '../models/service_model.dart';
import '../services/api_service.dart';
import '../models/sale_model.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/reports_provider.dart';
import '../view_models/dashboard_view_model.dart';
import '../providers/clients_provider.dart';
import '../utils/pdf_invoice_generator.dart';
import '../providers/inventory_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/appointments_provider.dart';
import '../providers/ledger_provider.dart';
import '../models/payment_account.dart';
import '../providers/payment_accounts_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const _kPrimary  = Color(0xFF6A11CB);
const _kDark     = Color(0xFF1B1B3A);
const _kBg       = Color(0xFFF4F6FB);
const _kAccent   = Color(0xFF2575FC);

class POSView extends ConsumerWidget {
  const POSView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final cartCount = ref.watch(posProvider.select((s) => s.cart.fold(0, (sum, i) => sum + i.quantity)));

    if (isWide) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Row(
          children: [
            Expanded(flex: 3, child: _ServiceListSection()),
            _CartSidePanel(),
          ],
        ),
      );
    }

    // Mobile: full-width service list + FAB to open cart bottom sheet
    return Scaffold(
      backgroundColor: _kBg,
      body: const _ServiceListSection(),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 4,
        highlightElevation: 8,
        backgroundColor: _kDark,
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _CartBottomSheet(),
        ),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(LucideIcons.shoppingCart, color: Colors.white, size: 20),
            if (cartCount > 0)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEA580C)]),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Center(
                    child: Text('$cartCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        ),
        label: Text('View Cart', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ).animate().scale(delay: 400.ms, curve: Curves.easeOutBack),
    );
  }
}

class _CartBottomSheet extends StatelessWidget {
  const _CartBottomSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const _BottomSheetHandle(),
          const _CartHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const _CustomerInfoField(),
                  const _CartList(),
                  const _PaymentToggleSection(),
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
                ],
              ),
            ),
          ),
          const _CheckoutFooter(),
        ],
      ),
    );
  }
}

class _BottomSheetHandle extends StatelessWidget {
  const _BottomSheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ServiceListSection extends ConsumerWidget {
  const _ServiceListSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TopBar(),
        servicesAsync.when(
          data: (services) {
            final categories = ['All', 'Packages', ...services.map((e) => e.category).toSet()];
            return _CategoryBar(categories: categories);
          },
          loading: () => const SizedBox(height: 50),
          error: (_, __) => const SizedBox(height: 50),
        ),
        const Expanded(
          child: _FilteredServiceGrid(),
        ),
      ],
    );
  }
}

class _FilteredServiceGrid extends ConsumerWidget {
  const _FilteredServiceGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredServicesProvider);
    final isLoading = ref.watch(servicesProvider).isLoading;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    if (filtered.isEmpty) {
      return const _EmptyState();
    }

    return BeautifulScrollbar(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 0.85,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _ServiceCard(service: filtered[index], index: index),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar();

  void _showQueueDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final appointmentsAsync = ref.watch(appointmentsProvider);
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(LucideIcons.listTodo, color: _kAccent),
                  const SizedBox(width: 8),
                  Text('Pending Checkouts Queue', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Container(
                width: 400,
                constraints: const BoxConstraints(maxHeight: 400),
                child: appointmentsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('Error: $err')),
                  data: (list) {
                    final queue = list.where((app) => app['status'] == 'PENDING_CHECKOUT').toList();
                    if (queue.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.smile, size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('No pending checkouts in queue', style: GoogleFonts.outfit(color: Colors.black38)),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: queue.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, idx) {
                        final app = queue[idx];
                        final customerName = app['customerName'] ?? 'Walk-in';
                        final customerPhone = app['customerPhone'] ?? '-';
                        final time = DateTime.tryParse(app['appointmentTime']?.toString() ?? '')?.toLocal();
                        final formattedTime = time != null ? DateFormat('hh:mm a').format(time) : 'N/A';
                        
                        final List<dynamic> services = app['services'] ?? [];
                        final servicesStr = services.map((s) => s['name']?.toString() ?? '').join(', ');

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(customerName, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Time: $formattedTime • Phone: $customerPhone', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54)),
                              if (servicesStr.isNotEmpty)
                                Text('Services: $servicesStr', style: GoogleFonts.outfit(fontSize: 11, color: _kPrimary, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              ref.read(posProvider.notifier).loadAppointment(app);
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Loaded $customerName\'s appointment into checkout!'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              elevation: 0,
                            ),
                            child: Text('Process', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final appointmentsAsync = ref.watch(appointmentsProvider);
    final queueCount = appointmentsAsync.value?.where((app) => app['status'] == 'PENDING_CHECKOUT').length ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, isWide ? 40 : 20, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick POS', style: GoogleFonts.outfit(fontSize: 13, color: Colors.black45, fontWeight: FontWeight.w500)),
                  Text('Select Services', style: GoogleFonts.outfit(fontSize: isWide ? 28 : 22, fontWeight: FontWeight.bold, color: _kDark)),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showQueueDialog(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.listTodo, size: 18, color: _kAccent),
                      const SizedBox(width: 6),
                      Text('Queue', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kAccent)),
                      if (queueCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$queueCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showDraftsDialog(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.fileText, size: 18, color: _kPrimary),
                      const SizedBox(width: 6),
                      Text('Drafts', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kPrimary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final servicesList = ref.read(servicesProvider).whenOrNull(data: (d) => d) ?? [];
                  _showAddServiceDialog(context, ref, servicesList);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.search, size: 18, color: _kPrimary),
                      const SizedBox(width: 6),
                      Text('Search', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kPrimary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 4))],
            ),
            child: const POSSearchField(),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends ConsumerWidget {
  final List<String> categories;
  const _CategoryBar({required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategory = ref.watch(posProvider.select((s) => s.selectedCategory));
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => ref.read(posProvider.notifier).setCategory(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  gradient: isSelected ? const LinearGradient(colors: [_kPrimary, _kAccent]) : null,
                  color: isSelected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected ? [BoxShadow(color: _kPrimary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  cat,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black45,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CartSidePanel extends ConsumerWidget {
  const _CartSidePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 30, offset: const Offset(-10, 0))],
      ),
      child: Column(
        children: [
          const _CartHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const _CustomerInfoField(),
                  const _CartList(),
                  const _PaymentToggleSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          const _CheckoutFooter(),
        ],
      ),
    );
  }
}

class _CartHeader extends ConsumerWidget {
  const _CartHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasItems = ref.watch(posProvider.select((s) =>
        s.cart.isNotEmpty ||
        s.customerName.isNotEmpty ||
        s.customerPhone.isNotEmpty ||
        s.draftId != null ||
        s.appointmentId != null));
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.shoppingBag, color: _kPrimary, size: 20),
          ),
          const SizedBox(width: 14),
          Text(
            'Your Order',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _kDark,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          if (hasItems)
            TextButton.icon(
              onPressed: () => ref.read(posProvider.notifier).clear(),
              icon: const Icon(LucideIcons.rotateCcw, size: 14, color: Colors.redAccent),
              label: Text(
                'Reset',
                style: GoogleFonts.outfit(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                backgroundColor: Colors.redAccent.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerInfoField extends ConsumerStatefulWidget {
  const _CustomerInfoField();

  @override
  ConsumerState<_CustomerInfoField> createState() => _CustomerInfoFieldState();
}

class _CustomerInfoFieldState extends ConsumerState<_CustomerInfoField> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = ref.read(posProvider);
    _phoneController.text = state.customerPhone;
    _nameController.text = state.customerName;
  }

  @override
  Widget build(BuildContext context) {
    // Listen for state changes to sync controllers when cart is cleared or updated from outside (e.g. loaded draft or appointment)
    ref.listen(posProvider, (prev, next) {
      if (next.customerPhone != _phoneController.text) {
        _phoneController.text = next.customerPhone;
      }
      if (next.customerName != _nameController.text) {
        _nameController.text = next.customerName;
      }
    });

    final clientsAsync = ref.watch(clientsProvider);
    final phone = ref.watch(posProvider.select((s) => s.customerPhone));
    final name = ref.watch(posProvider.select((s) => s.customerName));

    Widget? balanceWidget;
    clientsAsync.whenData((clients) {
      final match = clients.firstWhere(
        (c) => (phone.isNotEmpty && c['phone'] == phone) ||
               (phone.isEmpty && name.isNotEmpty && c['name'] == name),
        orElse: () => null,
      );
      if (match != null) {
        final bal = double.tryParse(match['balance']?.toString() ?? '0') ?? 0.0;
        if (bal > 0) {
          balanceWidget = Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertTriangle, size: 14, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Outstanding Debt: PKR ${bal.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          );
        } else if (bal < 0) {
          balanceWidget = Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.checkCircle, size: 14, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Advance Credit: PKR ${(-bal).toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          );
        }
      }
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildField(
            controller: _nameController,
            label: 'Customer Name',
            icon: LucideIcons.user,
            onChanged: (v) => ref.read(posProvider.notifier).setCustomerName(v),
            suffix: IconButton(
              icon: const Icon(LucideIcons.search, size: 18, color: _kPrimary),
              onPressed: () => _showClientSearchDialog(context),
            ),
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _phoneController,
            label: 'Phone Number',
            icon: LucideIcons.phone,
            keyboard: TextInputType.phone,
            onChanged: (v) => ref.read(posProvider.notifier).setCustomerPhone(v),
          ),
          if (balanceWidget != null) balanceWidget!,
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'How Customer Came',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black45,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSourceChip('Walk-in', 'WALK_IN', LucideIcons.userCheck),
              _buildSourceChip('Referral', 'REFERRAL', LucideIcons.users),
              _buildSourceChip('Social Media', 'SOCIAL_MEDIA', LucideIcons.share2),
              _buildSourceChip('Other', 'OTHER', LucideIcons.helpCircle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(String label, String value, IconData icon) {
    final selectedSource = ref.watch(posProvider.select((s) => s.customerSource));
    final isSelected = selectedSource == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected ? Colors.white : Colors.black45,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.black54,
            ),
          ),
        ],
      ),
      selected: isSelected,
      selectedColor: _kPrimary,
      backgroundColor: const Color(0xFFF8F9FD),
      checkmarkColor: Colors.white,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? _kPrimary : Colors.black.withValues(alpha: 0.05)),
      ),
      onSelected: (selected) {
        if (selected) {
          ref.read(posProvider.notifier).setCustomerSource(value);
        }
      },
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Function(String) onChanged,
    TextInputType keyboard = TextInputType.text,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: keyboard,
        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: _kDark),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.outfit(fontSize: 13, color: Colors.black38, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, size: 18, color: Colors.black26),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }

  void _showClientSearchDialog(BuildContext context) {
    final clientsAsync = ref.read(clientsProvider);
    clientsAsync.whenData((clients) {
      showDialog(
        context: context,
        builder: (context) {
          List filteredClients = List.from(clients);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text('Search Clients', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                content: Container(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name or phone...',
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (v) {
                          setDialogState(() {
                            filteredClients = clients.where((c) => 
                              c['name'].toLowerCase().contains(v.toLowerCase()) ||
                              (c['phone']?.contains(v) ?? false)
                            ).toList();
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredClients.length,
                          itemBuilder: (context, index) {
                            final client = filteredClients[index];
                            return ListTile(
                              title: Text(client['name'], style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                              subtitle: Text(client['phone'] ?? 'No phone'),
                              trailing: () {
                                final bal = double.tryParse(client['balance']?.toString() ?? '0') ?? 0.0;
                                if (bal > 0) {
                                  return Text('Debt: PKR ${bal.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12));
                                } else if (bal < 0) {
                                  return Text('Credit: PKR ${(-bal).toStringAsFixed(0)}', style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12));
                                }
                                return null;
                              }(),
                              onTap: () {
                                ref.read(posProvider.notifier).setCustomerName(client['name']);
                                ref.read(posProvider.notifier).setCustomerPhone(client['phone'] ?? '');
                                ref.read(posProvider.notifier).setCustomerSource(client['source'] ?? 'WALK_IN');
                                setState(() {
                                  _nameController.text = client['name'];
                                  _phoneController.text = client['phone'] ?? '';
                                });
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          );
        },
      );
    });
  }
}

class _CartList extends ConsumerWidget {
  const _CartList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(posProvider.select((s) => s.cart));
    final nameMap = ref.watch(posProvider.select((s) => s.serviceNameMap));
    final servicesList = ref.watch(servicesProvider).whenOrNull(data: (d) => d) ?? [];
    
    if (cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: _kBg, shape: BoxShape.circle),
              child: Icon(LucideIcons.shoppingCart, size: 40, color: Colors.black.withValues(alpha: 0.05)),
            ),
            const SizedBox(height: 16),
            Text('No items in cart', style: GoogleFonts.outfit(color: Colors.black26, fontSize: 15)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _showAddServiceDialog(context, ref, servicesList),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text('Add Service', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kPrimary,
                side: const BorderSide(color: _kPrimary, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Column(
        children: [
          ...List.generate(cart.length, (index) {
            final item = cart[index];
            final name = nameMap[item.serviceId] ?? 'Unknown Item';
            final service = servicesList.firstWhere(
              (s) => s.id == item.serviceId, 
              orElse: () => Service(id: '', name: '', price: '0', category: '', duration: 0)
            );
            return _CartItemTile(item: item, name: name, index: index, service: service);
          }),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showAddServiceDialog(context, ref, servicesList),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: Text('Add Service', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kPrimary,
              side: const BorderSide(color: _kPrimary, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
      ),
    );
  }
}

void _showAddServiceDialog(BuildContext context, WidgetRef ref, List<Service> services) {
  final currency = ref.read(currencyProvider);
  showDialog(
    context: context,
    builder: (context) {
      List<Service> filteredServices = List.from(services);
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                const Icon(LucideIcons.scissors, color: _kPrimary, size: 20),
                const SizedBox(width: 8),
                Text('Add Service', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search services...',
                      hintStyle: GoogleFonts.outfit(color: Colors.black26, fontSize: 13),
                      prefixIcon: const Icon(LucideIcons.search, size: 18, color: Colors.black26),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                    onChanged: (v) {
                      setDialogState(() {
                        filteredServices = services.where((s) => 
                          s.name.toLowerCase().contains(v.toLowerCase()) ||
                          s.category.toLowerCase().contains(v.toLowerCase())
                        ).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                    child: filteredServices.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text('No services found', style: GoogleFonts.outfit(color: Colors.black38)),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredServices.length,
                            itemBuilder: (context, index) {
                              final service = filteredServices[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                title: Text(service.name, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$currency ${service.price} • ${service.category}', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black45)),
                                    if (service.isPackage && service.bundledServices != null && service.bundledServices!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Includes: ${service.bundledServices!.map((e) => e.name).join(", ")}',
                                        style: GoogleFonts.outfit(fontSize: 10, color: _kPrimary, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: const Icon(LucideIcons.plus, color: _kPrimary, size: 18),
                                onTap: () {
                                  if (service.id.startsWith('inv_') && service.stockQuantity != null) {
                                    if (service.stockQuantity! <= 0) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: Colors.redAccent,
                                          content: Text('Cannot add. ${service.name} is Out of Stock.'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }
                                    final cart = ref.read(posProvider).cart;
                                    final existingIdx = cart.indexWhere((item) => item.serviceId == service.id);
                                    final currentQty = existingIdx >= 0 ? cart[existingIdx].quantity : 0;
                                    if (currentQty + 1 > service.stockQuantity!) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: Colors.redAccent,
                                          content: Text('Cannot add. Only ${service.stockQuantity!.toStringAsFixed(0)} items of ${service.name} are in stock.'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }
                                  }
                                  ref.read(posProvider.notifier).addToCart(service);
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Added ${service.name} to cart!'),
                                      duration: const Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        }
      );
    },
  );
}

class _CartItemTile extends ConsumerWidget {
  final SaleItem item;
  final String name;
  final int index;
  final Service service;
  const _CartItemTile({required this.item, required this.name, required this.index, required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isProduct = item.serviceId.startsWith('inv_');
    final currency = ref.watch(currencyProvider);
    final staffAsync = ref.watch(staffProvider);
    final staffList = staffAsync.value ?? [];
    final user = ref.watch(authProvider);
    final isStaffRole = user?['role'] == 'STAFF';

    // Auto-assign the logged-in staff's ID to service items when no staff is set yet
    if (!isProduct && isStaffRole && item.staffId == null && staffList.isNotEmpty) {
      final myStaff = staffList.firstWhere(
        (s) => s.userId == user?['id'],
        orElse: () => null,
      );
      if (myStaff != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(posProvider.notifier).setItemStaff(index, myStaff.id?.toString());
        });
      }
    }



    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent border or indicator
              Container(
                width: 6,
                color: isProduct ? (item.isInternal ? Colors.orange : Colors.blue) : _kPrimary,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: _kDark,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '$currency ${item.price}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        color: _kPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (isProduct) ...[
                                      const SizedBox(width: 8),
                                      _buildProductBadge(item.isInternal),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => ref.read(posProvider.notifier).updateQuantity(index, -item.quantity),
                            icon: Icon(LucideIcons.trash2, color: Colors.red.withValues(alpha: 0.5), size: 18),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (isProduct)
                            GestureDetector(
                              onTap: () => ref.read(posProvider.notifier).toggleInternalUse(index, service),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _kBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      item.isInternal ? LucideIcons.package : LucideIcons.shoppingCart,
                                      size: 14,
                                      color: _kDark.withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      item.isInternal ? 'Internal' : 'Retail',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: _kDark.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Container(
                              height: 28,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: _kBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: item.staffId,
                                  hint: Text('Assign Staff', style: GoogleFonts.outfit(fontSize: 11, color: _kPrimary)),
                                  icon: const Icon(LucideIcons.chevronDown, size: 14, color: _kPrimary),
                                  style: GoogleFonts.outfit(fontSize: 12, color: _kDark, fontWeight: FontWeight.w600),
                                  items: staffList.map((s) => DropdownMenuItem<String>(
                                    value: s.id,
                                    child: Text(s.name, style: GoogleFonts.outfit(fontSize: 12)),
                                  )).toList(),
                                  onChanged: (val) {
                                    ref.read(posProvider.notifier).setItemStaff(index, val);
                                  },
                                ),
                              ),
                            ),
                          Container(
                            decoration: BoxDecoration(
                              color: _kBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _QtyBtnCompact(
                                  icon: LucideIcons.minus,
                                  onTap: () => ref.read(posProvider.notifier).updateQuantity(index, -1),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    '${item.quantity}',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: _kDark,
                                    ),
                                  ),
                                ),
                                _QtyBtnCompact(
                                  icon: LucideIcons.plus,
                                  onTap: () {
                                    if (service.id.startsWith('inv_') && service.stockQuantity != null) {
                                      if (item.quantity + 1 > service.stockQuantity!) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            backgroundColor: Colors.redAccent,
                                            content: Text('Cannot add. Only ${service.stockQuantity!.toStringAsFixed(0)} items of ${service.name} are in stock.'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        return;
                                      }
                                    }
                                    ref.read(posProvider.notifier).updateQuantity(index, 1);
                                  },
                                  isPrimary: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.1);
  }

  Widget _buildProductBadge(bool isInternal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isInternal ? Colors.orange : Colors.blue).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isInternal ? 'INTERNAL' : 'RETAIL',
        style: GoogleFonts.outfit(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: isInternal ? Colors.orange : Colors.blue,
        ),
      ),
    );
  }
}

class _QtyBtnCompact extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  const _QtyBtnCompact({required this.icon, required this.onTap, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isPrimary ? _kDark : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 14, color: isPrimary ? Colors.white : _kDark.withValues(alpha: 0.4)),
      ),
    );
  }
}

class _PaymentToggleSection extends ConsumerWidget {
  const _PaymentToggleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentMethod = ref.watch(posProvider.select((s) => s.paymentMethod));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Method', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black45)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _PaymentOption('CASH', LucideIcons.banknote, paymentMethod == 'CASH')),
              const SizedBox(width: 8),
              Expanded(child: _PaymentOption('ONLINE', LucideIcons.creditCard, paymentMethod == 'ONLINE')),
              const SizedBox(width: 8),
              Expanded(child: _PaymentOption('CREDIT', LucideIcons.userPlus, paymentMethod == 'CREDIT', label: 'RECEIVABLE')),
            ],
          ),
          if (paymentMethod == 'ONLINE') ...[
            const SizedBox(height: 12),
            const _OnlineAccountSelector(),
          ],
        ],
      ),
    );
  }
}

class _OnlineAccountSelector extends ConsumerWidget {
  const _OnlineAccountSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(paymentAccountsProvider);
    final posState = ref.watch(posProvider);
    final total = posState.total;
    final currency = ref.watch(currencyProvider);

    return accountsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
          ),
        ),
      ),
      error: (err, _) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.alertCircle, size: 16, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Could not load accounts',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.redAccent),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              onPressed: () => ref.invalidate(paymentAccountsProvider),
            ),
          ],
        ),
      ),
      data: (allAccounts) {
        final accounts = allAccounts.where((a) => a.isActive).toList();
        if (accounts.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertTriangle, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No online accounts active. Setup in Salon Settings.',
                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.amber.shade900),
                  ),
                ),
              ],
            ),
          );
        }

        if (posState.selectedPaymentAccountId == null &&
            (posState.onlineBreakdown == null || posState.onlineBreakdown!.isEmpty)) {
          final defaultAcc = accounts.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(posProvider.notifier).setSelectedPaymentAccountId(defaultAcc.id);
          });
        }

        final isSplit = posState.onlineBreakdown != null && posState.onlineBreakdown!.isNotEmpty;

        if (isSplit) {
          final breakdown = posState.onlineBreakdown!;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.split, size: 16, color: _kPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Split Payment (${breakdown.length} Accounts)',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _kPrimary,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _openSplitDialog(context, ref, accounts, total, currency),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          'Edit',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _kAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        ref.read(posProvider.notifier).setOnlineBreakdown(null);
                        final def = accounts.first;
                        ref.read(posProvider.notifier).setSelectedPaymentAccountId(def.id);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Icon(LucideIcons.x, size: 16, color: Colors.black45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: breakdown.map((item) {
                    final accId = item['accountId']?.toString() ?? '';
                    final acc = accounts.cast<PaymentAccount?>().firstWhere(
                          (a) => a?.id == accId,
                          orElse: () => null,
                        );
                    final name = acc?.accountName ?? item['accountName'] ?? 'Account';
                    final amt = item['amount'] ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Text(
                        '$name: $currency $amt',
                        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }

        final selectedId = posState.selectedPaymentAccountId;
        final selectedAccount = accounts.cast<PaymentAccount?>().firstWhere(
          (a) => a?.id == selectedId,
          orElse: () => accounts.first,
        );

        return Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedAccount?.id,
                    icon: const Icon(LucideIcons.chevronDown, size: 16, color: Colors.black45),
                    borderRadius: BorderRadius.circular(12),
                    items: accounts.map((acc) {
                      return DropdownMenuItem<String>(
                        value: acc.id,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _kPrimary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.landmark, size: 12, color: _kPrimary),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${acc.accountName} (${acc.type}${acc.accountNumber != null && acc.accountNumber!.isNotEmpty ? " - ${acc.accountNumber}" : ""})',
                                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(posProvider.notifier).setSelectedPaymentAccountId(val);
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _openSplitDialog(context, ref, accounts, total, currency),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.split, size: 16, color: _kPrimary),
                    const SizedBox(width: 6),
                    Text(
                      'Split',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openSplitDialog(BuildContext context, WidgetRef ref, List<PaymentAccount> accounts, double total, String currency) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SplitPaymentDialog(
        accounts: accounts,
        total: total,
        currency: currency,
        initialBreakdown: ref.read(posProvider).onlineBreakdown,
        onConfirmed: (breakdown) {
          ref.read(posProvider.notifier).setOnlineBreakdown(breakdown);
          ref.read(posProvider.notifier).setSelectedPaymentAccountId(null);
        },
      ),
    );
  }
}

class _SplitPaymentDialog extends StatefulWidget {
  final List<PaymentAccount> accounts;
  final double total;
  final String currency;
  final List<Map<String, dynamic>>? initialBreakdown;
  final ValueChanged<List<Map<String, dynamic>>> onConfirmed;

  const _SplitPaymentDialog({
    required this.accounts,
    required this.total,
    required this.currency,
    this.initialBreakdown,
    required this.onConfirmed,
  });

  @override
  State<_SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<_SplitPaymentDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    for (final acc in widget.accounts) {
      double initialAmount = 0.0;
      if (widget.initialBreakdown != null) {
        final found = widget.initialBreakdown!.firstWhere(
          (b) => b['accountId']?.toString() == acc.id,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          initialAmount = (found['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
      _controllers[acc.id] = TextEditingController(
        text: initialAmount > 0 ? (initialAmount % 1 == 0 ? initialAmount.toInt().toString() : initialAmount.toString()) : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _currentSum {
    double sum = 0.0;
    for (final c in _controllers.values) {
      final val = double.tryParse(c.text.trim()) ?? 0.0;
      sum += val;
    }
    return sum;
  }

  void _fillRemaining(String targetAccountId) {
    double otherSum = 0.0;
    for (final entry in _controllers.entries) {
      if (entry.key != targetAccountId) {
        otherSum += double.tryParse(entry.value.text.trim()) ?? 0.0;
      }
    }
    final remaining = widget.total - otherSum;
    if (remaining >= 0) {
      _controllers[targetAccountId]?.text = remaining % 1 == 0 ? remaining.toInt().toString() : remaining.toString();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final sum = _currentSum;
    final diff = widget.total - sum;
    final isMatched = (diff.abs() < 0.01) && sum > 0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.split, size: 20, color: _kPrimary),
          ),
          const SizedBox(width: 12),
          Text(
            'Split Online Payment',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kDark.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Amount Due:', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    Text(
                      '${widget.currency} ${widget.total.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: _kPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...widget.accounts.map((acc) {
                final controller = _controllers[acc.id]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              acc.accountName,
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              '${acc.type} • ${acc.accountTitle ?? ''} ${acc.accountNumber ?? ''}'.trim(),
                              style: GoogleFonts.outfit(fontSize: 11, color: Colors.black45),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            hintText: '0',
                            prefixText: '${widget.currency} ',
                            prefixStyle: GoogleFonts.outfit(fontSize: 12, color: Colors.black54),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Fill Remaining',
                        icon: const Icon(LucideIcons.arrowDownToLine, size: 16, color: _kAccent),
                        onPressed: () => _fillRemaining(acc.id),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Allocated: ${widget.currency} ${sum.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: isMatched ? Colors.green : Colors.red)),
                  Text(
                    diff == 0
                        ? 'Balanced'
                        : (diff > 0
                            ? 'Remaining: ${widget.currency} ${diff.toStringAsFixed(0)}'
                            : 'Exceeded by: ${widget.currency} ${(-diff).toStringAsFixed(0)}'),
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: isMatched ? Colors.green : Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black54)),
        ),
        ElevatedButton(
          onPressed: isMatched
              ? () {
                  final list = <Map<String, dynamic>>[];
                  for (final acc in widget.accounts) {
                    final val = double.tryParse(_controllers[acc.id]?.text.trim() ?? '') ?? 0.0;
                    if (val > 0) {
                      list.add({
                        'accountId': acc.id,
                        'accountName': acc.accountName,
                        'amount': val,
                      });
                    }
                  }
                  widget.onConfirmed(list);
                  Navigator.of(context).pop();
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('Confirm Split', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _CheckoutFooter extends ConsumerWidget {
  const _CheckoutFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartEmpty = ref.watch(posProvider.select((s) => s.cart.isEmpty));
    final isLoading = ref.watch(posProvider.select((s) => s.isLoading));
    final currency = ref.watch(currencyProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kBg.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _buildSummaryRow('Subtotal', '$currency ${ref.watch(posProvider.select((s) => s.subtotal)).toStringAsFixed(0)}'),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: Colors.black12),
                ),
                _buildDiscountField(ref),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: Colors.black12),
                ),
                Row(
                  children: [
                    Expanded(child: _buildTaxField(ref)),
                    Container(width: 1, height: 24, color: Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 12)),
                    Expanded(child: _buildCommissionField(ref)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: _buildAmountPaidField(ref)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Payable',
                style: GoogleFonts.outfit(
                  color: Colors.black45,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$currency ${ref.watch(posProvider.select((s) => s.total)).toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _kPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (cartEmpty || isLoading) 
                  ? null 
                  : () {
                      ref.read(posProvider.notifier).setLoading(true);
                      _processSale(context, ref);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
                disabledBackgroundColor: Colors.grey[300],
              ),
              child: isLoading 
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    ref.watch(posProvider.select((s) => s.draftId != null))
                        ? 'Finalize & Close'
                        : 'Confirm Order',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: (cartEmpty || isLoading) 
                  ? null 
                  : () => _saveDraft(context, ref),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kPrimary, width: 1.5),
                foregroundColor: _kPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                disabledForegroundColor: Colors.grey[300],
              ),
              child: Text(
                ref.watch(posProvider.select((s) => s.draftId != null))
                    ? 'Update Draft'
                    : 'Save Draft / Quotation',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.black45,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: _kDark,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDiscountField(WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final discountType = ref.watch(posProvider.select((s) => s.discountType));
    final discountValue = ref.watch(posProvider.select((s) => s.discountValue));
    final actualDiscount = ref.watch(posProvider.select((s) => s.discount));
    final cartIsEmpty = ref.watch(posProvider.select((s) => s.cart.isEmpty));
    final isPercent = discountType == 'PERCENT';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Discount',
                style: GoogleFonts.outfit(
                  color: Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 28,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        ref.read(posProvider.notifier).setDiscountType('FLAT');
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: !isPercent ? _kPrimary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: !isPercent ? [BoxShadow(color: _kPrimary.withValues(alpha: 0.3), blurRadius: 4)] : null,
                        ),
                        child: Text(
                          'Val ($currency)',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: !isPercent ? Colors.white : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        ref.read(posProvider.notifier).setDiscountType('PERCENT');
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPercent ? _kPrimary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: isPercent ? [BoxShadow(color: _kPrimary.withValues(alpha: 0.3), blurRadius: 4)] : null,
                        ),
                        child: Text(
                          '%',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPercent ? Colors.white : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isPercent && actualDiscount > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '- $currency ${actualDiscount.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          SizedBox(
            width: 80,
            height: 32,
            child: TextFormField(
              key: ValueKey(cartIsEmpty ? 'disc_empty' : 'disc_$discountType'),
              initialValue: discountValue > 0 ? (discountValue == discountValue.toInt() ? discountValue.toInt().toString() : discountValue.toString()) : '',
              onChanged: (v) => ref.read(posProvider.notifier).setDiscount(double.tryParse(v) ?? 0),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
              decoration: InputDecoration(
                hintText: '0',
                suffixText: isPercent ? ' %' : ' $currency',
                suffixStyle: GoogleFonts.outfit(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommissionField(WidgetRef ref) {
    final cartIsEmpty = ref.watch(posProvider.select((s) => s.cart.isEmpty));
    final commissionRate = ref.watch(posProvider.select((s) => s.customCommissionRate));
    return Row(
      children: [
        Expanded(
          child: Text(
            'Commission',
            style: GoogleFonts.outfit(
              color: Colors.black45,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 75,
          height: 32,
          child: TextFormField(
            key: ValueKey(cartIsEmpty ? 'comm_empty' : 'comm_active'),
            initialValue: commissionRate != null ? commissionRate.toStringAsFixed(0) : '',
            onChanged: (v) => ref.read(posProvider.notifier).setCommissionRate(double.tryParse(v)),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _kPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Default',
              hintStyle: GoogleFonts.outfit(fontSize: 10, color: Colors.black26),
              suffixText: ' %',
              suffixStyle: GoogleFonts.outfit(fontSize: 10, color: _kPrimary),
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaxField(WidgetRef ref) {
    final taxRate = ref.watch(posProvider.select((s) => s.taxRate));
    final taxAmount = ref.watch(posProvider.select((s) => s.taxAmount));
    final currency = ref.watch(currencyProvider);
    final cartIsEmpty = ref.watch(posProvider.select((s) => s.cart.isEmpty));

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Tax (${taxRate.toStringAsFixed(0)}%)',
                style: GoogleFonts.outfit(
                  color: Colors.black45,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (taxAmount > 0)
                Text(
                  '+ $currency ${taxAmount.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 55,
          height: 32,
          child: TextFormField(
            key: ValueKey(cartIsEmpty ? 'tax_empty' : 'tax_active'),
            initialValue: taxRate > 0 ? taxRate.toStringAsFixed(0) : '0',
            onChanged: (v) => ref.read(posProvider.notifier).setTaxRate(double.tryParse(v) ?? 0.0),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
            decoration: InputDecoration(
              hintText: '15',
              suffixText: ' %',
              suffixStyle: GoogleFonts.outfit(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold),
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountPaidField(WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final total = ref.watch(posProvider.select((s) => s.total));
    final amountPaid = ref.watch(posProvider.select((s) => s.amountPaid));
    final cartIsEmpty = ref.watch(posProvider.select((s) => s.cart.isEmpty));

    return Row(
      children: [
        Expanded(
          child: Text(
            'Paid',
            style: GoogleFonts.outfit(
              color: Colors.black45,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 75,
          height: 32,
          child: TextFormField(
            key: ValueKey(cartIsEmpty ? 'paid_empty' : 'paid_active'),
            initialValue: amountPaid != null ? amountPaid.toStringAsFixed(0) : '',
            onChanged: (v) {
              final val = double.tryParse(v.replaceAll(',', ''));
              ref.read(posProvider.notifier).setAmountPaid(val);
            },
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
            decoration: InputDecoration(
              hintText: total.toStringAsFixed(0),
              hintStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black26),
              suffixText: ' $currency',
              suffixStyle: GoogleFonts.outfit(fontSize: 10, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _processSale(BuildContext context, WidgetRef ref) async {
    ref.read(posProvider.notifier).getOrGenerateDraftId();
    final state = ref.read(posProvider);
    final totalVal = state.total;
    final paidVal = state.amountPaid ?? totalVal;
    final hasDebt = paidVal < totalVal;
    if (state.paymentMethod == 'CREDIT' || hasDebt) {
      if (state.customerPhone.trim().isEmpty || state.customerName.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Customer Name and Phone Number are required for credit/partial payment sales.', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
        ref.read(posProvider.notifier).setLoading(false);
        return;
      }
    }
    try {
      final saleData = {
        'customerPhone': state.customerPhone,
        'customerName': state.customerName,
        'customerSource': state.customerSource,
        'subtotal': state.subtotal,
        'discount': state.discount,
        'taxRate': state.taxRate,
        'total': state.total,
        'paymentMethod': state.paymentMethod,
        'paymentAccountId': state.paymentMethod == 'ONLINE' ? state.selectedPaymentAccountId : null,
        'paymentBreakdown': state.paymentMethod == 'ONLINE' ? state.onlineBreakdown : null,
        'amountPaid': state.amountPaid,
        'staffId': null,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'customCommissionRate': state.customCommissionRate,
        'items': state.cart.map((i) => i.toJson()).toList(),
        'status': 'ACTIVE',
      };
      if (state.draftId != null) {
        saleData['id'] = state.draftId;
        try {
          await ref.read(syncRepositoryProvider).updateSale(state.draftId!, saleData);
        } catch (e) {
          if (e.toString().contains('404') || e.toString().contains('not found') || e.toString().toLowerCase().contains('failed to update')) {
            await ref.read(syncRepositoryProvider).createSale(saleData);
          } else {
            rethrow;
          }
        }
      } else {
        await ref.read(syncRepositoryProvider).createSale(saleData);
      }

      if (state.appointmentId != null) {
        await ref.read(apiServiceProvider).updateAppointmentStatus(state.appointmentId!, 'COMPLETED');
        ref.invalidate(appointmentsProvider);
      }
      
      ref.invalidate(reportsProvider);
      ref.invalidate(dashboardViewModelProvider);
      ref.invalidate(servicesProvider);
      ref.invalidate(inventoryProvider);
      ref.invalidate(clientsProvider);
      ref.invalidate(ledgerProvider);
      ref.invalidate(paymentAccountsProvider);
      
      if (context.mounted) {
        _showSuccessDialog(context, state, ref);
      }
      ref.read(posProvider.notifier).clear();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      ref.read(posProvider.notifier).setLoading(false);
    }
  }

  Future<void> _saveDraft(BuildContext context, WidgetRef ref) async {
    ref.read(posProvider.notifier).getOrGenerateDraftId();
    final state = ref.read(posProvider);
    final totalVal = state.total;
    final paidVal = state.amountPaid ?? totalVal;
    final hasDebt = paidVal < totalVal;
    if (state.paymentMethod == 'CREDIT' || hasDebt) {
      if (state.customerPhone.trim().isEmpty || state.customerName.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Customer Name and Phone Number are required for credit/partial payment sales.', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
        ref.read(posProvider.notifier).setLoading(false);
        return;
      }
    }
    ref.read(posProvider.notifier).setLoading(true);
    try {
      final saleData = {
        'customerPhone': state.customerPhone,
        'customerName': state.customerName,
        'customerSource': state.customerSource,
        'subtotal': state.subtotal,
        'discount': state.discount,
        'taxRate': state.taxRate,
        'total': state.total,
        'paymentMethod': state.paymentMethod,
        'paymentAccountId': state.paymentMethod == 'ONLINE' ? state.selectedPaymentAccountId : null,
        'paymentBreakdown': state.paymentMethod == 'ONLINE' ? state.onlineBreakdown : null,
        'amountPaid': state.amountPaid,
        'staffId': null,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'customCommissionRate': state.customCommissionRate,
        'items': state.cart.map((i) => i.toJson()).toList(),
        'status': 'DRAFT',
      };
      if (state.draftId != null) {
        saleData['id'] = state.draftId;
        try {
          await ref.read(syncRepositoryProvider).updateSale(state.draftId!, saleData);
        } catch (e) {
          if (e.toString().contains('404') || e.toString().contains('not found') || e.toString().toLowerCase().contains('failed to update')) {
            await ref.read(syncRepositoryProvider).createSale(saleData);
          } else {
            rethrow;
          }
        }
      } else {
        await ref.read(syncRepositoryProvider).createSale(saleData);
      }
      
      // Invalidate relevant providers to refresh data
      ref.invalidate(reportsProvider);
      ref.invalidate(dashboardViewModelProvider);
      ref.invalidate(servicesProvider);
      ref.invalidate(inventoryProvider);
      ref.invalidate(clientsProvider);
      ref.invalidate(ledgerProvider);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft/Quotation saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      ref.read(posProvider.notifier).clear();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      ref.read(posProvider.notifier).setLoading(false);
    }
  }




  void _showSuccessDialog(BuildContext context, POSState state, WidgetRef ref) {
    final currency = ref.read(currencyProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(LucideIcons.checkCircle, color: Colors.green, size: 48),
            ),
            const SizedBox(height: 20),
            Text('Payment Successful', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _dialogDetailRow('Total Amount', '$currency ${state.total.toStringAsFixed(0)}', isBold: true),
                  const Divider(height: 12),
                  _dialogDetailRow('Given Amount', '$currency ${(state.amountPaid ?? state.total).toStringAsFixed(0)}'),
                  if ((state.amountPaid ?? state.total) > state.total) ...[
                    const Divider(height: 12),
                    _dialogDetailRow('Change', '$currency ${((state.amountPaid ?? state.total) - state.total).toStringAsFixed(0)}', color: Colors.green),
                  ],
                  if ((state.amountPaid ?? state.total) < state.total) ...[
                    const Divider(height: 12),
                    _dialogDetailRow('Remaining Balance', '$currency ${(state.total - (state.amountPaid ?? state.total)).toStringAsFixed(0)}', color: Colors.red),
                  ],
                  const Divider(height: 12),
                  _dialogDetailRow('Payment Mode', state.paymentMethod.replaceAll('_', ' ')),
                  if (state.paymentMethod == 'ONLINE' && state.onlineBreakdown != null) ...[
                    const Divider(height: 12),
                    _dialogDetailRow('Account Breakdown', 'Split (${state.onlineBreakdown!.length} accounts)'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 320,
              height: 160,
              child: GridView.count(
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _receiptBtn(
                  icon: LucideIcons.messageCircle,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _shareDirectWhatsApp(context, state, ref),
                ),
                _receiptBtn(
                  icon: LucideIcons.printer,
                  label: 'Print',
                  color: Colors.blue,
                  onTap: () => _handlePrint(state, ref, false),
                ),
                _receiptBtn(
                  icon: LucideIcons.files,
                  label: 'Print Both',
                  color: Colors.indigo,
                  onTap: () => _handlePrint(state, ref, true),
                ),
                _receiptBtn(
                  icon: LucideIcons.x,
                  label: 'Close',
                  color: Colors.grey,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePrint(POSState state, WidgetRef ref, bool both) async {
    final authState = ref.read(authProvider);
    final salon = authState?['salon'];
    final serviceList = ref.read(servicesProvider).value ?? [];
    
    final items = state.cart.map((c) {
      // Use the name map that POS already has stored (covers services, packages, products)
      final nameFromMap = state.serviceNameMap[c.serviceId];
      final s = nameFromMap == null
          ? serviceList.firstWhere((s) => s.id == c.serviceId, orElse: () => Service(id: '', name: '', price: '0', category: '', duration: 0))
          : null;
      return InvoiceItemData(
        name: nameFromMap ?? s!.name,
        arabicName: s?.arabicName ?? '',
        quantity: c.quantity,
        price: c.price,
      );
    }).toList();

    final invoiceData = InvoiceData(
      invoiceId: state.draftId ?? ref.read(posProvider.notifier).getOrGenerateDraftId(),
      items: items,
      subtotal: state.subtotal,
      taxAmount: state.taxAmount,
      taxRate: state.taxRate,
      discount: state.discount,
      total: state.total,
      amountPaid: state.amountPaid ?? state.total,
      balanceDue: state.total > (state.amountPaid ?? state.total) ? state.total - (state.amountPaid ?? state.total) : 0.0,
      change: (state.amountPaid ?? state.total) > state.total ? (state.amountPaid ?? state.total) - state.total : 0.0,
      paymentMethod: state.paymentMethod,
      date: DateTime.now(),
      customerName: state.customerName,
      cashierName: authState?['name']?.toString(),
    );

    final pdf = await PdfInvoiceGenerator.generate(invoiceData, salon, both);
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Future<void> _shareDirectWhatsApp(BuildContext context, POSState state, WidgetRef ref) async {
    final authState = ref.read(authProvider);
    final salonName = authState?['salon']?['name'] ?? 'Salon Pro';
    final salonAddress = authState?['salon']?['address'] ?? '';
    final currency = ref.read(currencyProvider);

    final clientName = state.customerName.isNotEmpty ? state.customerName : 'Valued Customer';
    
    final buffer = StringBuffer();
    buffer.writeln("🧾 *INVOICE - $salonName*");
    if (salonAddress.isNotEmpty) {
      buffer.writeln("📍 $salonAddress");
    }
    buffer.writeln();
    buffer.writeln("👤 *Client:* $clientName");
    if (state.customerPhone.isNotEmpty) {
      buffer.writeln("📞 *Phone:* ${state.customerPhone}");
    }
    buffer.writeln();
    buffer.writeln("📋 *ITEMS*");

    for (var item in state.cart) {
      final name = state.serviceNameMap[item.serviceId] ?? 'Service';
      buffer.writeln("• $name x${item.quantity} - $currency ${(item.price * item.quantity).toStringAsFixed(0)}");
    }

    if (state.discount > 0) {
      buffer.writeln("\nSubtotal: $currency ${state.subtotal.toStringAsFixed(0)}");
      buffer.writeln("Discount: -$currency ${state.discount.toStringAsFixed(0)}");
    }

    if (state.taxAmount > 0) {
      buffer.writeln("Tax (${state.taxRate.toStringAsFixed(0)}%): $currency ${state.taxAmount.toStringAsFixed(0)}");
    }

    buffer.writeln("\n💰 *TOTAL: $currency ${state.total.toStringAsFixed(0)}*");
    buffer.writeln("Payment: ${state.paymentMethod.replaceAll('_', ' ')}");
    
    final qrDomain = authState?['salon']?['qrDomain'] ?? 'salonpro.app';
    final invoiceId = state.draftId ?? ref.read(posProvider.notifier).getOrGenerateDraftId();
    final invoiceUrl = "https://$qrDomain/invoice/$invoiceId";
    
    buffer.writeln("\n📄 *View PDF Invoice:*\n$invoiceUrl");
    buffer.writeln("\nThank you for choosing us! ✨\n*Powered by $salonName*");

    final fullMessage = buffer.toString();

    String phone = state.customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.startsWith('0')) {
      if (phone.length == 11) {
        phone = '92${phone.substring(1)}';
      } else if (phone.length == 10) {
        phone = '966${phone.substring(1)}';
      } else {
        phone = phone.substring(1);
      }
    }

    final String urlStr = phone.isNotEmpty
        ? "https://api.whatsapp.com/send?phone=$phone&text=${Uri.encodeComponent(fullMessage)}"
        : "https://api.whatsapp.com/send?text=${Uri.encodeComponent(fullMessage)}";

    try {
      final uri = Uri.parse(urlStr);
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success) {
        final altUrlStr = phone.isNotEmpty
            ? "https://wa.me/$phone?text=${Uri.encodeComponent(fullMessage)}"
            : "https://wa.me/?text=${Uri.encodeComponent(fullMessage)}";
        await launchUrl(Uri.parse(altUrlStr), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await Share.share(fullMessage, subject: 'Salon Receipt');
    }
  }

  void _showShareDialog(BuildContext context, POSState state, WidgetRef ref) {
    final authState = ref.read(authProvider);
    final salonName = authState?['salon']?['name'] ?? 'Salon Pro';
    final salonAddress = authState?['salon']?['address'] ?? '';
    final currency = ref.read(currencyProvider);

    final qrDomain = authState?['salon']?['qrDomain'] ?? 'salonpro.app';
    final invoiceUrl = "https://$qrDomain/invoice/${state.draftId ?? ref.read(posProvider.notifier).getOrGenerateDraftId()}";

    final clientName = state.customerName.isNotEmpty ? state.customerName : 'Walk-in Customer';
    final clientPhone = state.customerPhone.isNotEmpty ? state.customerPhone : 'N/A';
    String receiptBody = "Client: $clientName\nPhone: $clientPhone\n\n";
    for (var item in state.cart) {
      final name = state.serviceNameMap[item.serviceId] ?? 'Service';
      receiptBody += "- $name x${item.quantity}: $currency ${(item.price * item.quantity).toStringAsFixed(0)}\n";
    }
    receiptBody += "\n*Total Amount: $currency ${state.total.toStringAsFixed(0)}*\nMode: ${state.paymentMethod}";
    receiptBody += "\n\n📄 *View PDF Invoice:*\n$invoiceUrl";

    final messageController = TextEditingController(text: "Thank you for your visit!");
    final headerController = TextEditingController(text: salonName);
    final footerController = TextEditingController(text: "Thank you for choosing us! ✨\n*Powered by Salon Pro System*");
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Customize Message', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: headerController,
              decoration: InputDecoration(
                labelText: 'Header / Salon Name',
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Bill Details:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text(receiptBody, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Personal Message',
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
              TextField(
                controller: footerController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Custom Footer',
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final header = headerController.text;
                final fullMessage = "*$header*\n" + 
                                    (salonAddress.isNotEmpty ? "📍 $salonAddress\n" : "") +
                                    "\n*Bill Summary*\n$receiptBody\n\n" +
                                    "${messageController.text}\n\n" +
                                    "${footerController.text}";
              
              Navigator.pop(context); // Close share dialog
              Navigator.pop(context); // Close success dialog
              
              await _shareReceiptMessage(state, fullMessage);
            },
            child: const Text('Share to WhatsApp'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareReceiptMessage(POSState state, String message) async {
    String phone = state.customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.startsWith('0')) {
      if (phone.length == 11) {
        phone = '92${phone.substring(1)}';
      } else if (phone.length == 10) {
        phone = '966${phone.substring(1)}';
      } else {
        phone = phone.substring(1);
      }
    }
    
    final String urlStr = phone.isNotEmpty
        ? "https://api.whatsapp.com/send?phone=$phone&text=${Uri.encodeComponent(message)}"
        : "https://api.whatsapp.com/send?text=${Uri.encodeComponent(message)}";
        
    try {
      final uri = Uri.parse(urlStr);
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success) {
        final altUrlStr = phone.isNotEmpty
            ? "https://wa.me/$phone?text=${Uri.encodeComponent(message)}"
            : "https://wa.me/?text=${Uri.encodeComponent(message)}";
        await launchUrl(Uri.parse(altUrlStr), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await Share.share(message, subject: 'Salon Receipt');
    }
  }

  Future<void> _shareReceipt(POSState state, WidgetRef ref) async {}
}

void _showDraftsDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => _DraftsDialog(ref: ref),
  );
}

void _shareDraftQuotation(Sale draft, WidgetRef ref) async {
  final authState = ref.read(authProvider);
  final salonName = authState?['salon']?['name'] ?? 'Salon Pro';
  final salonAddress = authState?['salon']?['address'] ?? '';
  final currency = ref.read(currencyProvider);

  String receiptBody = "";
  for (var item in draft.items) {
    final name = item.serviceName ?? 'Service';
    receiptBody += "- $name x${item.quantity}: $currency ${(item.price * item.quantity).toStringAsFixed(0)}\n";
  }
  receiptBody += "\n*Subtotal: $currency ${draft.subtotal.toStringAsFixed(0)}*";
  if (draft.discount > 0) {
    receiptBody += "\nDiscount: $currency ${draft.discount.toStringAsFixed(0)}";
  }
  receiptBody += "\n*Total Amount: $currency ${draft.total.toStringAsFixed(0)}*";

  final header = "*QUOTATION - $salonName*";
  final footer = "This is a quotation / draft bill. You can finalize it at the salon at any time. ✨\n*Powered by $salonName*";
  final addressLine = salonAddress.isNotEmpty ? "📍 $salonAddress\n" : "";
  final clientName = draft.customerName ?? 'Walk-in Customer';
  final clientPhone = draft.customerPhone ?? 'N/A';
  final clientInfo = "Client: $clientName\nPhone: $clientPhone\n";

  final fullMessage = "$header\n$addressLine\n$clientInfo\n$receiptBody\n\n$footer";

  String phone = draft.customerPhone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  if (phone.startsWith('0')) {
    if (phone.length == 11) {
      phone = '92${phone.substring(1)}';
    } else if (phone.length == 10) {
      phone = '966${phone.substring(1)}';
    } else {
      phone = phone.substring(1);
    }
  }

  final String urlStr = phone.isNotEmpty
      ? "https://api.whatsapp.com/send?phone=$phone&text=${Uri.encodeComponent(fullMessage)}"
      : "https://api.whatsapp.com/send?text=${Uri.encodeComponent(fullMessage)}";

  try {
    final uri = Uri.parse(urlStr);
    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success) {
      final altUrlStr = phone.isNotEmpty
          ? "https://wa.me/$phone?text=${Uri.encodeComponent(fullMessage)}"
          : "https://wa.me/?text=${Uri.encodeComponent(fullMessage)}";
      await launchUrl(Uri.parse(altUrlStr), mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    await Share.share(fullMessage, subject: 'Salon Quotation');
  }
}

// --- Quotation Drafts List Dialog Widget ---
class _DraftsDialog extends StatefulWidget {
  final WidgetRef ref;
  const _DraftsDialog({required this.ref});

  @override
  State<_DraftsDialog> createState() => _DraftsDialogState();
}

class _DraftsDialogState extends State<_DraftsDialog> {
  late Future<List<Sale>> _draftsFuture;

  @override
  void initState() {
    super.initState();
    _fetchDrafts();
  }

  void _fetchDrafts() {
    _draftsFuture = widget.ref.read(apiServiceProvider).getSales(status: 'DRAFT').then((data) {
      return data.map((json) => Sale.fromJson(json)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.ref.read(currencyProvider);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(LucideIcons.fileText, color: _kPrimary, size: 22),
          const SizedBox(width: 8),
          Text('Quotation Drafts', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: FutureBuilder<List<Sale>>(
          future: _draftsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _kPrimary));
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.outfit(fontSize: 13, color: Colors.red)));
            }
            final drafts = snapshot.data ?? [];
            if (drafts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.folderOpen, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('No drafts found', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 14)),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: drafts.length,
              itemBuilder: (context, index) {
                final draft = drafts[index];
                final dateStr = DateFormat('MMM dd, HH:mm').format(draft.createdAt);
                final phone = draft.customerPhone ?? '';
                final name = draft.customerName ?? (phone.isNotEmpty ? phone : 'Walk-in Customer');
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kBg.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$dateStr • ${draft.items.length} items',
                                    style: GoogleFonts.outfit(color: Colors.black45, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$currency ${draft.total.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: _kPrimary, fontSize: 15),
                                ),
                                if (draft.discount > 0)
                                  Text(
                                    'Disc: $currency ${draft.discount.toStringAsFixed(0)}',
                                    style: GoogleFonts.outfit(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Actions row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // WhatsApp share button
                            _dialogActionBtn(
                              icon: LucideIcons.messageCircle,
                              color: const Color(0xFF25D366),
                              onTap: () => _shareDraftQuotation(draft, widget.ref),
                            ),
                            const SizedBox(width: 8),
                            // Delete button
                            _dialogActionBtn(
                              icon: LucideIcons.trash2,
                              color: Colors.red,
                              onTap: () => _confirmDeleteDraft(draft.id),
                            ),
                            const SizedBox(width: 8),
                            // Load button
                            _dialogActionBtn(
                              icon: LucideIcons.folderOpen,
                              color: Colors.blue,
                              onTap: () {
                                _loadDraftIntoPOS(draft);
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
    }

    Widget _dialogActionBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      );
    }

    void _loadDraftIntoPOS(Sale draft) {
      final posState = widget.ref.read(posProvider);
      final newMap = Map<String, String>.from(posState.serviceNameMap);
      for (var item in draft.items) {
        if (item.serviceName != null) {
          newMap[item.serviceId] = item.serviceName!;
        }
      }
      widget.ref.read(posProvider.notifier).loadDraft(draft, newMap);
    }

    void _confirmDeleteDraft(String draftId) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Delete Draft?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to delete this quotation draft?', style: GoogleFonts.outfit(fontSize: 14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await widget.ref.read(apiServiceProvider).deleteSale(draftId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft deleted')));
                    setState(() {
                      _fetchDrafts();
                    });
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.searchX, size: 64, color: Colors.black.withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          Text('No services found matching your criteria', style: GoogleFonts.outfit(color: Colors.black26)),
        ],
      ),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  final Service service;
  final int index;
  const _ServiceCard({required this.service, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    return GestureDetector(
      onTap: () {
        if (service.id.startsWith('inv_') && service.stockQuantity != null) {
          if (service.stockQuantity! <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.redAccent,
                content: Text('Cannot add. ${service.name} is Out of Stock.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          final cart = ref.read(posProvider).cart;
          final existingIdx = cart.indexWhere((item) => item.serviceId == service.id);
          final currentQty = existingIdx >= 0 ? cart[existingIdx].quantity : 0;
          if (currentQty + 1 > service.stockQuantity!) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.redAccent,
                content: Text('Cannot add. Only ${service.stockQuantity!.toStringAsFixed(0)} items of ${service.name} are in stock.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
        }
        ref.read(posProvider.notifier).addToCart(service);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 6))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Subtle background icon
              Positioned(
                bottom: -15, right: -15,
                child: Icon(LucideIcons.scissors, size: 80, color: _kPrimary.withValues(alpha: 0.03)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(service.category, style: GoogleFonts.outfit(fontSize: 9, color: _kPrimary, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        ),
                        if (service.isPackage) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('PACKAGE', style: GoogleFonts.outfit(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          ),
                        ]
                      ],
                    ),
                    const Spacer(),
                    Text(service.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _kDark, height: 1.2)),
                    if (service.isPackage && service.bundledServices != null && service.bundledServices!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Includes: ${service.bundledServices!.map((e) => e.name).join(", ")}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: 10, color: _kPrimary, fontWeight: FontWeight.w500),
                      ),
                    ],
                    if (service.id.startsWith('inv_')) ...[
                      const SizedBox(height: 4),
                      Text(
                        service.stockQuantity == null || service.stockQuantity! <= 0 
                            ? 'Out of Stock' 
                            : 'Stock: ${service.stockQuantity!.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 11, 
                          color: service.stockQuantity == null || service.stockQuantity! <= 0 
                              ? Colors.red 
                              : Colors.green, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text('$currency ${service.price}', style: GoogleFonts.outfit(fontSize: 16, color: _kPrimary, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              // Add indicator
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: _kBg, shape: BoxShape.circle),
                  child: Icon(service.isPackage ? LucideIcons.sliders : LucideIcons.plus, size: 14, color: _kPrimary),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(delay: (index * 40).ms).scale(begin: const Offset(0.9, 0.9)),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  const _QtyBtn({required this.icon, required this.onTap, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isPrimary ? _kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isPrimary ? null : Border.all(color: Colors.black12),
        ),
        child: Icon(icon, size: 14, color: isPrimary ? Colors.white : Colors.black45),
      ),
    );
  }
}

class _PaymentOption extends ConsumerWidget {
  final String method;
  final String? label;
  final IconData icon;
  final bool isSelected;
  const _PaymentOption(this.method, this.icon, this.isSelected, {this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => ref.read(posProvider.notifier).setPaymentMethod(method),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _kDark : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? _kDark : Colors.black12),
          boxShadow: isSelected ? [BoxShadow(color: _kDark.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.black38),
            const SizedBox(width: 10),
            Text(label ?? method, style: GoogleFonts.outfit(fontSize: 13, color: isSelected ? Colors.white : Colors.black38, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

Widget _dialogDetailRow(String label, String value, {bool isBold = false, Color? color}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: GoogleFonts.outfit(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)),
      Text(value, style: GoogleFonts.outfit(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color ?? Colors.black87)),
    ],
  );
}

pw.Widget _pwInvoiceSummaryRow(String label, String val, pw.TextStyle labelStyle, pw.TextStyle valStyle) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(label, style: labelStyle),
        pw.SizedBox(width: 20),
        pw.Container(
          width: 100,
          alignment: pw.Alignment.centerRight,
          child: pw.Text(val, style: valStyle),
        )
      ]
    )
  );
}

class BeautifulScrollbar extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;
  const BeautifulScrollbar({super.key, required this.child, this.controller});

  @override
  Widget build(BuildContext context) {
    return RawScrollbar(
      controller: controller,
      thumbColor: _kPrimary.withValues(alpha: 0.4),
      radius: const Radius.circular(10),
      thickness: 6,
      fadeDuration: const Duration(milliseconds: 400),
      timeToFade: const Duration(milliseconds: 1000),
      thumbVisibility: true,
      child: child,
    );
  }
}



