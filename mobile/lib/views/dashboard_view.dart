import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/safe_view.dart';
import '../services/api_service.dart';
import '../view_models/dashboard_view_model.dart';
import '../providers/auth_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/staff_provider.dart';
import '../providers/services_provider.dart';
import '../providers/expenses_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/appointments_provider.dart';
import '../providers/salons_provider.dart';
import '../providers/logo_provider.dart';
import '../providers/currency_provider.dart';
import 'staff_management_view.dart';
import 'pos_view.dart';
import 'attendance_view.dart';
import 'service_management_view.dart';
import 'appointments_view.dart';
import 'reports_view.dart';
import 'expenses_view.dart';
import 'clients_view.dart';
import 'inventory_view.dart';
import 'ledger_view.dart';
import '../utils/format_helper.dart';
import 'salon_settings_view.dart';
import '../providers/ledger_provider.dart';
import '../repositories/sync_repository.dart';
import '../providers/connectivity_provider.dart';
import 'payroll_view.dart';
import '../providers/clients_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/reports_provider.dart';
import '../view_models/pos_view_model.dart';

// ─── Bottom nav shows 5 tabs on mobile; sidebar shows all 7 on wide screens ───
const _kPrimary  = Color(0xFF6A11CB);
const _kDark     = Color(0xFF1B1B3A);
const _kGold     = Color(0xFFD4AF37);
const _kBg       = Color(0xFFF4F6FB);

class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  static const _bottomNavItems = [
    (icon: LucideIcons.layoutDashboard, label: 'Home'),
    (icon: LucideIcons.shoppingCart,    label: 'POS'),
    (icon: LucideIcons.calendar,        label: 'Booking'),
    (icon: LucideIcons.clock,           label: 'Attend'),
    (icon: LucideIcons.users,           label: 'Staff'),
  ];

  // Indexes into _allViews

  // Removed static final _allViews to implement lazy loading in layouts
  
  static Widget getView(int index) {
    switch (index) {
      case 0: return const _DashboardMainContent();
      case 1: return const StaffManagementView();
      case 2: return const POSView();
      case 3: return const AttendanceView();
      case 4: return const ServiceManagementView();
      case 5: return const AppointmentsView();
      case 6: return const ReportsView();
      case 7: return const ExpensesView();
      case 8: return const ClientsView();
      case 9: return const InventoryView();
      case 10: return const LedgerView();
      case 11: return const PayrollView();
      default: return const _DashboardMainContent();
    }
  }

  static String getViewName(int index) {
    switch (index) {
      case 0: return 'Dashboard';
      case 1: return 'Staff';
      case 2: return 'POS';
      case 3: return 'Attendance';
      case 4: return 'Services';
      case 5: return 'Appointments';
      case 6: return 'Reports';
      case 7: return 'Expenses';
      case 8: return 'Clients';
      case 9: return 'Inventory';
      case 10: return 'Ledger';
      case 11: return 'Payroll';
      default: return 'Unknown';
    }
  }

  static const _sidebarItems = [
    (icon: LucideIcons.layoutDashboard, label: 'Dashboard',    idx: 0),
    (icon: LucideIcons.shoppingCart,    label: 'POS',          idx: 2),
    (icon: LucideIcons.calendar,        label: 'Appointments', idx: 5),
    (icon: LucideIcons.clock,           label: 'Attendance',   idx: 3),
    (icon: LucideIcons.users,           label: 'Staff',        idx: 1),
    (icon: LucideIcons.scissors,        label: 'Services',     idx: 4),
    (icon: LucideIcons.barChart3,       label: 'Reports',      idx: 6),
    (icon: LucideIcons.package,         label: 'Inventory',    idx: 9),
    (icon: LucideIcons.banknote,        label: 'Expenses',     idx: 7), // Filtered later
    (icon: LucideIcons.users,           label: 'Clients',      idx: 8), // Filtered later
    (icon: LucideIcons.book,            label: 'Ledger',       idx: 10), // Filtered later
    (icon: LucideIcons.banknote,        label: 'Payroll',      idx: 11),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(isOnlineProvider, (previous, next) {
      if (next == true && previous == false) {
        ref.read(syncRepositoryProvider).syncPendingChanges();
      }
    });

    final selectedIndex = ref.watch(navigationIndexProvider);
    final isWide = MediaQuery.of(context).size.width >= 640;

    if (isWide) {
      return _WideLayout(selectedIndex: selectedIndex);
    }
    return _MobileLayout(selectedIndex: selectedIndex);
  }
}

