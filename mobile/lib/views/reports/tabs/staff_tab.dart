import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:salon_management_system/providers/reports_provider.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/staff_provider.dart';
import '../../../providers/attendance_provider.dart';
import '../../../providers/ledger_provider.dart';
import '../../../utils/format_helper.dart';

const _kDark = Color(0xFF1E293B);
const _kPrimary = Color(0xFF6366F1);

class StaffTabWidget extends ConsumerWidget {
  final String? salonId;
  final List<dynamic> sales;
  final Map<String, dynamic> data;
  final String? selectedStaffId;
  final ValueChanged<String?> onStaffSelected;
  final DateTime startDate;
  final DateTime endDate;

  const StaffTabWidget({
    super.key,
    required this.salonId,
    required this.sales,
    required this.data,
    required this.selectedStaffId,
    required this.onStaffSelected,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = salonId != null
        ? ref.watch(staffForSalonProvider(salonId!))
        : ref.watch(staffProvider);
    final ledgerAsync = ref.watch(ledgerProvider(LedgerParams(salonId: salonId, limit: 1000, includeOnline: true)));

    if (staffAsync.isLoading || ledgerAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    final rawStaffList = staffAsync.value ?? [];
    final staffList = selectedStaffId != null
        ? rawStaffList.where((s) => s['id']?.toString() == selectedStaffId).toList()
        : rawStaffList;
    final ledgerEntries = ledgerAsync.value?['entries'] ?? [];
    final currency = ref.watch(currencyProvider);

    if (staffList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.folderOpen, size: 40, color: Colors.black12),
            const SizedBox(height: 12),
            Text('No staff profiles found', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 13)),
          ],
        ),
      );
    }

    final List<Map<String, dynamic>> staffRows = [];
    int totalServices = 0;
    double totalServiceSales = 0;
    double totalProductSales = 0;
    double totalCommission = 0;
    double totalSalaryPaid = 0;

    for (var s in staffList) {
      final staffId = s['id'];
      final staffName = s['name'] ?? 'Staff Member';
      final commissionRate = double.tryParse(s['commissionPercentage']?.toString() ?? s['commissionRate']?.toString() ?? '10') ?? 10.0;

      final staffSales = sales.where((sale) {
        if (sale['status'] != 'ACTIVE') return false;
        final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
        return items.any((item) {
          final itemStaffId = item['staffId'] ?? sale['staffId'];
          return itemStaffId == staffId;
        });
      }).toList();

      int servicesDone = 0;
      double serviceSales = 0;
      double productSales = 0;
      double expectedComm = 0;

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
          if (itemStaffId != staffId) continue;

          final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
          final discountAmt = double.tryParse(item['discountAmount']?.toString() ?? '0') ?? 0.0;
          final commAmt = double.tryParse(item['commissionAmount']?.toString() ?? '0') ?? 0.0;
          
          final netRevenue = ((price * qty) - discountAmt) * ratio;
          if (commAmt > 0) {
            expectedComm += commAmt * ratio;
          } else {
            expectedComm += netRevenue * (commissionRate / 100);
          }

          final isProduct = item['productId'] != null || (item['serviceId']?.toString() ?? '').startsWith('inv_');
          if (isProduct) {
            productSales += netRevenue;
          } else {
            servicesDone += qty;
            serviceSales += netRevenue;
          }
        }
      }

      double salaryPaid = 0;
      for (var entry in ledgerEntries) {
        if (entry['staffId'] == staffId) {
          final dateStr = entry['date']?.toString() ?? '';
          final date = DateTime.tryParse(dateStr);
          if (date != null) {
            final localDate = date.toLocal();
            final dateMidnight = DateTime(localDate.year, localDate.month, localDate.day);
            final startMidnight = DateTime(startDate.year, startDate.month, startDate.day);
            final endMidnight = DateTime(endDate.year, endDate.month, endDate.day);
            if (dateMidnight.isBefore(startMidnight) || dateMidnight.isAfter(endMidnight)) {
              continue;
            }
          }
          final notes = entry['notes']?.toString() ?? '';
          final name = entry['name']?.toString() ?? '';
          final isSalary = entry['category'] == 'Salaries' || 
                           name.toLowerCase().contains('salary') || 
                           notes.toLowerCase().contains('salary') ||
                           (entry['type'] == 'DEBIT' && entry['category'] == 'EXPENSE');
          if (isSalary) {
            salaryPaid += double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
          }
        }
      }

      final baseSal = double.tryParse(s['salaryValue']?.toString() ?? '0') ?? 0.0;
      final salaryType = s['salaryType']?.toString() ?? 'COMMISSION';
      final includesBase = salaryType != 'COMMISSION';
      final expectedEarning = (includesBase ? baseSal : 0.0) + expectedComm - salaryPaid;
      final balPayable = expectedEarning < 0 ? 0.0 : expectedEarning;

      staffRows.add({
        'name': staffName,
        'servicesDone': servicesDone,
        'serviceSales': serviceSales,
        'productSales': productSales,
        'commissionRate': commissionRate,
        'expectedCommission': expectedComm,
        'baseSalary': includesBase ? baseSal : 0.0,
        'salaryType': salaryType,
        'salaryPaid': salaryPaid,
        'balancePayable': balPayable,
      });

      totalServices += servicesDone;
      totalServiceSales += serviceSales;
      totalProductSales += productSales;
      totalCommission += expectedComm;
      totalSalaryPaid += salaryPaid;
    }

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
              Text(selectedStaffId != null ? 'My Salary & Commission' : 'Staff Performance and Expected Payroll', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
              Text('Expected payroll is only for checking. It is not deducted until salary is paid as expense.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
              const SizedBox(height: 20),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.grey.shade100),
                  child: DataTable(
                    columnSpacing: 24,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    headingRowHeight: 40,
                    dataRowMinHeight: 44,
                    dataRowMaxHeight: 52,
                    columns: [
                      DataColumn(label: Text('STAFF', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                      DataColumn(label: Text('SERVICES', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                      DataColumn(label: Text('SERVICE SALES', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                      DataColumn(label: Text('PRODUCT SALES', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                      DataColumn(label: Text('COMM %', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                      DataColumn(label: Text('COMMISSION EARNED', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                      DataColumn(label: Text('SALARY PAID', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    ],
                    rows: [
                      ...List.generate(staffRows.length, (idx) {
                        final row = staffRows[idx];
                        final cellStyle = GoogleFonts.outfit(fontSize: 13, color: _kDark);

                        return DataRow(
                          cells: [
                            DataCell(Text(row['name'], style: cellStyle.copyWith(fontWeight: FontWeight.bold))),
                            DataCell(Text('${row['servicesDone']}', style: cellStyle)),
                            DataCell(Text('$currency ${formatAmount(row['serviceSales'])}', style: cellStyle.copyWith(fontWeight: FontWeight.bold))),
                            DataCell(Text('$currency ${formatAmount(row['productSales'])}', style: cellStyle)),
                            DataCell(Text('${row['commissionRate'].toStringAsFixed(0)}%', style: cellStyle)),
                            DataCell(Text('$currency ${formatAmount(row['expectedCommission'])}', style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
                            DataCell(Text('$currency ${formatAmount(row['salaryPaid'])}', style: cellStyle)),
                          ],
                        );
                      }),
                      DataRow(
                        cells: [
                          DataCell(Text('Total', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kDark))),
                          DataCell(Text('$totalServices', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold))),
                          DataCell(Text('$currency ${formatAmount(totalServiceSales)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold))),
                          DataCell(Text('$currency ${formatAmount(totalProductSales)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold))),
                          const DataCell(SizedBox()),
                          DataCell(Text('$currency ${formatAmount(totalCommission)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
                          DataCell(Text('$currency ${formatAmount(totalSalaryPaid)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AttendanceTabWidget extends ConsumerWidget {
  final String? salonId;
  final DateTime startDate;
  final DateTime endDate;
  final bool isStaff;
  final String? myStaffId;
  final String? selectedStaffId;
  final Map<String, dynamic> data;

  const AttendanceTabWidget({
    super.key,
    required this.salonId,
    required this.startDate,
    required this.endDate,
    required this.isStaff,
    required this.myStaffId,
    required this.selectedStaffId,
    required this.data,
  });

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          '$value',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attAsync = salonId != null
        ? ref.watch(attendanceForSalonProvider(salonId))
        : ref.watch(attendanceProvider);
    final staffAsync = salonId != null
        ? ref.watch(staffForSalonProvider(salonId!))
        : ref.watch(staffProvider);

    if (attAsync.isLoading || staffAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    final attendanceList = attAsync.value ?? [];
    final staffList = staffAsync.value ?? [];
    final staffMap = {for (var s in staffList) s['id']?.toString(): s['name']?.toString() ?? 'Staff'};
    
    final filteredAtt = attendanceList.where((att) {
      final dateStr = att['date']?.toString() ?? '';
      final parsed = DateTime.tryParse(dateStr);
      if (parsed == null) return false;
      
      final attDate = DateTime(parsed.year, parsed.month, parsed.day);
      final rangeStart = DateTime(startDate.year, startDate.month, startDate.day);
      final rangeEnd = DateTime(endDate.year, endDate.month, endDate.day);
      
      final isWithinDates = (attDate.isAfter(rangeStart) || attDate.isAtSameMomentAs(rangeStart)) &&
                            (attDate.isBefore(rangeEnd) || attDate.isAtSameMomentAs(rangeEnd));
      if (!isWithinDates) return false;

      if (isStaff && myStaffId != null) {
        if (att['staffId'] != myStaffId) return false;
      } else {
        if (selectedStaffId != null && att['staffId'] != selectedStaffId) return false;
      }

      return true;
    }).toList();

    final summaryList = data['staffAttendanceSummary'] as List<dynamic>? ?? [];
    final String? staffFilterId = isStaff ? myStaffId : selectedStaffId;
    Widget? summaryHeader;

    if (staffFilterId != null) {
      final staffSummary = summaryList.firstWhere(
        (s) => s['staffId']?.toString() == staffFilterId,
        orElse: () => null,
      );
      if (staffSummary != null) {
        final present = int.tryParse(staffSummary['presentDays']?.toString() ?? '0') ?? 0;
        final absent = int.tryParse(staffSummary['absentDays']?.toString() ?? '0') ?? 0;
        final leaves = int.tryParse(staffSummary['leaveDays']?.toString() ?? '0') ?? 0;
        final lates = int.tryParse(staffSummary['lateDays']?.toString() ?? '0') ?? 0;
        final earlyExits = int.tryParse(staffSummary['earlyExits']?.toString() ?? '0') ?? 0;
        
        summaryHeader = Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Attendance Stats Summary', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(child: _buildStatItem('Present', present, Colors.green)),
                  Expanded(child: _buildStatItem('Absent', absent, Colors.red)),
                  Expanded(child: _buildStatItem('Leaves', leaves, Colors.blue)),
                  Expanded(child: _buildStatItem('Late', lates, Colors.orange)),
                  Expanded(child: _buildStatItem('Early Exit', earlyExits, Colors.redAccent)),
                ],
              ),
            ],
          ),
        );
      }
    } else {
      final dailyList = summaryList.where((s) => s['salaryType']?.toString().toUpperCase().contains('DAILY') ?? false).toList();
      final monthlyList = summaryList.where((s) => !dailyList.contains(s)).toList();

      if (summaryList.isNotEmpty) {
        summaryHeader = Column(
          children: [
            if (monthlyList.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monthly & Commission Staff Attendance Summary', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 16,
                        headingRowHeight: 36,
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 44,
                        columns: [
                          DataColumn(label: Text('Staff', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11))),
                          DataColumn(label: Text('Present', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Absent', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Leaves', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Sunday', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Holiday', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Late', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Early Exit', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                        ],
                        rows: monthlyList.map((s) {
                          return DataRow(
                            cells: [
                              DataCell(Text(s['name']?.toString() ?? 'Staff', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataCell(Text('${s['presentDays']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.green))),
                              DataCell(Text('${s['absentDays']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.red))),
                              DataCell(Text('${s['leaveDays']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.blue))),
                              DataCell(Text('${s['sundayDays'] ?? 0}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.teal))),
                              DataCell(Text('${s['holidayDays'] ?? 0}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.amber))),
                              DataCell(Text('${s['lateDays']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.orange))),
                              DataCell(Text('${s['earlyExits']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.redAccent))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (dailyList.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily/Wage Staff Attendance Summary', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 16,
                        headingRowHeight: 36,
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 44,
                        columns: [
                          DataColumn(label: Text('Staff', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11))),
                          DataColumn(label: Text('Present', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Absent', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Leaves', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Sunday', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Holiday', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Late', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                          DataColumn(label: Text('Early Exit', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                        ],
                        rows: dailyList.map((s) {
                          return DataRow(
                            cells: [
                              DataCell(Text(s['name']?.toString() ?? 'Staff', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataCell(Text('${s['presentDays']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.green))),
                              DataCell(Text('${s['absentDays']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.red))),
                              DataCell(Text('${s['leaveDays']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.blue))),
                              DataCell(Text('${s['sundayDays'] ?? 0}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.teal))),
                              DataCell(Text('${s['holidayDays'] ?? 0}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.amber))),
                              DataCell(Text('${s['lateDays']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.orange))),
                              DataCell(Text('${s['earlyExits']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.redAccent))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      }
    }

    if (filteredAtt.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          if (summaryHeader != null) summaryHeader,
          Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.folderOpen, size: 40, color: Colors.black12),
                const SizedBox(height: 12),
                Text('No detailed attendance records found', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 13)),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        if (summaryHeader != null) summaryHeader,
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: DataTable(
            columns: [
              DataColumn(label: Text('Date', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Staff Member', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Status', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Check In', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Check Out', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Early Exit', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold))),
            ],
            rows: filteredAtt.map((att) {
              final dateStr = att['date']?.toString() ?? '';
              final date = DateTime.tryParse(dateStr) ?? DateTime.now();
              final formattedDate = DateFormat('MMM dd, yyyy').format(date);
              
              final staffName = staffMap[att['staffId']?.toString()] ?? 'Staff';
              final status = att['status']?.toString().toUpperCase() ?? 'UNKNOWN';
              final checkInRaw = att['checkIn']?.toString();
              final checkOutRaw = att['checkOut']?.toString();
              final parsedCheckIn = checkInRaw != null ? DateTime.tryParse(checkInRaw) : null;
              final parsedCheckOut = checkOutRaw != null ? DateTime.tryParse(checkOutRaw) : null;
              final checkIn = parsedCheckIn != null ? DateFormat('hh:mm a').format(parsedCheckIn.toLocal()) : 'N/A';
              final checkOutTime = parsedCheckOut != null ? DateFormat('hh:mm a').format(parsedCheckOut.toLocal()) : 'N/A';
              final earlyExit = att['earlyExit'] == true || att['earlyExit'] == 'true';
              final earlyExitStr = earlyExit ? 'Yes' : 'No';
              final earlyExitColor = earlyExit ? Colors.redAccent : Colors.black54;

              Color statusColor = Colors.grey;
              if (status == 'PRESENT') statusColor = Colors.green;
              if (status == 'ABSENT') statusColor = Colors.red;
              if (status == 'LEAVE') statusColor = Colors.blue;
              if (status == 'LATE') statusColor = Colors.orange;

              return DataRow(
                cells: [
                  DataCell(Text(formattedDate, style: GoogleFonts.outfit(fontSize: 10))),
                  DataCell(Text(staffName, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataCell(Text(status, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor))),
                  DataCell(Text(checkIn, style: GoogleFonts.outfit(fontSize: 10))),
                  DataCell(Text(checkOutTime, style: GoogleFonts.outfit(fontSize: 10))),
                  DataCell(Text(earlyExitStr, style: GoogleFonts.outfit(fontSize: 10, fontWeight: earlyExit ? FontWeight.bold : FontWeight.normal, color: earlyExitColor))),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
