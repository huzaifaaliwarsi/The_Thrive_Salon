import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/salons_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/staff_provider.dart';
import '../providers/services_provider.dart';
import '../providers/expenses_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/appointments_provider.dart';
import '../services/api_service.dart';
import '../providers/logo_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/clients_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/reports_provider.dart';
import '../view_models/dashboard_view_model.dart';
import '../view_models/pos_view_model.dart';
import 'reports_view.dart';
import '../utils/format_helper.dart';

const _kPrimary  = Color(0xFF6A11CB);
const _kDark     = Color(0xFF1B1B3A);
const _kBg       = Color(0xFFF4F6FB);

class SuperAdminDashboard extends ConsumerStatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  ConsumerState<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends ConsumerState<SuperAdminDashboard> {
  int _selectedMenuIndex = 0;
  String? _selectedBranchIdForReports;
  String? _selectedBranchNameForReports;
  
  String? _selectedBranchIdForAttendance;
  List<dynamic>? _branchAttendanceLogs;
  bool _loadingAttendance = false;

  final _addNameC = TextEditingController();
  final _addAddrC = TextEditingController();
    final _addQrC = TextEditingController(text: 'salonpro.app');
  final _addEmailC = TextEditingController();
  final _addPassC = TextEditingController();
  final _addVatC = TextEditingController();

  final List<String> _timezones = [
    'Asia/Karachi',
    'UTC',
    'Asia/Dubai',
    'Asia/Riyadh',
    'Asia/Muscat',
    'Asia/Qatar',
    'Asia/Kuwait',
    'Asia/Bahrain',
    'Asia/Singapore',
    'Asia/Kolkata',
    'Asia/Dhaka',
    'Asia/Kathmandu',
    'Asia/Colombo',
    'Europe/London',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Australia/Sydney',
    'Africa/Lagos',
    'Africa/Cairo',
    'Europe/Istanbul',
    'America/Sao_Paulo',
    'America/Mexico_City',
    'Asia/Kuala_Lumpur',
    'Asia/Jakarta',
    'Asia/Manila',
    'Asia/Bangkok',
  ];
  String _addTimezone = 'Asia/Karachi';
  String _addInTime = '09:00';
  String _addLateTime = '09:15';
  String _addOutTime = '18:00';
  String _addEarlyExitTime = '17:45';

  Future<void> _logout() async {
    try {
      await ref.read(apiServiceProvider).logout();
    } catch (_) {}
    await ref.read(authProvider.notifier).logout();
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
  }

  Future<List<Map<String, dynamic>>> _loadAllMetrics(List<dynamic> salons) async {
    final api = ref.read(apiServiceProvider);
    return await Future.wait(salons.map((salon) async {
      try {
        final m = await api.getDashboardMetrics(salonId: salon['id']);
        return {
          'salonId': salon['id'],
          'salonName': salon['name'],
          'totalSales': double.tryParse(m['totalSales']?.toString() ?? '0') ?? 0.0,
          'staffCount': int.tryParse(m['staffCount']?.toString() ?? '0') ?? 0,
          'serviceCount': int.tryParse(m['serviceCount']?.toString() ?? '0') ?? 0,
          'recentGrowth': double.tryParse(m['recentGrowth']?.toString() ?? '0') ?? 0.0,
          'cashBalance': double.tryParse((m['cashBalance'] ?? m['drawerBalance'])?.toString() ?? '0') ?? 0.0,
          'onlineBalance': double.tryParse((m['onlineBalance'] ?? m['onlineDrawerBalance'])?.toString() ?? '0') ?? 0.0,
        };
      } catch (e) {
        return {
          'salonId': salon['id'],
          'salonName': salon['name'],
          'totalSales': 0.0,
          'staffCount': 0,
          'serviceCount': 0,
          'recentGrowth': 0.0,
          'cashBalance': 0.0,
          'onlineBalance': 0.0,
        };
      }
    }));
  }