// ─────────────── WIDE (Tablet/Desktop) ───────────────
class _WideLayout extends ConsumerStatefulWidget {
  final int selectedIndex;
  const _WideLayout({required this.selectedIndex});

  @override
  ConsumerState<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends ConsumerState<_WideLayout> {
  final List<Widget?> _viewCache = List.filled(12, null);

  @override
  void didUpdateWidget(covariant _WideLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex && widget.selectedIndex == 0) {
      ref.invalidate(dashboardViewModelProvider);
      ref.invalidate(dashboardMetricsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    print('[Dashboard] Building WideLayout for index ${widget.selectedIndex}');
    // Initialize the view if it hasn't been already
    if (_viewCache[widget.selectedIndex] == null) {
      print('[Dashboard] Initializing view ${DashboardView.getViewName(widget.selectedIndex)}');
      _viewCache[widget.selectedIndex] = SafeView(
        viewName: DashboardView.getViewName(widget.selectedIndex),
        child: DashboardView.getView(widget.selectedIndex),
      );
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: Row(
        children: [
          _Sidebar(selectedIndex: widget.selectedIndex),
          Expanded(
            child: Column(
              children: [
                if (user?['originalSuperAdmin'] != null)
                  Container(
                    width: double.infinity,
                    color: Colors.amber.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Impersonation Mode: Viewing branch "${user?['salon']?['name'] ?? 'Branch'}" as Super Admin',
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        InkWell(
                          onTap: () async {
                            final original = user?['originalSuperAdmin'];
                            if (original != null) {
                              final originalToken = original['token'];
                              await const FlutterSecureStorage().write(key: 'token', value: originalToken);
                              final cleanOriginal = Map<String, dynamic>.from(original)..remove('token');
                              
                              await ref.read(authProvider.notifier).refreshUser(cleanOriginal);
                              ref.invalidate(dashboardViewModelProvider);
                              ref.invalidate(dashboardMetricsProvider);
                              ref.invalidate(staffProvider);
                              ref.invalidate(servicesProvider);
                              ref.invalidate(expensesProvider);
                              ref.invalidate(attendanceProvider);
                              ref.invalidate(appointmentsProvider);
                              ref.invalidate(salonsProvider);
                              ref.invalidate(logoProvider);
                              ref.invalidate(navigationIndexProvider);
                              ref.invalidate(clientsProvider);
                              ref.invalidate(ledgerProvider);
                              ref.invalidate(inventoryProvider);
                              ref.invalidate(posProvider);
                              ref.invalidate(reportsProvider);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Return to Admin',
                              style: GoogleFonts.outfit(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: widget.selectedIndex,
                    children: List.generate(12, (i) => _viewCache[i] ?? const SizedBox.shrink()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────── MOBILE ───────────────
class _MobileLayout extends ConsumerStatefulWidget {
  final int selectedIndex;
  const _MobileLayout({required this.selectedIndex});

  @override
  ConsumerState<_MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends ConsumerState<_MobileLayout> {
  final List<Widget?> _viewCache = List.filled(12, null);

  @override
  void didUpdateWidget(covariant _MobileLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex && widget.selectedIndex == 0) {
      ref.invalidate(dashboardViewModelProvider);
      ref.invalidate(dashboardMetricsProvider);
    }
  }

  void _onNavTap(int pos, List filteredItems) {
    final item = filteredItems[pos];
    int viewIdx = 0;
    if (item.label == 'Home') {
      viewIdx = 0;
    } else if (item.label == 'POS') viewIdx = 2;
    else if (item.label == 'Booking') viewIdx = 5;
    else if (item.label == 'Attend') viewIdx = 3;
    else if (item.label == 'Staff') viewIdx = 1;

    ref.read(navigationIndexProvider.notifier).state = viewIdx;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isStaff = user?['role'] == 'STAFF';

    final filteredBottomItems = DashboardView._bottomNavItems.where((item) {
      if (isStaff && item.label == 'Staff') return false;
      return true;
    }).toList();

    final curIdx = widget.selectedIndex;
    // Map the global view index back to bottom nav position
    final bottomPos = filteredBottomItems.indexWhere((item) {
       if (item.label == 'Home' && curIdx == 0) return true;
       if (item.label == 'POS' && curIdx == 2) return true;
       if (item.label == 'Booking' && curIdx == 5) return true;
       if (item.label == 'Attend' && curIdx == 3) return true;
       if (item.label == 'Staff' && curIdx == 1) return true;
       return false;
    });

    final isSyncing = ref.watch(syncStatusProvider);
    print('[Dashboard] Building MobileLayout for index $curIdx');
    
    // Initialize the view if it hasn't been already
    if (_viewCache[curIdx] == null) {
      print('[Dashboard] Initializing view ${DashboardView.getViewName(curIdx)}');
      _viewCache[curIdx] = SafeView(
        viewName: DashboardView.getViewName(curIdx),
        child: DashboardView.getView(curIdx),
      );
    }

    return Scaffold(
      backgroundColor: _kBg,
      endDrawer: _MobileDrawer(selectedIndex: curIdx),
      body: Column(
        children: [
          if (user?['originalSuperAdmin'] != null)
            Container(
              width: double.infinity,
              color: Colors.amber.shade700,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Impersonating: ${user?['salon']?['name'] ?? 'Branch'}',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      final original = user?['originalSuperAdmin'];
                      if (original != null) {
                        final originalToken = original['token'];
                        await const FlutterSecureStorage().write(key: 'token', value: originalToken);
                        final cleanOriginal = Map<String, dynamic>.from(original)..remove('token');
                        
                        await ref.read(authProvider.notifier).refreshUser(cleanOriginal);
                        ref.invalidate(dashboardViewModelProvider);
                        ref.invalidate(dashboardMetricsProvider);
                        ref.invalidate(staffProvider);
                        ref.invalidate(servicesProvider);
                        ref.invalidate(expensesProvider);
                        ref.invalidate(attendanceProvider);
                        ref.invalidate(appointmentsProvider);
                        ref.invalidate(salonsProvider);
                        ref.invalidate(logoProvider);
                        ref.invalidate(navigationIndexProvider);
                        ref.invalidate(clientsProvider);
                        ref.invalidate(ledgerProvider);
                        ref.invalidate(inventoryProvider);
                        ref.invalidate(posProvider);
                        ref.invalidate(reportsProvider);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Return',
                        style: GoogleFonts.outfit(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: curIdx,
              children: List.generate(12, (i) => _viewCache[i] ?? const SizedBox.shrink()),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                ...List.generate(filteredBottomItems.length, (i) {
                  final item = filteredBottomItems[i];
                  final isActive = bottomPos == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onNavTap(i, filteredBottomItems),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: isActive ? _kPrimary.withValues(alpha: 0.1) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              item.icon,
                              size: 22,
                              color: isActive ? _kPrimary : Colors.black38,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              color: isActive ? _kPrimary : Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                // "More" button opens end drawer
                Expanded(
                  child: Builder(builder: (ctx) => GestureDetector(
                    onTap: () => Scaffold.of(ctx).openEndDrawer(),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                              child: const Icon(LucideIcons.menu, size: 22, color: Colors.black38),
                            ),
                            if (isSyncing)
                              Positioned(
                                top: 0, right: 6,
                                child: Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('More', style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38)),
                      ],
                    ),
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────── MOBILE DRAWER ───────────────
class _MobileDrawer extends ConsumerWidget {
  final int selectedIndex;
  const _MobileDrawer({required this.selectedIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);

    return Drawer(
      backgroundColor: Colors.white,
      width: 280,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kPrimary, Color(0xFF2575FC)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Consumer(builder: (context, ref, _) {
                    final bytes = ref.watch(logoProvider);
                    if (bytes != null) {
                      return CircleAvatar(
                        radius: 30,
                        backgroundImage: MemoryImage(bytes),
                        backgroundColor: Colors.white24,
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.store, color: Colors.white, size: 28),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(
                    user?['name'] ?? 'Admin',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if (user?['salon'] != null)
                    Text(
                      user?['salon']['name'] ?? '',
                      style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  Text(
                    user?['email'] ?? '',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Extra nav items
            if (user?['role'] != 'STAFF') ...[
              _DrawerItem(icon: LucideIcons.scissors,  label: 'Services', onTap: () {
                Navigator.pop(context);
                ref.read(navigationIndexProvider.notifier).state = 4;
              }),
              const Divider(indent: 16, endIndent: 16),
            ],
            _DrawerItem(icon: LucideIcons.barChart3, label: 'Reports',  onTap: () {
              Navigator.pop(context);
              ref.read(navigationIndexProvider.notifier).state = 6;
            }),
            const Divider(indent: 16, endIndent: 16),
            if (user?['role'] != 'STAFF') ...[
              _DrawerItem(icon: LucideIcons.banknote, label: 'Expenses', onTap: () {
                Navigator.pop(context);
                ref.read(navigationIndexProvider.notifier).state = 7;
              }),
              const Divider(indent: 16, endIndent: 16),
              _DrawerItem(icon: LucideIcons.users, label: 'Clients', onTap: () {
                Navigator.pop(context);
                ref.read(navigationIndexProvider.notifier).state = 8;
              }),
              const Divider(indent: 16, endIndent: 16),
            ],
            if (user?['role'] != 'STAFF') ...[
              _DrawerItem(icon: LucideIcons.package, label: 'Inventory', onTap: () {
                Navigator.pop(context);
                ref.read(navigationIndexProvider.notifier).state = 9;
              }),
              const Divider(indent: 16, endIndent: 16),
            ],
            if (user?['role'] != 'STAFF') ...[
              _DrawerItem(icon: LucideIcons.book, label: 'Ledger', onTap: () {
                Navigator.pop(context);
                ref.read(navigationIndexProvider.notifier).state = 10;
              }),
              const Divider(indent: 16, endIndent: 16),
              _DrawerItem(icon: LucideIcons.banknote, label: 'Payroll', onTap: () {
                Navigator.pop(context);
                ref.read(navigationIndexProvider.notifier).state = 11;
              }),
              const Divider(indent: 16, endIndent: 16),
              _DrawerItem(icon: LucideIcons.settings, label: 'Salon Settings', color: Colors.indigo, onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SalonSettingsView()));
              }),
              const Divider(indent: 16, endIndent: 16),
              _DrawerItem(icon: LucideIcons.trash2, label: 'Clear History', color: Colors.orange, onTap: () {
                Navigator.pop(context);
                _showClearHistoryDialog(context, ref);
              }),
              const Divider(indent: 16, endIndent: 16),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.globe, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 16),
                  Text('Currency:', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: ref.watch(currencyProvider),
                        items: ['PKR', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'OMR', 'KWD', 'BHD', 'QAR', 'INR', 'BDT', 'NPR', 'LKR', 'CAD', 'AUD', 'SGD', 'NZD', 'JPY', 'CNY', 'RUB', 'TRY', 'ZAR', 'NGN', 'EGP', 'BRL', 'MXN', 'MYR', 'IDR', 'PHP', 'THB']
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kPrimary)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref.read(currencyProvider.notifier).setCurrency(val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            _DrawerItem(icon: LucideIcons.logOut, label: 'Logout', color: Colors.redAccent, onTap: () async {
              Navigator.pop(context);
              try {
                await ref.read(apiServiceProvider).logout();
              } catch (_) {}
              await ref.read(authProvider.notifier).logout();
              
              // Invalidate additional cached providers locally to be absolutely sure
              ref.invalidate(dashboardViewModelProvider);
              ref.invalidate(dashboardMetricsProvider);
              ref.invalidate(staffProvider);
              ref.invalidate(servicesProvider);
              ref.invalidate(expensesProvider);
              ref.invalidate(attendanceProvider);
              ref.invalidate(appointmentsProvider);
              ref.invalidate(salonsProvider);
              ref.invalidate(logoProvider);
              ref.invalidate(navigationIndexProvider);
              ref.invalidate(clientsProvider);
              ref.invalidate(ledgerProvider);
              ref.invalidate(inventoryProvider);
              ref.invalidate(posProvider);
              ref.invalidate(reportsProvider);
            }),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Salon Pro v1.0', style: GoogleFonts.outfit(color: Colors.black26, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _DrawerItem({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? _kDark;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: c),
      ),
      title: Text(label, style: GoogleFonts.outfit(color: c, fontWeight: FontWeight.w500)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

// ─────────────── SIDEBAR (Wide) ───────────────
class _Sidebar extends ConsumerWidget {
  final int selectedIndex;
  const _Sidebar({required this.selectedIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20)],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Consumer(builder: (context, ref, _) {
                      final bytes = ref.watch(logoProvider);
                      if (bytes != null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundImage: MemoryImage(bytes),
                            backgroundColor: Colors.transparent,
                          ),
                        );
                      }
                      return Column(
                        children: [
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.store, color: _kPrimary, size: 22),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  user?['salon']?['name'] ?? 'Salon Pro', 
                                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }),
                    const Divider(indent: 16, endIndent: 16),
                    ...DashboardView._sidebarItems.where((e) {
                      if (user?['role'] == 'STAFF' && (
                        e.label == 'Staff' || 
                        e.label == 'Services' || 
                        e.label == 'Expenses' || 
                        e.label == 'Clients' || 
                        e.label == 'Ledger' ||
                        e.label == 'Inventory' ||
                        e.label == 'Payroll'
                      )) return false;
                      return true;
                    }).map((e) => _SidebarItem(
                      icon: e.icon, title: e.label,
                      isActive: selectedIndex == e.idx,
                      onTap: () => ref.read(navigationIndexProvider.notifier).state = e.idx,
                    )),
                    if (user?['role'] == 'OWNER') ...[
                      const Divider(indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: _SidebarItem(
                          icon: LucideIcons.settings, title: 'Settings',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalonSettingsView())),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(indent: 16, endIndent: 16, height: 1),
            if (user?['originalSuperAdmin'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _SidebarItem(
                  icon: LucideIcons.arrowLeftCircle, title: 'Return to Admin',
                  activeColor: Colors.blueAccent,
                  onTap: () async {
                    final original = user?['originalSuperAdmin'];
                    if (original != null) {
                      final originalToken = original['token'];
                      await const FlutterSecureStorage().write(key: 'token', value: originalToken);
                      final cleanOriginal = Map<String, dynamic>.from(original)..remove('token');
                      
                      await ref.read(authProvider.notifier).refreshUser(cleanOriginal);
                      ref.invalidate(dashboardViewModelProvider);
                      ref.invalidate(dashboardMetricsProvider);
                      ref.invalidate(staffProvider);
                      ref.invalidate(servicesProvider);
                      ref.invalidate(expensesProvider);
                      ref.invalidate(attendanceProvider);
                      ref.invalidate(appointmentsProvider);
                      ref.invalidate(salonsProvider);
                      ref.invalidate(logoProvider);
                      ref.invalidate(navigationIndexProvider);
                      ref.invalidate(clientsProvider);
                      ref.invalidate(ledgerProvider);
                      ref.invalidate(inventoryProvider);
                      ref.invalidate(posProvider);
                      ref.invalidate(reportsProvider);
                    }
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _SidebarItem(
                icon: LucideIcons.logOut, title: 'Logout',
                activeColor: Colors.redAccent,
                onTap: () async {
                  try {
                    await ref.read(apiServiceProvider).logout();
                  } catch (_) {}
                  await ref.read(authProvider.notifier).logout();
                  
                  // Invalidate all cached providers
                  ref.invalidate(dashboardViewModelProvider);
                  ref.invalidate(dashboardMetricsProvider);
                  ref.invalidate(staffProvider);
                  ref.invalidate(servicesProvider);
                  ref.invalidate(expensesProvider);
                  ref.invalidate(attendanceProvider);
                  ref.invalidate(appointmentsProvider);
                  ref.invalidate(salonsProvider);
                  ref.invalidate(logoProvider);
                  ref.invalidate(navigationIndexProvider);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isActive;
  final VoidCallback? onTap;
  final Color? activeColor;

  const _SidebarItem({
    required this.icon, required this.title,
    this.isActive = false, this.onTap, this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? _kPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? color : Colors.black38, size: 20),
            const SizedBox(width: 12),
            Text(title, style: GoogleFonts.outfit(
              color: isActive ? _kDark : Colors.black38,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }
}

// ─────────────── DASHBOARD HOME CONTENT ───────────────
class _DashboardMainContent extends ConsumerWidget {
  const _DashboardMainContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsState = ref.watch(dashboardViewModelProvider);
    final user = ref.watch(authProvider);
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 640;

    DateTime? subEnd;
    bool isNearExpiry = false;
    if (user != null && user['salon'] != null) {
      final subEndStr = user['salon']['subscriptionEnd']?.toString() ?? '';
      if (subEndStr.isNotEmpty) {
        subEnd = DateTime.tryParse(subEndStr);
        if (subEnd != null) {
          final daysLeft = subEnd!.difference(DateTime.now()).inDays;
          isNearExpiry = daysLeft >= 0 && daysLeft <= 7;
        }
      }
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.read(dashboardViewModelProvider.notifier).fetchMetrics(),
        color: _kPrimary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(isWide ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNearExpiry) ...[
                _SubscriptionBanner(subEnd: subEnd!),
                const SizedBox(height: 14),
              ],
              if (user?['role'] != 'STAFF')
                metricsState.when(
                  data: (m) {
                    final alerts = m['inventoryAlerts'];
                    if (alerts == null) return const SizedBox.shrink();
                    final lowCount = alerts['lowStockCount'] ?? 0;
                    final expiryCount = alerts['nearExpiryCount'] ?? 0;
                    if (lowCount == 0 && expiryCount == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _InventoryAlertsBanner(
                        lowCount: lowCount, 
                        expiryCount: expiryCount,
                        lowStockItems: alerts['lowStockItems'] ?? [],
                        nearExpiryItems: alerts['nearExpiryItems'] ?? [],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              _Header(name: user?['name'] ?? 'Admin', isWide: isWide),
              const SizedBox(height: 24),
              _MetricsGrid(metricsState: metricsState, isWide: isWide),
              const SizedBox(height: 24),
              _RecentActivitySection(metricsState: metricsState),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  final DateTime subEnd;
  const _SubscriptionBanner({required this.subEnd});

  @override
  Widget build(BuildContext context) {
    final days = subEnd.difference(DateTime.now()).inDays;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, color: Colors.orange.shade700, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Subscription expires in $days days (${subEnd.day}/${subEnd.month}/${subEnd.year})',
              style: GoogleFonts.outfit(color: Colors.orange.shade800, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    ).animate().shake();
  }
}

class _InventoryAlertsBanner extends StatelessWidget {
  final int lowCount;
  final int expiryCount;
  final List lowStockItems;
  final List nearExpiryItems;

  const _InventoryAlertsBanner({
    required this.lowCount, 
    required this.expiryCount,
    required this.lowStockItems,
    required this.nearExpiryItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertCircle, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 10),
              Text(
                'Inventory Alerts',
                style: GoogleFonts.outfit(color: Colors.red.shade800, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (lowCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '• $lowCount items are low in stock: ${lowStockItems.take(3).map((i) => i['name']).join(', ')}${lowStockItems.length > 3 ? '...' : ''}',
              style: GoogleFonts.outfit(color: Colors.red.shade700, fontSize: 13),
            ),
          ],
          if (expiryCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '• $expiryCount items are expiring within 30 days: ${nearExpiryItems.take(3).map((i) => i['name']).join(', ')}${nearExpiryItems.length > 3 ? '...' : ''}',
              style: GoogleFonts.outfit(color: Colors.red.shade700, fontSize: 13),
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.2);
  }
}

class _Header extends ConsumerWidget {
  final String name;
  final bool isWide;
  const _Header({required this.name, required this.isWide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSyncing = ref.watch(syncStatusProvider);
    final user = ref.watch(authProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Good day 👋', style: GoogleFonts.outfit(fontSize: 14, color: Colors.black45)),
              Text(
                name,
                style: GoogleFonts.outfit(fontSize: isWide ? 28 : 22, fontWeight: FontWeight.bold, color: _kDark),
              ),
            ],
          ),
        ),
        if (isSyncing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade400)),
                const SizedBox(width: 6),
                Text('Syncing', style: GoogleFonts.outfit(color: Colors.blue.shade700, fontSize: 11)),
              ],
            ),
          )
        else
        Consumer(builder: (context, ref, _) {
          final bytes = ref.watch(logoProvider);
          if (bytes != null) {
            return Container(
              margin: const EdgeInsets.only(left: 12),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
              ),
            );
          }
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
            child: const Icon(LucideIcons.bell, color: _kPrimary, size: 20),
          );
        }),
      ],
    ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.05);
  }
}

class _MetricsGrid extends ConsumerWidget {
  final AsyncValue<Map<String, dynamic>> metricsState;
  final bool isWide;
  const _MetricsGrid({required this.metricsState, required this.isWide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final user = ref.watch(authProvider);
    final isStaff = user?['role'] == 'STAFF';

    return metricsState.when(
      data: (m) {
        if (isStaff) {
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isWide ? 2 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isWide ? 1.4 : 1.25,
            children: [
              _MetricCard(
                label: 'My Revenue',
                value: '$currency ${formatAmount(double.tryParse(m['totalSales']?.toString() ?? '0') ?? 0.0)}',
                change: '+${m['recentGrowth'] ?? 0}%',
                icon: LucideIcons.trendingUp,
                accent: const Color(0xFF22C55E),
              ),
              _MetricCard(
                label: 'My Growth',
                value: '${m['recentGrowth'] ?? 0}%',
                change: '30 Days',
                icon: LucideIcons.barChart2,
                accent: const Color(0xFF3B82F6),
              ),
            ],
          );
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isWide ? 3 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: isWide ? 1.4 : 1.25,
          children: [
            _MetricCard(label: 'Total Cash Collected', value: '$currency ${formatAmount(double.tryParse(m['totalSales']?.toString() ?? '0') ?? 0.0)}', change: '+${m['recentGrowth'] ?? 0}%', icon: LucideIcons.trendingUp, accent: const Color(0xFF22C55E)),
            _MetricCard(label: 'Cash Collected', value: '$currency ${formatAmount(double.tryParse(m['cashSales']?.toString() ?? '0') ?? 0.0)}', change: 'Cash', icon: LucideIcons.banknote, accent: const Color(0xFF10B981)),
            _MetricCard(label: 'Online Collected', value: '$currency ${formatAmount(double.tryParse(m['onlineSales']?.toString() ?? '0') ?? 0.0)}', change: 'Online', icon: LucideIcons.creditCard, accent: const Color(0xFF3B82F6)),
            _MetricCard(label: 'Staff', value: '${m['staffCount'] ?? 0}', change: 'Active', icon: LucideIcons.users, accent: const Color(0xFF8B5CF6)),
            _MetricCard(label: 'Services', value: '${m['serviceCount'] ?? 0}', change: 'Listed', icon: LucideIcons.scissors, accent: _kPrimary),
            (() {
              final bal = double.tryParse((m['cashBalance'] ?? m['drawerBalance'])?.toString() ?? '0') ?? 0.0;
              return _MetricCard(
                label: 'Cash Drawer',
                value: '$currency ${formatAmount(bal)}',
                change: 'On Hand',
                icon: LucideIcons.wallet,
                accent: bal < 0 ? Colors.redAccent : const Color(0xFFF59E0B),
              );
            })(),
            (() {
              final balOnline = double.tryParse((m['onlineBalance'] ?? m['onlineDrawerBalance'])?.toString() ?? '0') ?? 0.0;
              final breakdown = (m['onlineBreakdown'] ?? m['drawerBalances']?['onlineBreakdown']) as Map<String, dynamic>? ?? {};
              return _MetricCard(
                label: 'Online Balance',
                value: '$currency ${formatAmount(balOnline)}',
                change: breakdown.isNotEmpty ? '${breakdown.length} Accounts' : 'In Account',
                icon: LucideIcons.creditCard,
                accent: balOnline < 0 ? Colors.redAccent : const Color(0xFF0284C7),
                onTap: breakdown.isNotEmpty ? () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(LucideIcons.landmark, size: 20, color: Color(0xFF0284C7)),
                          ),
                          const SizedBox(width: 12),
                          Text('Online Accounts Breakdown', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                      content: SizedBox(
                        width: 360,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Total Online Balance', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                                  Text('$currency ${formatAmount(balOnline)}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF0284C7), fontSize: 16)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            ...breakdown.entries.map((e) {
                              final amt = (e.value as num?)?.toDouble() ?? 0.0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(LucideIcons.landmark, size: 14, color: Colors.black54),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(e.key, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                                    ),
                                    Text('$currency ${formatAmount(amt)}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text('Close', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                } : null,
              );
            })(),
          ],
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14)),
        child: Text('Could not load metrics', style: GoogleFonts.outfit(color: Colors.red.shade600)),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label, value, change;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  const _MetricCard({required this.label, required this.value, required this.change, required this.icon, required this.accent, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: accent, size: 18),
              ),
              Text(change, style: GoogleFonts.outfit(color: accent, fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
            const Spacer(),
            Text(label, style: GoogleFonts.outfit(color: Colors.black45, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.outfit(color: _kDark, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ).animate().scale(duration: 350.ms, curve: Curves.easeOut);
  }
}

class _RecentActivitySection extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>> metricsState;
  const _RecentActivitySection({required this.metricsState});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Activity', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: _kDark)),
        const SizedBox(height: 14),
        metricsState.when(
          data: (m) {
            final activities = (m['recentActivity'] as List?) ?? [];
            if (activities.isEmpty) return Center(child: Text('No recent activity', style: GoogleFonts.outfit(color: Colors.black26)));
            return Column(
              children: activities.map((a) => _ActivityTile(activity: a)).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> activity;
  const _ActivityTile({required this.activity});

  String _formatTimestamp(String ts) {
    final date = DateTime.parse(ts).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    final type = activity['type'];
    final isSale = type == 'SALE';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: (isSale ? Colors.green : _kPrimary).withValues(alpha: 0.08),
            child: Icon(isSale ? LucideIcons.banknote : LucideIcons.calendar, color: isSale ? Colors.green : _kPrimary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(activity['title'] ?? 'Activity', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: _kDark)),
              Text(activity['subtitle'] ?? '', style: GoogleFonts.outfit(color: Colors.black45, fontSize: 12)),
            ]),
          ),
          Text(_formatTimestamp(activity['timestamp']), style: GoogleFonts.outfit(color: Colors.black26, fontSize: 11)),
        ],
      ),
    );
  }
}

void _showClearHistoryDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  const phrase = 'PERMANENTLY DELETE HISTORY';
  bool isDeleting = false;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(LucideIcons.alertTriangle, color: Colors.orange),
            const SizedBox(width: 12),
            const Text('Clear All History?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will PERMANENTLY delete all Sales, Expenses, Attendance, Ledger, and Appointment records.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text(
              'Core data like Staff, Services, Clients, Vendors, and Inventory Stock will remain intact.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Text('Type "$phrase" to confirm:', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Type confirmation phrase...',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: (controller.text == phrase && !isDeleting) ? () async {
              setState(() => isDeleting = true);
              try {
                await ref.read(apiServiceProvider).clearHistory(phrase);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('History cleared successfully!'), backgroundColor: Colors.green),
                  );
                  // Refresh metrics
                  ref.invalidate(dashboardViewModelProvider);
                }
              } catch (e) {
                if (context.mounted) {
                  setState(() => isDeleting = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            } : null,
            child: isDeleting 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Clear Everything', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
}