  Future<void> _fetchBranchAttendance(String branchId) async {
    setState(() {
      _loadingAttendance = true;
      _branchAttendanceLogs = null;
    });
    try {
      final logs = await ref.read(apiServiceProvider).getAttendance(salonId: branchId);
      setState(() {
        _branchAttendanceLogs = logs;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load attendance: $e')));
      }
    } finally {
      setState(() {
        _loadingAttendance = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final salonsAsync = ref.watch(salonsProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 800;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: Text(
                _getMenuTitle(),
                style: GoogleFonts.outfit(color: _kDark, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              actions: [
                IconButton(icon: const Icon(LucideIcons.logOut, color: Colors.black26), onPressed: _logout),
                const SizedBox(width: 8),
              ],
            ),
      drawer: isDesktop ? null : Drawer(child: _buildSidebarContent()),
      body: salonsAsync.when(
        data: (salons) {
          if (salons.isEmpty && _selectedMenuIndex != 4) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.scissors, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('No Branches Registered', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => setState(() => _selectedMenuIndex = 4),
                    child: const Text('Open New Branch'),
                  ),
                ],
              ),
            );
          }

          final bodyContent = _buildActiveView(salons);

          if (isDesktop) {
            return Row(
              children: [
                SizedBox(
                  width: 250,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(right: BorderSide(color: Colors.black12)),
                    ),
                    child: _buildSidebarContent(),
                  ),
                ),
                Expanded(child: bodyContent),
              ],
            );
          }

          return bodyContent;
        },
        loading: () => const Center(child: CircularProgressIndicator(color: _kPrimary)),
        error: (e, _) => Center(child: Text('Error: $e', style: GoogleFonts.outfit())),
      ),
    );
  }

  String _getMenuTitle() {
    switch (_selectedMenuIndex) {
      case 0:
        return 'BI Intelligence';
      case 1:
        return 'Branches List';
      case 2:
        return 'Branch Reports';
      case 3:
        return 'Branch Attendance';
      case 4:
        return 'Open New Branch';
      default:
        return 'Super Admin';
    }
  }

  Widget _buildSidebarContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.scissors, color: _kPrimary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Salon Pro', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: _kDark)),
                    Text('Network Manager', style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.black12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            children: [
              _sidebarItem(0, LucideIcons.barChart3, 'BI Intelligence'),
              _sidebarItem(1, LucideIcons.layers, 'Branches List'),
              _sidebarItem(2, LucideIcons.fileText, 'Branch Reports'),
              _sidebarItem(3, LucideIcons.calendar, 'Branch Attendance'),
              _sidebarItem(4, LucideIcons.plusCircle, 'Open New Branch'),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.black12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              const Icon(LucideIcons.globe, size: 18, color: Colors.black38),
              const SizedBox(width: 12),
              Text('Currency:', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black45)),
              const SizedBox(width: 8),
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
        const Divider(height: 1, color: Colors.black12),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          leading: const Icon(LucideIcons.logOut, color: Colors.redAccent),
          title: Text('Sign Out', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
          onTap: _logout,
        ),
      ],
    );
  }

  Widget _sidebarItem(int index, IconData icon, String label) {
    final isSelected = _selectedMenuIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedMenuIndex = index;
          });
          if (MediaQuery.of(context).size.width < 800) {
            Navigator.pop(context); // Close Drawer
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? _kPrimary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? _kPrimary : Colors.black45, size: 20),
              const SizedBox(width: 16),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: isSelected ? _kPrimary : Colors.black54,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveView(List<dynamic> salons) {
    switch (_selectedMenuIndex) {
      case 0:
        return _buildBIView(salons);
      case 1:
        return _buildBranchesView(salons);
      case 2:
        return _buildReportsView(salons);
      case 3:
        return _buildAttendanceView(salons);
      case 4:
        return _buildRegisterBranchView();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- 1. Global BI Dashboard ---
  Widget _buildBIView(List<dynamic> salons) {
    final currency = ref.watch(currencyProvider);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadAllMetrics(salons),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _kPrimary));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to load metrics: ${snapshot.error}'));
        }

        final metricsList = snapshot.data ?? [];
        final totalSales = metricsList.map((m) => m['totalSales'] as double).fold(0.0, (a, b) => a + b);
        final totalStaff = metricsList.map((m) => m['staffCount'] as int).fold(0, (a, b) => a + b);
        final totalServices = metricsList.map((m) => m['serviceCount'] as int).fold(0, (a, b) => a + b);
        final totalCashDrawer = metricsList.map((m) => m['cashBalance'] as double).fold(0.0, (a, b) => a + b);
        final totalOnlineBalance = metricsList.map((m) => (m['onlineBalance'] ?? 0.0) as double).fold(0.0, (a, b) => a + b);

        final isWide = MediaQuery.of(context).size.width >= 800;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Network Summary', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isWide ? 6 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: isWide ? 1.2 : 1.25,
                children: [
                  _statCard('Total Sales', '$currency ${formatAmount(totalSales)}', LucideIcons.trendingUp, Colors.green),
                  _statCard('Total Cash Drawer', '$currency ${formatAmount(totalCashDrawer)}', LucideIcons.wallet, const Color(0xFFF59E0B)),
                  _statCard('Online Balance', '$currency ${formatAmount(totalOnlineBalance)}', LucideIcons.creditCard, const Color(0xFF0284C7)),
                  _statCard('Active Branches', '${salons.length}', LucideIcons.home, _kPrimary),
                  _statCard('Total Staff', '$totalStaff', LucideIcons.users, Colors.blue),
                  _statCard('Services List', '$totalServices', LucideIcons.scissors, Colors.orange),
                ],
              ),
              const SizedBox(height: 24),
              if (metricsList.isNotEmpty) ...[
                _buildCustomColumnChart(metricsList),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    SizedBox(
                      width: isWide ? (MediaQuery.of(context).size.width - 350) / 2 : double.infinity,
                      child: _buildCustomRevenueShare(metricsList, totalSales),
                    ),
                    SizedBox(
                      width: isWide ? (MediaQuery.of(context).size.width - 350) / 2 : double.infinity,
                      child: _buildCustomStaffStrength(metricsList),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCustomColumnChart(List<Map<String, dynamic>> metricsList) {
    final currency = ref.watch(currencyProvider);
    final maxSales = metricsList.map((m) => m['totalSales'] as double).fold(0.0, (a, b) => b > a ? b : a);
    final scaleMax = maxSales > 0 ? maxSales : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Branch Sales Comparison', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark)),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: metricsList.map((m) {
                final sales = m['totalSales'] as double;
                final pct = sales / scaleMax;
                final barHeight = 150 * pct;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '$currency ${formatAmount(sales / 1000)}k',
                        style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: _kPrimary),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutBack,
                        width: 36,
                        height: barHeight > 12 ? barHeight : 12,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_kPrimary, Color(0xFF8E2DE2)],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          boxShadow: [
                            BoxShadow(
                              color: _kPrimary.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        m['salonName'] as String,
                        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomRevenueShare(List<Map<String, dynamic>> metricsList, double totalSales) {
    final currency = ref.watch(currencyProvider);
    final colors = [
      _kPrimary,
      Colors.blueAccent,
      Colors.green,
      Colors.orange,
      Colors.redAccent,
      Colors.teal,
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Revenue Share By Branch', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark)),
          const SizedBox(height: 20),
          Column(
            children: List.generate(metricsList.length, (idx) {
              final m = metricsList[idx];
              final sales = m['totalSales'] as double;
              final sharePct = totalSales > 0 ? (sales / totalSales * 100) : 0.0;
              final color = colors[idx % colors.length];

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(
                              m['salonName'] as String,
                              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kDark),
                            ),
                          ],
                        ),
                        Text(
                          '$currency ${formatAmount(sales)} (${formatAmount(sharePct, decimals: 1)}%)',
                          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: sharePct / 100,
                        backgroundColor: Colors.black.withValues(alpha: 0.03),
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomStaffStrength(List<Map<String, dynamic>> metricsList) {
    final maxStaff = metricsList.map((m) => m['staffCount'] as int).fold(0, (a, b) => b > a ? b : a);
    final scaleMax = maxStaff > 0 ? maxStaff : 1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Branch Staff Strength', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark)),
          const SizedBox(height: 20),
          Column(
            children: metricsList.map((m) {
              final staffCount = m['staffCount'] as int;
              final pct = staffCount / scaleMax;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          m['salonName'] as String,
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kDark),
                        ),
                        Text(
                          '$staffCount Staff',
                          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Colors.black.withValues(alpha: 0.03),
                        color: Colors.blueAccent,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: GoogleFonts.outfit(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500)),
                Text(val, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: _kDark), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. Manage Branches ---
  Widget _buildBranchesView(List<dynamic> salons) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(salonsProvider.future),
        child: ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: salons.length,
          itemBuilder: (context, index) {
            final salon = salons[index];
            final subEndStr = salon['subscriptionEnd']?.toString() ?? '';
            final parsedDate = DateTime.tryParse(subEndStr);
            final isLifetime = subEndStr.isEmpty || (parsedDate != null && parsedDate.year >= 2099);
            final subEnd = isLifetime
                ? DateTime(2099, 12, 31)
                : (parsedDate ?? DateTime.now().add(const Duration(days: 30)));
            final isSuspended = salon['isSuspended'] == 'true';
            final isExpired = !isLifetime && subEnd.isBefore(DateTime.now());

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 6))],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(LucideIcons.scissors, color: _kPrimary, size: 18),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(salon['name'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: _kDark)),
                                  Text(salon['address'] ?? 'No address', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 11)),
                                ],
                              ),
                            ),
                            _buildStatusBadge(isSuspended, isExpired),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              _buildCredentialRow(icon: LucideIcons.mail, label: 'Owner Email', value: _getOwnerEmail(salon)),
                              const Divider(height: 16, color: Colors.black12),
                              _buildCredentialRow(icon: LucideIcons.key, label: 'Access Code', value: _getOwnerPass(salon)),
                              const Divider(height: 16, color: Colors.black12),
                              _buildCredentialRow(
                                icon: LucideIcons.wallet,
                                label: 'Cash Drawer',
                                value: '${ref.watch(currencyProvider)} ${formatAmount(((double.tryParse(salon['cashBalance']?.toString() ?? '0') ?? 0.0) < 0 ? 0.0 : (double.tryParse(salon['cashBalance']?.toString() ?? '0') ?? 0.0)))}'
                              ),
                              const Divider(height: 16, color: Colors.black12),
                              _buildCredentialRow(
                                icon: LucideIcons.creditCard,
                                label: 'Online Balance',
                                value: '${ref.watch(currencyProvider)} ${formatAmount(((double.tryParse(salon['onlineBalance']?.toString() ?? '0') ?? 0.0) < 0 ? 0.0 : (double.tryParse(salon['onlineBalance']?.toString() ?? '0') ?? 0.0)))}'
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isLifetime
                                  ? 'Valid Until: Lifetime'
                                  : 'Valid Until: ${DateFormat('MMM dd, yyyy').format(subEnd)}',
                              style: GoogleFonts.outfit(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              isLifetime
                                  ? 'Lifetime Subscription'
                                  : (isExpired
                                      ? 'Expired (${DateTime.now().difference(subEnd).inDays}d ago)'
                                      : '${subEnd.difference(DateTime.now()).inDays} days remaining'),
                              style: GoogleFonts.outfit(fontSize: 11, color: isExpired ? Colors.red : _kPrimary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FD),
                      borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _btn(LucideIcons.barChart3, 'Reports', _kPrimary, () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReportsView(
                                  salonId: salon['id'],
                                  salonName: salon['name'],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(width: 8),
                          _btn(LucideIcons.logIn, 'Login', Colors.purple, () async {
                            final email = _getOwnerEmail(salon);
                            final pass = _getOwnerPass(salon);
                            if (email == 'N/A' || pass == '******' || pass == 'N/A') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cannot login: No owner credentials available.')),
                              );
                              return;
                            }
                            
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                            );
                            
                            try {
                              final currentSuperAdminToken = await const FlutterSecureStorage().read(key: 'token');
                              final apiService = ref.read(apiServiceProvider);
                              final response = await apiService.login(email.toLowerCase(), pass);
                              
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                              
                              final user = response['user'];
                              
                              final Map<String, dynamic> freshUserData = Map<String, dynamic>.from(user);
                              final originalSuperAdminData = Map<String, dynamic>.from(ref.read(authProvider)!);
                              originalSuperAdminData['token'] = currentSuperAdminToken;
                              
                              freshUserData['originalSuperAdmin'] = originalSuperAdminData;
                              
                              await ref.read(authProvider.notifier).refreshUser(freshUserData);
                              
                              ref.invalidate(dashboardViewModelProvider);
                              ref.invalidate(posProvider);
                              ref.invalidate(staffProvider);
                              ref.invalidate(servicesProvider);
                              ref.invalidate(expensesProvider);
                              ref.invalidate(attendanceProvider);
                              ref.invalidate(appointmentsProvider);
                              ref.invalidate(salonsProvider);
                              ref.invalidate(inventoryProvider);
                              ref.invalidate(clientsProvider);
                              ref.invalidate(vendorsProvider);
                              ref.invalidate(ledgerProvider);
                              ref.invalidate(reportsProvider);
                              ref.invalidate(logoProvider);
                              ref.invalidate(navigationIndexProvider);
                            } catch (e) {
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Login failed: ${e.toString()}')),
                                );
                              }
                            }
                          }),
                          const SizedBox(width: 8),
                          _btn(LucideIcons.edit, 'Edit', Colors.blue, () => _showEditSalonDialog(context, salon)),
                          const SizedBox(width: 8),
                          _btn(LucideIcons.refreshCw, 'Refill', const Color(0xFF0D9488), () => _showRefillDialog(context, salon)),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: isSuspended ? 'Unfreeze Branch' : 'Freeze Branch',
                            icon: Icon(isSuspended ? LucideIcons.unlock : LucideIcons.lock, color: isSuspended ? Colors.green : Colors.redAccent, size: 18),
                            onPressed: () async {
                              try {
                                await ref.read(apiServiceProvider).toggleSuspension(salon['id']);
                                ref.invalidate(salonsProvider);
                              } catch (e) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Share Credentials',
                            icon: const Icon(LucideIcons.share2, color: _kPrimary, size: 18),
                            onPressed: () => _shareSalonCredentials(salon),
                          ),
                          IconButton(
                            tooltip: 'Message Branch',
                            icon: const Icon(LucideIcons.messageCircle, color: Colors.green, size: 18),
                            onPressed: () => _showMessageSalonDialog(context, salon),
                          ),
                          IconButton(
                            tooltip: 'Delete Branch',
                            icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                            onPressed: () => _confirmDeleteSalon(salon['id'], salon['name']),
                          ),
                          IconButton(
                            tooltip: 'Branch Clients',
                            icon: const Icon(LucideIcons.users, color: Colors.blueAccent, size: 18),
                            onPressed: () => _showSalonClientsDialog(context, salon),
                          ),
                          IconButton(
                            tooltip: 'Reset Password',
                            icon: const Icon(LucideIcons.key, color: Colors.orange, size: 18),
                            onPressed: () => _showPasswordResetDialog(context, salon['id']),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // --- 3. Branch Reports View ---
  Widget _buildReportsView(List<dynamic> salons) {
    if (_selectedBranchIdForReports == null && salons.isNotEmpty) {
      _selectedBranchIdForReports = salons[0]['id'];
      _selectedBranchNameForReports = salons[0]['name'];
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Salon Branch', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBranchIdForReports,
                isExpanded: true,
                items: salons.map((salon) => DropdownMenuItem<String>(
                  value: salon['id'],
                  child: Text(salon['name'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                )).toList(),
                onChanged: (val) {
                  final s = salons.firstWhere((element) => element['id'] == val);
                  setState(() {
                    _selectedBranchIdForReports = val;
                    _selectedBranchNameForReports = s['name'];
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.fileText, size: 64, color: _kPrimary),
                  const SizedBox(height: 16),
                  Text(
                    'Reports for ${_selectedBranchNameForReports ?? "Branch"}',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: _kDark),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Access financial summaries, sales statements, expenses, commissions, and staff attendance reports.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: Colors.black38, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_selectedBranchIdForReports != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReportsView(
                              salonId: _selectedBranchIdForReports,
                              salonName: _selectedBranchNameForReports,
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(LucideIcons.externalLink, size: 16),
                    label: const Text('Open Analytics Dashboard'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 4. Branch Attendance View ---
  Widget _buildAttendanceView(List<dynamic> salons) {
    if (_selectedBranchIdForAttendance == null && salons.isNotEmpty) {
      _selectedBranchIdForAttendance = salons[0]['id'];
      _fetchBranchAttendance(_selectedBranchIdForAttendance!);
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Salon Branch', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBranchIdForAttendance,
                isExpanded: true,
                items: salons.map((salon) => DropdownMenuItem<String>(
                  value: salon['id'],
                  child: Text(salon['name'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                )).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedBranchIdForAttendance = val;
                  });
                  if (val != null) {
                    _fetchBranchAttendance(val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Builder(
              builder: (context) {
                if (_loadingAttendance) {
                  return const Center(child: CircularProgressIndicator(color: _kPrimary));
                }
                if (_branchAttendanceLogs == null || _branchAttendanceLogs!.isEmpty) {
                  return Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.calendarDays, size: 48, color: Colors.black12),
                        const SizedBox(height: 12),
                        Text('No attendance records logged.', style: GoogleFonts.outfit(color: Colors.black38)),
                      ],
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _buildHeaderRow(['Date', 'Staff Name', 'Status', 'Check In', 'Check Out']),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _branchAttendanceLogs!.length,
                          itemBuilder: (context, index) {
                            final log = _branchAttendanceLogs![index];
                            final dateStr = log['date']?.toString() ?? '';
                            final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                            final formattedDate = DateFormat('MMM dd, yyyy').format(date);
                            final staffName = log['staff']?['name'] ?? 'Staff';
                            final status = log['status']?.toString().toUpperCase() ?? 'ABSENT';
                            final checkInVal = log['checkIn']?.toString();
                            final checkOutVal = log['checkOut']?.toString();
                            final hasEarlyExit = log['earlyExit'] == true || log['earlyExit'] == 'true';

                            String formatTime(String? isoStr) {
                              if (isoStr == null || isoStr == 'N/A' || isoStr.isEmpty) return 'N/A';
                              try {
                                final parsed = DateTime.tryParse(isoStr);
                                if (parsed == null) return isoStr;
                                return DateFormat('hh:mm a').format(parsed.toLocal());
                              } catch (_) {
                                return isoStr;
                              }
                            }

                            final checkInText = checkInVal != null ? formatTime(checkInVal) : 'N/A';
                            final checkOutText = checkOutVal != null ? formatTime(checkOutVal) : 'N/A';

                            Color statusColor = Colors.grey;
                            if (status == 'PRESENT') statusColor = Colors.green;
                            if (status == 'ABSENT') statusColor = Colors.red;
                            if (status == 'LATE') statusColor = Colors.orange;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
                              child: Row(
                                children: [
                                  Expanded(child: Text(formattedDate, style: GoogleFonts.outfit(fontSize: 12))),
                                  Expanded(child: Text(staffName, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold))),
                                  Expanded(child: Text(status, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor))),
                                  Expanded(child: Text(checkInText, style: GoogleFonts.outfit(fontSize: 12))),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(checkOutText, style: GoogleFonts.outfit(fontSize: 12)),
                                        if (hasEarlyExit)
                                          Text('(Early Exit)', style: GoogleFonts.outfit(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(List<String> headers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFEEEEEE),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      ),
      child: Row(
        children: headers.map((h) => Expanded(
          child: Text(
            h,
            style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
        )).toList(),
      ),
    );
  }

  // --- 5. Open New Branch ---
  Widget _buildRegisterBranchView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Register New Salon Branch', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
            const SizedBox(height: 6),
            Text('Create a new branch location, allocate subscription periods, and generate credentials.', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black38)),
            const SizedBox(height: 24),
            _formField(_addNameC, 'Salon Name', LucideIcons.home),
            _formField(_addQrC, 'QR Domain (e.g. salonpro.app)', LucideIcons.globe),
            _formField(_addVatC, 'Tax Number (e.g. 3121252266700003)', LucideIcons.fileText),
            _formField(_addAddrC, 'Address', LucideIcons.mapPin),
            _formField(_addEmailC, 'Owner Email Address', LucideIcons.mail),
            _formField(_addPassC, 'Owner Password', LucideIcons.lock, isPass: true),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 20),
              child: Text(
                'Note: Owner Password must contain both numbers and letters, with at least 8 characters.',
                style: GoogleFonts.outfit(fontSize: 10, color: Colors.black26),
              ),
            ),
            Text('Branch Timezone', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(12)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _addTimezone,
                  isExpanded: true,
                  items: _timezones.map((tz) => DropdownMenuItem(value: tz, child: Text(tz, style: GoogleFonts.outfit(fontSize: 14)))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _addTimezone = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (_addNameC.text.trim().isEmpty || _addAddrC.text.trim().isEmpty || _addEmailC.text.trim().isEmpty || _addPassC.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please complete all required fields.'), backgroundColor: Colors.redAccent)
                    );
                    return;
                  }
                  
                  final qrDomainStr = _addQrC.text.trim().isEmpty ? 'salonpro.app' : _addQrC.text.trim();
                  
                  final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegExp.hasMatch(_addEmailC.text.trim())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid email address.'), backgroundColor: Colors.redAccent)
                    );
                    return;
                  }
                  if (_addPassC.text.length < 6) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Owner password must be at least 6 characters long.'), backgroundColor: Colors.redAccent)
                    );
                    return;
                  }
                  try {
                    await ref.read(apiServiceProvider).createSalon({
                      'name': _addNameC.text,
                      'qrDomain': qrDomainStr,
                      'address': _addAddrC.text,
                      'vatNumber': _addVatC.text,
                      'ownerEmail': _addEmailC.text,
                      'ownerPassword': _addPassC.text,
                      'timezone': _addTimezone,
                    });
                    
                    _addNameC.clear();
                      _addQrC.text = 'salonpro.app';
                    _addVatC.clear();
                    _addAddrC.clear();
                    _addEmailC.clear();
                    _addPassC.clear();
                    _addTimezone = 'Asia/Karachi';
                    _addInTime = '09:00';
                    _addLateTime = '09:15';
                    _addOutTime = '18:00';
                    _addEarlyExitTime = '17:45';
                    
                    ref.invalidate(salonsProvider);
                    setState(() {
                      _selectedMenuIndex = 1; // Go back to branches list
                    });
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Branch registered successfully!')));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Register Branch Location', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeSelectField(String label, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final parts = value.split(':');
            final initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
            final picked = await showTimePicker(context: context, initialTime: initialTime);
            if (picked != null) {
              final hour = picked.hour.toString().padLeft(2, '0');
              final minute = picked.minute.toString().padLeft(2, '0');
              onChanged('$hour:$minute');
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(LucideIcons.clock, size: 16, color: _kPrimary),
                const SizedBox(width: 10),
                Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _formField(TextEditingController c, String label, IconData icon, {bool isPass = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            obscureText: isPass,
            style: GoogleFonts.outfit(fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
              filled: true,
              fillColor: _kBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  // --- Branch UI Helper Components ---
  Widget _btn(IconData icon, String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05), 
            borderRadius: BorderRadius.circular(12), 
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.outfit(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isSuspended, bool isExpired) {
    final String text = isSuspended ? 'LOCKED' : (isExpired ? 'EXPIRED' : 'ACTIVE');
    final Color color = isSuspended || isExpired ? Colors.redAccent : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: GoogleFonts.outfit(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  void _showExtendDialog(BuildContext context, String salonId) {
    // Convenience backward compatibility wrapper
    final salonsAsync = ref.read(salonsProvider);
    final salonList = salonsAsync.value ?? [];
    final salon = salonList.firstWhere(
      (s) => s['id']?.toString() == salonId,
      orElse: () => {'id': salonId, 'name': 'Branch'},
    );
    _showRefillDialog(context, salon);
  }

  void _showRefillDialog(BuildContext context, dynamic salon) {
    final salonId = salon['id']?.toString() ?? '';
    final salonName = salon['name']?.toString() ?? 'Branch';
    final subEndStr = salon['subscriptionEnd']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(subEndStr);
    final isCurrentLifetime = subEndStr.isEmpty || (parsedDate != null && parsedDate.year >= 2099);
    final currentSubEnd = isCurrentLifetime
        ? DateTime(2099, 12, 31)
        : (parsedDate ?? DateTime.now());
    final isCurrentlyExpired = !isCurrentLifetime && currentSubEnd.isBefore(DateTime.now());

    int selectedDays = 30; // default 1 month
    String refillMode = 'preset'; // 'preset', 'custom', 'date', 'lifetime'
    DateTime? pickedDate;
    final customDaysController = TextEditingController(text: '30');
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          DateTime calculatePreviewDate() {
            if (refillMode == 'lifetime') {
              return DateTime(2099, 12, 31);
            }
            if (refillMode == 'date' && pickedDate != null) {
              return pickedDate!;
            }
            int days = selectedDays;
            if (refillMode == 'custom') {
              days = int.tryParse(customDaysController.text.trim()) ?? 30;
            }
            final base = (!isCurrentLifetime && currentSubEnd.isAfter(DateTime.now()))
                ? currentSubEnd
                : DateTime.now();
            return base.add(Duration(days: days));
          }

          final previewDate = calculatePreviewDate();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.refreshCw, color: Color(0xFF0D9488), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Refill Branch Expiry',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: _kDark),
                      ),
                      Text(
                        salonName,
                        style: GoogleFonts.outfit(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current Status Box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isCurrentlyExpired
                            ? Colors.red.withValues(alpha: 0.08)
                            : (isCurrentLifetime ? Colors.purple.withValues(alpha: 0.08) : Colors.green.withValues(alpha: 0.08)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCurrentlyExpired
                              ? Colors.red.withValues(alpha: 0.25)
                              : (isCurrentLifetime ? Colors.purple.withValues(alpha: 0.25) : Colors.green.withValues(alpha: 0.25)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isCurrentlyExpired
                                ? LucideIcons.alertCircle
                                : (isCurrentLifetime ? LucideIcons.infinity : LucideIcons.checkCircle),
                            color: isCurrentlyExpired
                                ? Colors.red
                                : (isCurrentLifetime ? Colors.purple : Colors.green),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isCurrentLifetime
                                      ? 'Active: Lifetime Access'
                                      : (isCurrentlyExpired
                                          ? 'Status: Subscription Expired'
                                          : 'Status: Active Subscription'),
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isCurrentlyExpired
                                        ? Colors.red
                                        : (isCurrentLifetime ? Colors.purple : Colors.green),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isCurrentLifetime
                                      ? 'No expiration date configured.'
                                      : (isCurrentlyExpired
                                          ? 'Expired on ${DateFormat('MMM dd, yyyy').format(currentSubEnd)} (${DateTime.now().difference(currentSubEnd).inDays} days ago)'
                                          : 'Valid until ${DateFormat('MMM dd, yyyy').format(currentSubEnd)} (${currentSubEnd.difference(DateTime.now()).inDays} days left)'),
                                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    Text(
                      'Choose Refill Duration',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark),
                    ),
                    const SizedBox(height: 10),

                    // Preset options
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildRefillChip(
                          label: '1 Month (30d)',
                          selected: refillMode == 'preset' && selectedDays == 30,
                          onTap: () => setDialogState(() {
                            refillMode = 'preset';
                            selectedDays = 30;
                          }),
                        ),
                        _buildRefillChip(
                          label: '3 Months (90d)',
                          selected: refillMode == 'preset' && selectedDays == 90,
                          onTap: () => setDialogState(() {
                            refillMode = 'preset';
                            selectedDays = 90;
                          }),
                        ),
                        _buildRefillChip(
                          label: '6 Months (180d)',
                          selected: refillMode == 'preset' && selectedDays == 180,
                          onTap: () => setDialogState(() {
                            refillMode = 'preset';
                            selectedDays = 180;
                          }),
                        ),
                        _buildRefillChip(
                          label: '1 Year (365d)',
                          selected: refillMode == 'preset' && selectedDays == 365,
                          onTap: () => setDialogState(() {
                            refillMode = 'preset';
                            selectedDays = 365;
                          }),
                        ),
                        _buildRefillChip(
                          label: 'Custom Days',
                          icon: LucideIcons.calendarPlus,
                          selected: refillMode == 'custom',
                          onTap: () => setDialogState(() {
                            refillMode = 'custom';
                          }),
                        ),
                        _buildRefillChip(
                          label: 'Pick Date',
                          icon: LucideIcons.calendar,
                          selected: refillMode == 'date',
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: previewDate.isAfter(DateTime.now()) ? previewDate : DateTime.now().add(const Duration(days: 30)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                refillMode = 'date';
                                pickedDate = picked;
                              });
                            }
                          },
                        ),
                        _buildRefillChip(
                          label: 'Lifetime',
                          icon: LucideIcons.infinity,
                          selected: refillMode == 'lifetime',
                          onTap: () => setDialogState(() {
                            refillMode = 'lifetime';
                          }),
                        ),
                      ],
                    ),

                    if (refillMode == 'custom') ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: customDaysController,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.outfit(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Number of Days to Add',
                          hintText: 'e.g. 15, 45, 60',
                          prefixIcon: const Icon(LucideIcons.calendarPlus, size: 18, color: Color(0xFF0D9488)),
                          filled: true,
                          fillColor: _kBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Preview Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.calendarCheck, color: Color(0xFF16A34A), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'New Expiration Preview',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: const Color(0xFF15803D)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  refillMode == 'lifetime'
                                      ? 'Lifetime (Never Expires)'
                                      : '${DateFormat('EEEE, MMMM dd, yyyy').format(previewDate)} (${previewDate.difference(DateTime.now()).inDays} days from now)',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: const Color(0xFF14532D),
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
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black54, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.checkCircle2, size: 16),
                label: Text(
                  isSubmitting ? 'Refilling...' : 'Confirm Refill',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        try {
                          final api = ref.read(apiServiceProvider);
                          if (refillMode == 'lifetime') {
                            await api.extendSubscription(salonId, isLifetime: true);
                          } else if (refillMode == 'date' && pickedDate != null) {
                            await api.extendSubscription(salonId, newDate: pickedDate!.toIso8601String());
                          } else {
                            int days = selectedDays;
                            if (refillMode == 'custom') {
                              days = int.tryParse(customDaysController.text.trim()) ?? 0;
                              if (days <= 0) {
                                throw Exception('Please enter a valid number of days');
                              }
                            }
                            await api.extendSubscription(salonId, days: days);
                          }

                          ref.invalidate(salonsProvider);

                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF0D9488),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                content: Row(
                                  children: [
                                    const Icon(LucideIcons.checkCircle2, color: Colors.white, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Subscription for "$salonName" refilled successfully!',
                                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRefillChip({
    required String label,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0D9488) : _kBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF0D9488) : Colors.black12,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : Colors.black87),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {bool isPass = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: isPass,
        style: GoogleFonts.outfit(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
          filled: true,
          fillColor: _kBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  void _showEditSalonDialog(BuildContext context, dynamic salon) {
    final name = TextEditingController(text: salon['name']);
    final addr = TextEditingController(text: salon['address']);
    final vat = TextEditingController(text: salon['vatNumber']);
      final qrDomain = TextEditingController(text: salon['qrDomain'] ?? 'salonpro.app');
    String tz = salon['timezone'] ?? 'Asia/Karachi';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Edit Salon Settings', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(name, 'Salon Name', LucideIcons.home),
                    _field(vat, 'Tax Number (e.g. 3121252266700003)', LucideIcons.fileText),
                      _field(qrDomain, 'QR Code Domain (e.g. salonpro.app)', LucideIcons.link),
                    _field(addr, 'Address', LucideIcons.mapPin),
                    const SizedBox(height: 8),
                    Text('Timezone', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(10)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tz,
                          isExpanded: true,
                          items: _timezones.map((item) => DropdownMenuItem(value: item, child: Text(item, style: GoogleFonts.outfit(fontSize: 13)))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => tz = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit())),
              ElevatedButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty || addr.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Salon name and address are required.'), backgroundColor: Colors.redAccent)
                    );
                    return;
                  }
                  try {
                    await ref.read(apiServiceProvider).updateSalon(salon['id'], {
                      'name': name.text,
                      'address': addr.text,
                      'vatNumber': vat.text,
                        'qrDomain': qrDomain.text,
                      'timezone': tz,
                    });
                    ref.invalidate(salonsProvider);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('Save Changes', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  String _getOwnerEmail(dynamic salon) {
    try {
      final owner = (salon['users'] as List).firstWhere((u) => u['role'] == 'OWNER');
      return owner['email'] ?? 'N/A';
    } catch (_) { return 'No owner'; }
  }

  String _getOwnerPass(dynamic salon) {
    try {
      final owner = (salon['users'] as List).firstWhere((u) => u['role'] == 'OWNER');
      return owner['plainPassword'] ?? '******';
    } catch (_) { return 'N/A'; }
  }

  Widget _buildCredentialRow({required IconData icon, required String label, required String value}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.black26),
        const SizedBox(width: 10),
        Text('$label:', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black38)),
        const SizedBox(width: 6),
        Expanded(child: Text(value, style: GoogleFonts.outfit(fontSize: 12, color: _kDark, fontWeight: FontWeight.w600))),
      ],
    );
  }

  void _confirmDeleteSalon(String id, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete Salon?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: Text('This will delete all data related to $name. This action cannot be undone.', style: GoogleFonts.outfit(color: Colors.white70)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Back', style: GoogleFonts.outfit(color: Colors.white54))),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(apiServiceProvider).deleteSalon(id);
                if (context.mounted) { Navigator.pop(context); ref.invalidate(salonsProvider); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salon deleted'))); }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _shareSalonCredentials(dynamic salon) async {
    final salonName = salon['name'];
    final ownerEmail = _getOwnerEmail(salon);
    final ownerPass = _getOwnerPass(salon);
    final serverUrl = kIsWeb ? Uri.base.origin : ApiConfig.baseUrl;

    String message = "*Salon Access Credentials*\n\n";
    message += "Salon: $salonName\n";
    message += "Email: $ownerEmail\n";
    message += "Password: $ownerPass\n\n";
    message += "Portal: $serverUrl\n\n";
    message += "Please login and change your password immediately. ✨";

    await Share.share(message, subject: 'Credentials: $salonName');
  }

  void _showSalonClientsDialog(BuildContext context, dynamic salon) {
    final salonId = salon['id'];
    final salonName = salon['name'];
    final nameC = TextEditingController();
    final phoneC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Manage Clients - $salonName', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Quick add client for this salon:', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45)),
            const SizedBox(height: 12),
            _field(nameC, 'Client Name', LucideIcons.user),
            _field(phoneC, 'Phone Number', LucideIcons.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: GoogleFonts.outfit())),
          ElevatedButton(
            onPressed: () async {
              if (nameC.text.isEmpty) return;
              try {
                await ref.read(apiServiceProvider).createClient({
                  'name': nameC.text,
                  'phone': phoneC.text,
                  'salonId': salonId,
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client added successfully')));
                }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Add Client', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMessageSalonDialog(BuildContext context, dynamic salon) {
    final messageController = TextEditingController();
    final headerController = TextEditingController(text: 'Salon Pro Support');
    final footerController = TextEditingController(text: 'Best regards, Super Admin');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Message ${salon['name']}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMessageField('Header', headerController, 1),
                const SizedBox(height: 12),
                _buildMessageField('Message to Salon Owner', messageController, 4, hint: 'Enter your message...'),
                const SizedBox(height: 12),
                _buildMessageField('Footer', footerController, 1),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final phone = salon['phone']?.toString();
              if (phone == null || phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number found for this salon.')));
                return;
              }
              final fullMessage = "*${headerController.text}*\n\n${messageController.text}\n\n${footerController.text}";
              final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
              final whatsappUrl = Uri.parse("whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(fullMessage)}");
              
              Navigator.pop(context);
              if (await canLaunchUrl(whatsappUrl)) {
                await launchUrl(whatsappUrl);
              } else {
                final webUrl = Uri.parse("https://wa.me/$cleanPhone?text=${Uri.encodeComponent(fullMessage)}");
                await launchUrl(webUrl, mode: LaunchMode.externalApplication);
              }
            },
            child: Text('Send WhatsApp', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageField(String label, TextEditingController controller, int lines, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: lines,
          style: GoogleFonts.outfit(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  void _showPasswordResetDialog(BuildContext context, String salonId) {
    final pass = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Reset Owner Password', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter a new password for this salon owner.', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45)),
            const SizedBox(height: 16),
            _field(pass, 'New Password', LucideIcons.lock, isPass: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit())),
          ElevatedButton(
            onPressed: () async {
              try {
                if (pass.text.isEmpty) return;
                await ref.read(apiServiceProvider).resetSalonOwnerPassword(salonId, pass.text);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated successfully')));
                }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Reset', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

