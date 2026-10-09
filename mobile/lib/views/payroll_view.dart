import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../providers/staff_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/salons_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/reports_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/expenses_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/payment_accounts_provider.dart';
import '../models/payment_account.dart';
import '../view_models/dashboard_view_model.dart';
import '../providers/dashboard_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

const _kPrimary = Color(0xFF0F4C81); // Navy
const _kDark = Color(0xFF1B1B3A); // Deep Slate
const _kBg = Color(0xFFF4F6FB); // Soft Blue-Grey
const _kGreen = Color(0xFF2ECD71);
const _kRed = Color(0xFFE74C3C);
const _kOrange = Color(0xFFF39C12);
const _kBlue = Color(0xFF3498DB);

class GeneratedSalaryRecord {
  final String id;
  final String staffId;
  final String name;
  final String role;
  final String salaryType;
  final double basicSalary;
  final String month;
  final int year;
  final int present;
  final int absent;
  final int leaves;
  final int lateDays;
  final int earlyExit;
  final double salaryGenerated;
  final double commission;
  double amountPaid;
  double loanRepayment;
  double bonus;
  double deductions;
  String status; // 'Paid' or 'Pending'
  String? expenseId;
  String? deductionId;
  String? paymentMethod;
  String? paymentAccountId;

  GeneratedSalaryRecord({
    required this.id,
    required this.staffId,
    required this.name,
    required this.role,
    required this.salaryType,
    required this.basicSalary,
    required this.month,
    required this.year,
    required this.present,
    required this.absent,
    this.leaves = 0,
    required this.lateDays,
    required this.earlyExit,
    required this.salaryGenerated,
    this.commission = 0.0,
    required this.amountPaid,
    required this.loanRepayment,
    this.bonus = 0.0,
    this.deductions = 0.0,
    required this.status,
    this.expenseId,
    this.deductionId,
    this.paymentMethod,
    this.paymentAccountId,
  });

  factory GeneratedSalaryRecord.fromJson(Map<String, dynamic> json) {
    return GeneratedSalaryRecord(
      id: json['id']?.toString() ?? '',
      staffId: json['staffId']?.toString() ?? '',
      name: json['name'] ?? 'Staff',
      role: json['role'] ?? 'Staff',
      salaryType: json['salaryType'] ?? 'MONTHLY',
      basicSalary:
          double.tryParse(json['basicSalary']?.toString() ?? '0') ?? 0.0,
      month: json['month'] ?? 'July',
      year: int.tryParse(json['year']?.toString() ?? '2026') ?? 2026,
      present: int.tryParse(json['present']?.toString() ?? '0') ?? 0,
      absent: int.tryParse(json['absent']?.toString() ?? '0') ?? 0,
      leaves: int.tryParse(json['leaves']?.toString() ?? '0') ?? 0,
      lateDays: int.tryParse(json['lateDays']?.toString() ?? '0') ?? 0,
      earlyExit: int.tryParse(json['earlyExit']?.toString() ?? '0') ?? 0,
      salaryGenerated:
          double.tryParse(json['salaryGenerated']?.toString() ?? '0') ?? 0.0,
      commission: double.tryParse(json['commission']?.toString() ?? '0') ?? 0.0,
      amountPaid: double.tryParse(json['amountPaid']?.toString() ?? '0') ?? 0.0,
      loanRepayment:
          double.tryParse(json['loanRepayment']?.toString() ?? '0') ?? 0.0,
      bonus: double.tryParse(json['bonus']?.toString() ?? '0') ?? 0.0,
      deductions: double.tryParse(json['deductions']?.toString() ?? '0') ?? 0.0,
      status: json['status'] ?? 'Pending',
      expenseId: json['expenseId']?.toString(),
      deductionId: json['deductionId']?.toString(),
      paymentMethod: json['paymentMethod']?.toString(),
      paymentAccountId: json['paymentAccountId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'staffId': staffId,
        'name': name,
        'role': role,
        'salaryType': salaryType,
        'basicSalary': basicSalary,
        'month': month,
        'year': year,
        'present': present,
        'absent': absent,
        'leaves': leaves,
        'lateDays': lateDays,
        'earlyExit': earlyExit,
        'salaryGenerated': salaryGenerated,
        'commission': commission,
        'amountPaid': amountPaid,
        'loanRepayment': loanRepayment,
        'bonus': bonus,
        'deductions': deductions,
        'status': status,
        'expenseId': expenseId,
        'deductionId': deductionId,
        'paymentMethod': paymentMethod,
        'paymentAccountId': paymentAccountId,
      };
}

class PayrollView extends ConsumerStatefulWidget {
  const PayrollView({super.key});

  @override
  ConsumerState<PayrollView> createState() => _PayrollViewState();
}

class _PayrollViewState extends ConsumerState<PayrollView> {
  String? _selectedSalonId;
  String _selectedMonth = 'July';
  int _selectedYear = 2026;
  String _filterSalaryType = 'ALL';
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59, 999);
  String _selectedDateMode = 'THIS_MONTH';

  final List<String> _monthsList = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  final List<int> _yearsList = [2024, 2025, 2026, 2027, 2028];

  final Set<String> _selectedStaffIds = {};
  List<GeneratedSalaryRecord> _generatedSalaries = [];

  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadGeneratedSalaries();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGeneratedSalaries() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('generated_salaries');
    if (jsonStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final loaded = <GeneratedSalaryRecord>[];
        for (final item in decoded) {
          try {
            loaded.add(
                GeneratedSalaryRecord.fromJson(item as Map<String, dynamic>));
          } catch (_) {
            // Skip corrupted individual records, don't wipe everything
          }
        }
        if (mounted) setState(() => _generatedSalaries = loaded);
      } catch (_) {
        // JSON completely malformed — leave _generatedSalaries as empty
      }
    }
  }

  Future<void> _saveGeneratedSalaries() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        jsonEncode(_generatedSalaries.map((r) => r.toJson()).toList());
    await prefs.setString('generated_salaries', jsonStr);
  }

  DateTime? _getLastPaidDate(String staffId) {
    DateTime? maxPaidDate;
    for (final r in _generatedSalaries) {
      if (r.staffId == staffId && r.status == 'Paid') {
        final parts = r.id.split('_');
        if (parts.length >= 3) {
          final endDateStr = parts.last; // yyyyMMdd
          try {
            final year = int.parse(endDateStr.substring(0, 4));
            final month = int.parse(endDateStr.substring(4, 6));
            final day = int.parse(endDateStr.substring(6, 8));
            final paidDate = DateTime(year, month, day);
            if (maxPaidDate == null || paidDate.isAfter(maxPaidDate)) {
              maxPaidDate = paidDate;
            }
          } catch (_) {}
        }
      }
    }
    return maxPaidDate;
  }

  void _generateSalaryForSelected(List<dynamic> staffList,
      List<dynamic> attendanceList, List<dynamic> salesList) {
    if (_selectedStaffIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Please select at least one staff member to generate salary.')));
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_startDate.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('Cannot generate salary for future dates.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    int generatedCount = 0;
    int alreadyPaidCount = 0;

    setState(() {
      for (var staffId in _selectedStaffIds) {
        final staff = staffList.cast<dynamic>().firstWhere(
            (s) => s['id']?.toString() == staffId,
            orElse: () => null);
        if (staff == null) continue;

        final salaryType = staff['salaryType']?.toString() ?? 'MONTHLY';

        // Determine last paid date
        final lastPaid = _getLastPaidDate(staffId);
        DateTime effectiveStartDate =
            (lastPaid != null && lastPaid.isAfter(_startDate))
                ? lastPaid.add(const Duration(days: 1))
                : _startDate;

        // Cap start date at joining date
        final String? joiningDateStr = staff['joiningDate']?.toString() ??
            staff['joining_date']?.toString();
        if (joiningDateStr != null && joiningDateStr.isNotEmpty) {
          final joiningDate = DateTime.tryParse(joiningDateStr);
          if (joiningDate != null && joiningDate.isAfter(effectiveStartDate)) {
            effectiveStartDate =
                DateTime(joiningDate.year, joiningDate.month, joiningDate.day);
          }
        }

        // Normalize end date and cap it at today
        var effectiveEndDate =
            DateTime(_endDate.year, _endDate.month, _endDate.day);
        if (effectiveEndDate.isAfter(today)) {
          effectiveEndDate = today;
        }

        // If the start date is after the end date, they are already paid up to the target date.
        if (effectiveStartDate.isAfter(effectiveEndDate)) {
          alreadyPaidCount++;
          continue;
        }

        final daysInMonth =
            DateTime(effectiveStartDate.year, effectiveStartDate.month + 1, 0)
                .day;
        final String rangeLabel =
            '${DateFormat('dd MMM').format(effectiveStartDate)} - ${DateFormat('dd MMM').format(effectiveEndDate)}';
        final String recordId =
            '${staffId}_${DateFormat('yyyyMMdd').format(effectiveStartDate)}_${DateFormat('yyyyMMdd').format(effectiveEndDate)}';

        // Remove ALL existing PENDING records for this staff that overlap the new period.
        // This allows regeneration when the date range changes, avoiding phantom duplicates.
        _generatedSalaries.removeWhere((r) {
          if (r.staffId != staffId || r.status != 'Pending') return false;
          // Parse record start/end from ID
          final parts = r.id.split('_');
          if (parts.length >= 3) {
            try {
              final rs = parts[parts.length - 2];
              final re = parts[parts.length - 1];
              final rStart = DateTime(int.parse(rs.substring(0, 4)),
                  int.parse(rs.substring(4, 6)), int.parse(rs.substring(6, 8)));
              final rEnd = DateTime(int.parse(re.substring(0, 4)),
                  int.parse(re.substring(4, 6)), int.parse(re.substring(6, 8)));
              // Remove if overlaps with the new effectiveStart..effectiveEnd
              return !rEnd.isBefore(effectiveStartDate) &&
                  !rStart.isAfter(effectiveEndDate);
            } catch (_) {}
          }
          return r.id == recordId; // fallback: exact match
        });

        // Clear existing PENDING record for this exact period to allow fresh recalculation
        _generatedSalaries.removeWhere((r) {
          if (r.staffId != staffId || r.status != 'Pending') return false;
          final parts = r.id.split('_');
          if (parts.length >= 3) {
            try {
              final rs = parts[parts.length - 2];
              final re = parts[parts.length - 1];
              final rStart = DateTime(int.parse(rs.substring(0, 4)),
                  int.parse(rs.substring(4, 6)), int.parse(rs.substring(6, 8)));
              final rEnd = DateTime(int.parse(re.substring(0, 4)),
                  int.parse(re.substring(4, 6)), int.parse(re.substring(6, 8)));
              return !rEnd.isBefore(effectiveStartDate) &&
                  !rStart.isAfter(effectiveEndDate);
            } catch (_) {}
          }
          return r.id == recordId;
        });

        final name = staff['name'] ?? 'Staff';
        final role = staff['role'] ?? 'Staff';
        final basicValue =
            double.tryParse(staff['salaryValue']?.toString() ?? '0') ?? 0.0;
        final commissionRate = double.tryParse(
                staff['commissionPercentage']?.toString() ??
                    staff['commissionRate']?.toString() ??
                    '10') ??
            10.0;

        // Calculate attendance metrics
        int present = 0;
        int absent = 0;
        int lateDays = 0;
        int earlyExit = 0;
        int leaves = 0;
        int sundays = 0;
        int holidays = 0;

        for (var att in attendanceList) {
          if (att['staffId']?.toString() == staffId && att['date'] != null) {
            try {
              final approvalStatus =
                  att['approvalStatus']?.toString().toUpperCase() ?? 'APPROVED';
              if (approvalStatus == 'REJECTED') continue;

              final date = DateTime.parse(att['date']);
              // Normalize dates to midnight for range checks
              final dateMidnight = DateTime(date.year, date.month, date.day);
              final startMidnight = DateTime(effectiveStartDate.year,
                  effectiveStartDate.month, effectiveStartDate.day);
              final endMidnight = DateTime(effectiveEndDate.year,
                  effectiveEndDate.month, effectiveEndDate.day);
              if (!dateMidnight.isBefore(startMidnight) &&
                  !dateMidnight.isAfter(endMidnight)) {
                final status = att['status']?.toString().toUpperCase();
                if (status == 'PRESENT' || status == 'LATE') {
                  present++;
                } else if (status == 'ABSENT') {
                  absent++;
                } else if (status == 'LEAVE') {
                  leaves++;
                } else if (status == 'SUNDAY') {
                  sundays++;
                } else if (status == 'HOLIDAY') {
                  holidays++;
                }
                if (status == 'LATE') lateDays++;
                if (att['earlyExit'] == true || att['earlyExit'] == 'true')
                  earlyExit++;
              }
            } catch (_) {}
          }
        }

        // Calculate commission from salesList (based on actual payment dates in range & item-level staff assignment)
        final startMidnight = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
        final endMidnight = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);

        double earnedCommission = 0;
        for (var sale in salesList) {
          if (sale['status'] != 'ACTIVE') continue;
          final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
          if (total <= 0) continue;

          // Calculate payments received for this sale within [startMidnight, endMidnight]
          final List<dynamic> payments = sale['payments'] as List<dynamic>? ?? [];
          double rangePaid = 0.0;

          if (payments.isNotEmpty) {
            for (var p in payments) {
              final pDateStr = p['date']?.toString() ?? '';
              final pDate = DateTime.tryParse(pDateStr);
              if (pDate == null) continue;
              final localPDate = pDate.toLocal();
              final pMidnight = DateTime(localPDate.year, localPDate.month, localPDate.day);
              if (!pMidnight.isBefore(startMidnight) && !pMidnight.isAfter(endMidnight)) {
                rangePaid += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
              }
            }
          } else {
            // Fallback: check creation date
            final dateStr = sale['createdAt']?.toString() ?? sale['date']?.toString() ?? '';
            final saleDate = DateTime.tryParse(dateStr);
            if (saleDate != null) {
              final localSaleDate = saleDate.toLocal();
              final dateMidnight = DateTime(localSaleDate.year, localSaleDate.month, localSaleDate.day);
              if (!dateMidnight.isBefore(startMidnight) && !dateMidnight.isAfter(endMidnight)) {
                rangePaid = double.tryParse(sale['amountPaid']?.toString() ?? '0') ?? 0.0;
              }
            }
          }

          if (rangePaid <= 0) continue;
          final payRatio = (rangePaid / total).clamp(0.0, 1.0);

          final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
          for (var item in items) {
            final isInternal = item['isInternal'] == true || item['isInternal']?.toString() == 'true';
            if (isInternal) continue;

            final itemStaffId = item['staffId']?.toString() ?? sale['staffId']?.toString();
            if (itemStaffId != staffId) continue;

            final commVal = double.tryParse(item['commissionAmount']?.toString() ?? '0') ?? 0.0;
            if (commVal > 0) {
              earnedCommission += commVal * payRatio;
            } else {
              final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
              final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
              final discount = double.tryParse(item['discountAmount']?.toString() ?? '0') ?? 0.0;
              final netItemPrice = ((price * qty) - discount) * payRatio;
              earnedCommission += netItemPrice * (commissionRate / 100);
            }
          }
        }
        final expectedComm = earnedCommission;

        // Parse timing-based rates and parameters from staff profile
        final double lateDeductionRate =
            double.tryParse(staff['lateDeductionRate']?.toString() ?? '0') ??
                0.0;
        final double earlyExitDeductionRate = double.tryParse(
                staff['earlyExitDeductionRate']?.toString() ?? '0') ??
            0.0;
        final int allowedLeaves =
            int.tryParse(staff['allowedLeaves']?.toString() ?? '0') ?? 0;

        // Calculate basic generated salary based on salaryType
        double salaryGenerated = 0;
        double deductionsVal = 0.0;

        if (salaryType == 'MONTHLY' ||
            salaryType == 'MONTHLY_PLUS_COMMISSION') {
          final double dailyRate = basicValue / daysInMonth;

          // periodDays is the total days in the selected range
          final int periodDays =
              effectiveEndDate.difference(effectiveStartDate).inDays + 1;
          final double grossPeriodSalary = dailyRate * periodDays;

          // Leaves exceeding the allowed leaves limit count as unpaid deductions (pay zero for those days)
          final int unpaidLeaves =
              leaves > allowedLeaves ? (leaves - allowedLeaves) : 0;
          final int deductionDays = absent + unpaidLeaves;
          final double absenceDeduction = deductionDays * dailyRate;

          final double lateDeduction = lateDays * lateDeductionRate;
          final double earlyExitDeduction = earlyExit * earlyExitDeductionRate;

          double finalBaseSalary = grossPeriodSalary -
              absenceDeduction -
              lateDeduction -
              earlyExitDeduction;
          if (finalBaseSalary < 0) finalBaseSalary = 0;

          salaryGenerated = finalBaseSalary;

          // Total deductions for the pay slip
          deductionsVal = absenceDeduction + lateDeduction + earlyExitDeduction;
        } else if (salaryType == 'DAILY' ||
            salaryType == 'DAILY_PLUS_COMMISSION') {
          final double dailyRate = basicValue;
          final int paidLeaves =
              leaves > allowedLeaves ? allowedLeaves : leaves;
          final int paidDays = present + sundays + holidays + paidLeaves;

          final double baseSalaryForPaidDays = dailyRate * paidDays;
          final double lateDeduction = lateDays * lateDeductionRate;
          final double earlyExitDeduction = earlyExit * earlyExitDeductionRate;

          double finalBaseSalary =
              baseSalaryForPaidDays - lateDeduction - earlyExitDeduction;
          if (finalBaseSalary < 0) finalBaseSalary = 0;

          salaryGenerated = finalBaseSalary;

          final double absenceDeduction = absent * dailyRate;
          final double totalDeduct =
              absenceDeduction + lateDeduction + earlyExitDeduction;
          final double leavesCredit = paidLeaves * dailyRate;
          deductionsVal =
              (totalDeduct - leavesCredit).clamp(0.0, double.infinity);
        } else if (salaryType == 'COMMISSION') {
          salaryGenerated = 0;
        } else {
          salaryGenerated = basicValue; // Fallback
        }

        if (salaryGenerated < 0) salaryGenerated = 0;

        // Deduct any salary and commission ALREADY PAID in existing 'Paid' records for this period
        double alreadyPaidSalary = 0.0;
        double alreadyPaidCommission = 0.0;
        for (final r in _generatedSalaries) {
          if (r.staffId == staffId && r.status == 'Paid') {
            final parts = r.id.split('_');
            if (parts.length >= 3) {
              try {
                final rs = parts[parts.length - 2];
                final re = parts[parts.length - 1];
                final rStart = DateTime(int.parse(rs.substring(0, 4)),
                    int.parse(rs.substring(4, 6)), int.parse(rs.substring(6, 8)));
                final rEnd = DateTime(int.parse(re.substring(0, 4)),
                    int.parse(re.substring(4, 6)), int.parse(re.substring(6, 8)));
                if (!rEnd.isBefore(effectiveStartDate) && !rStart.isAfter(effectiveEndDate)) {
                  alreadyPaidSalary += r.salaryGenerated;
                  alreadyPaidCommission += r.commission;
                }
              } catch (_) {}
            }
          }
        }

        final double remainingSalary = (salaryGenerated - alreadyPaidSalary).clamp(0.0, double.infinity);
        final double remainingComm = (expectedComm - alreadyPaidCommission).clamp(0.0, double.infinity);

        if (remainingSalary <= 0 && remainingComm <= 0) {
          alreadyPaidCount++;
          continue;
        }

        salaryGenerated = remainingSalary;
        final double finalComm = remainingComm;

        final double balanceVal =
            double.tryParse(staff['balance']?.toString() ?? '0') ?? 0.0;
        final double loan = balanceVal > 0 ? balanceVal : 0.0;
        final netPay = salaryGenerated + finalComm - loan;

        final newRecord = GeneratedSalaryRecord(
          id: recordId,
          staffId: staffId,
          name: name,
          role: role,
          salaryType: salaryType,
          basicSalary: basicValue,
          month: rangeLabel,
          year: effectiveStartDate.year,
          present: present,
          absent: absent,
          lateDays: lateDays,
          earlyExit: earlyExit,
          salaryGenerated: salaryGenerated,
          commission: finalComm,
          amountPaid: netPay < 0 ? 0.0 : netPay,
          loanRepayment: loan,
          deductions: deductionsVal,
          status: 'Pending',
        );

        _generatedSalaries.add(newRecord);
        generatedCount++;
      }
    });

    _saveGeneratedSalaries();

    if (generatedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: _kGreen,
        content: Text(
            'Generated salary records for $generatedCount staff member(s).${alreadyPaidCount > 0 ? " ($alreadyPaidCount staff already paid/skipped)" : ""}',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold, color: Colors.white)),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: _kOrange,
        content: Text(
            'No new salary records generated. already paid or no eligible period.',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold, color: Colors.white)),
      ));
    }
  }

  void _deleteSalaryRecord(String id) {
    final record = _generatedSalaries.firstWhere((r) => r.id == id,
        orElse: () => _generatedSalaries.first);
    final isPaidRecord = record.status == 'Paid';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Record?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Are you sure you want to delete this salary record for ${record.name}?',
                style: GoogleFonts.outfit()),
            if (isPaidRecord) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This is a PAID record. Deleting it will remove the pay-block and allow regeneration for this period.',
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.outfit(color: Colors.black38)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);

              if (isPaidRecord) {
                try {
                  if (record.expenseId != null) {
                    await ref
                        .read(apiServiceProvider)
                        .deleteExpense(record.expenseId!);
                  }
                  if (record.deductionId != null) {
                    await ref
                        .read(apiServiceProvider)
                        .deleteSalaryDeduction(record.deductionId!);
                  }
                  ref.invalidate(reportsProvider);
                  ref.invalidate(ledgerProvider);
                  ref.invalidate(expensesProvider);
                  ref.invalidate(salonsProvider);
                  ref.invalidate(staffProvider);
                  ref.invalidate(dashboardViewModelProvider);
                  ref.invalidate(dashboardMetricsProvider);
                  if (_selectedSalonId != null) {
                    ref.invalidate(staffForSalonProvider(_selectedSalonId!));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Failed to delete associated records: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                  return;
                }
              }

              setState(() {
                _generatedSalaries.removeWhere((r) => r.id == id);
              });
              await _saveGeneratedSalaries();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Salary record deleted successfully.'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMakePaymentDialog(GeneratedSalaryRecord record) {
    final bonusC = TextEditingController(text: record.bonus.toStringAsFixed(2));
    final deductionC =
        TextEditingController(text: record.deductions.toStringAsFixed(2));
    final loanC =
        TextEditingController(text: record.loanRepayment.toStringAsFixed(2));
    final gross =
        record.salaryGenerated + record.commission + record.deductions;
    final initialPaid =
        (gross + record.bonus - record.deductions - record.loanRepayment)
            .clamp(0.0, double.infinity);
    final paidC = TextEditingController(text: initialPaid.toStringAsFixed(2));

    DateTime payoutDate = DateTime.now();
    String paymentMethod = 'CASH';
    String? selectedPaymentAccountId;
    final cashPartController = TextEditingController();
    final onlinePartController = TextEditingController();

    // showModalBottomSheet is more reliable on Flutter web than showDialog
    // (avoids barrier-dismissal race condition and Navigator context issues)
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
          builder: (context, setS) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
                  left: 24,
                  right: 24,
                  top: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Process Payroll Payout',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: _kDark)),
                    const SizedBox(height: 4),
                    Text('${record.name}  ·  ${record.month} ${record.year}',
                        style: GoogleFonts.outfit(
                            color: Colors.black45, fontSize: 13)),
                    const Divider(height: 28),
                    StatefulBuilder(
                      builder: (context, setS) {
                        void recalculate() {
                          final grossVal = record.salaryGenerated +
                              record.commission +
                              record.deductions;
                          final bonusVal = double.tryParse(bonusC.text) ?? 0.0;
                          final dedVal =
                              double.tryParse(deductionC.text) ?? 0.0;
                          final loanVal = double.tryParse(loanC.text) ?? 0.0;
                          final net = (grossVal + bonusVal - dedVal - loanVal)
                              .clamp(0.0, double.infinity);
                          paidC.text = net.toStringAsFixed(2);
                          if (paymentMethod == 'SPLIT') {
                            final half = (net / 2).roundToDouble();
                            cashPartController.text = half.toStringAsFixed(2);
                            onlinePartController.text = (net - half).toStringAsFixed(2);
                          }
                        }

                        return Column(
                          children: [
                            _buildDialogField(bonusC, 'Bonus / Allowance',
                                LucideIcons.plusCircle, (_) {
                              setS(() {
                                recalculate();
                              });
                            }),
                            const SizedBox(height: 12),
                            _buildDialogField(deductionC, 'Salary Deductions',
                                LucideIcons.minusCircle, (_) {
                              setS(() {
                                recalculate();
                              });
                            }),
                            const SizedBox(height: 12),
                            _buildDialogField(loanC, 'Loan Repayment Deduct',
                                LucideIcons.wallet, (_) {
                              setS(() {
                                recalculate();
                              });
                            }),
                            const SizedBox(height: 12),
                            _buildDialogField(paidC, 'Final Net Amount Paid',
                                LucideIcons.banknote, (_) {}),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
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
                        labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'CASH', child: Text('Cash Drawer')),
                        DropdownMenuItem(value: 'ONLINE', child: Text('Online / Bank / Wallet')),
                        DropdownMenuItem(value: 'SPLIT', child: Text('Split (Cash + Online)')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setS(() {
                          paymentMethod = v;
                          if (paymentMethod == 'SPLIT') {
                            final total = double.tryParse(paidC.text) ?? record.amountPaid;
                            final half = (total / 2).roundToDouble();
                            cashPartController.text = half.toStringAsFixed(2);
                            onlinePartController.text = (total - half).toStringAsFixed(2);
                          }
                        });
                      },
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

                          if (selectedPaymentAccountId == null && accounts.isNotEmpty) {
                            selectedPaymentAccountId = accounts.first.id;
                          }

                          if (accounts.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              child: Row(
                                children: [
                                  Icon(LucideIcons.alertCircle, size: 16, color: Colors.amber.shade900),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No active bank/wallet accounts configured. Add one in Settings.',
                                      style: GoogleFonts.outfit(fontSize: 12, color: Colors.amber.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return DropdownButtonFormField<String>(
                            value: selectedPaymentAccountId,
                            style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                            decoration: InputDecoration(
                              labelText: paymentMethod == 'SPLIT' ? 'Online Bank Account (Split Portion) *' : 'Select Bank / Wallet Account *',
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
                            onChanged: (v) => setS(() => selectedPaymentAccountId = v),
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
                                final total = double.tryParse(paidC.text) ?? 0;
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
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: sheetCtx,
                          initialDate: payoutDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setS(() => payoutDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: _kBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.calendar,
                                size: 16, color: _kPrimary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Payout Date',
                                      style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          color: Colors.black54,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(
                                      DateFormat('yyyy-MM-dd')
                                          .format(payoutDate),
                                      style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          color: _kDark,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const Icon(LucideIcons.chevronRight,
                                size: 16, color: Colors.black26),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            icon: const Icon(LucideIcons.banknote,
                                size: 16, color: Colors.white),
                            label: const Text('Confirm & Pay',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              final paidAmount = double.tryParse(paidC.text) ??
                                  record.amountPaid;
                              final bonusVal =
                                  double.tryParse(bonusC.text) ?? 0.0;
                              final dedVal =
                                  double.tryParse(deductionC.text) ?? 0.0;
                              final loanVal =
                                  double.tryParse(loanC.text) ?? 0.0;

                              double cashAmt = paidAmount;
                              double onlineAmt = 0.0;
                              if (paymentMethod == 'ONLINE') {
                                cashAmt = 0.0;
                                onlineAmt = paidAmount;
                              } else if (paymentMethod == 'SPLIT') {
                                cashAmt = double.tryParse(cashPartController.text) ?? 0.0;
                                onlineAmt = double.tryParse(onlinePartController.text) ?? 0.0;
                                if (cashAmt + onlineAmt <= 0) {
                                  cashAmt = paidAmount / 2;
                                  onlineAmt = paidAmount - cashAmt;
                                }
                              }

                              if ((paymentMethod == 'ONLINE' || (paymentMethod == 'SPLIT' && onlineAmt > 0)) && (selectedPaymentAccountId == null || selectedPaymentAccountId!.isEmpty)) {
                                if (sheetCtx.mounted) {
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(const SnackBar(
                                    content: Text('Please select a bank or wallet account for the online payout.', style: TextStyle(color: Colors.white)),
                                    backgroundColor: Colors.redAccent,
                                  ));
                                }
                                return;
                              }

                              // Close bottom sheet first
                              Navigator.pop(sheetCtx);

                              try {
                                final user = ref.read(authProvider);
                                final salonId = _selectedSalonId ??
                                    user?['salonId']?.toString() ??
                                    '';

                                final expenseResult = await ref
                                    .read(apiServiceProvider)
                                    .createExpense({
                                  'name': 'Salary: ${record.name} ${record.month} ${record.year}'
                                      ' (Base: ${record.salaryGenerated.toStringAsFixed(2)}'
                                      ', Comm: ${record.commission.toStringAsFixed(2)}'
                                      ', Bonus: ${bonusVal.toStringAsFixed(2)}'
                                      ', Ded: ${dedVal.toStringAsFixed(2)}'
                                      ', Loan: ${loanVal.toStringAsFixed(2)})',
                                  'amount': paidAmount,
                                  'category': 'Salaries',
                                  'staffId': record.staffId,
                                  'date': DateFormat('yyyy-MM-dd')
                                      .format(payoutDate),
                                  'salonId': salonId,
                                  'paymentMethod': paymentMethod,
                                  'paymentAccountId': (paymentMethod == 'ONLINE' || (paymentMethod == 'SPLIT' && onlineAmt > 0)) ? selectedPaymentAccountId : null,
                                  if (paymentMethod == 'SPLIT') 'cashAmount': cashAmt,
                                  if (paymentMethod == 'SPLIT') 'onlineAmount': onlineAmt,
                                });
                                final String? newExpenseId =
                                    expenseResult['id']?.toString();

                                String? newDeductionId;
                                if (loanVal > 0) {
                                  final dedResult = await ref
                                      .read(apiServiceProvider)
                                      .createSalaryDeduction(
                                        record.staffId,
                                        'DEDUCTION',
                                        loanVal,
                                        reason:
                                            'Loan Repayment (Payroll: ${record.month} ${record.year})',
                                        date: DateFormat('yyyy-MM-dd')
                                            .format(payoutDate),
                                        paymentMethod: paymentMethod == 'SPLIT' ? 'CASH' : paymentMethod,
                                        paymentAccountId: paymentMethod == 'ONLINE' ? selectedPaymentAccountId : null,
                                      );
                                  newDeductionId = dedResult['id']?.toString();
                                }

                                // Invalidate providers to show real-time changes on Reports, Expenses, Staff & Dashboard
                                ref.invalidate(reportsProvider);
                                ref.invalidate(ledgerProvider);
                                ref.invalidate(expensesProvider);
                                ref.invalidate(salonsProvider);
                                ref.invalidate(staffProvider);
                                ref.invalidate(dashboardViewModelProvider);
                                ref.invalidate(dashboardMetricsProvider);
                                if (_selectedSalonId != null) {
                                  ref.invalidate(
                                      staffForSalonProvider(_selectedSalonId!));
                                }

                                setState(() {
                                  record.status = 'Paid';
                                  record.bonus = bonusVal;
                                  record.deductions = dedVal;
                                  record.loanRepayment = loanVal;
                                  record.amountPaid = paidAmount;
                                  record.expenseId = newExpenseId;
                                  record.deductionId = newDeductionId;
                                  record.paymentMethod = paymentMethod;
                                  record.paymentAccountId = selectedPaymentAccountId;
                                });
                                await _saveGeneratedSalaries();

                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    backgroundColor: _kGreen,
                                    duration: const Duration(seconds: 4),
                                    content: Text(
                                      '✓ Salary payout of PKR ${paidAmount.toStringAsFixed(2)} recorded!',
                                      style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ));
                                }
                              } catch (e) {
                                final msg =
                                    e.toString().replaceAll('Exception: ', '');
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    backgroundColor: Colors.red.shade700,
                                    duration: const Duration(seconds: 8),
                                    content: Text('Payment failed: $msg',
                                        style: GoogleFonts.outfit(
                                            color: Colors.white)),
                                  ));
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              )),
    );
  }

  Future<void> _downloadOrPrintSlipPdf(
      GeneratedSalaryRecord record, String salonName, String currency) async {
    final pdf = pw.Document();
    
    final primaryColor = PdfColors.blue800;
    final secondaryColor = PdfColors.blue700;
    final darkBlueColor = PdfColors.blue900;
    final greyColor = PdfColors.grey400;

    final headerStyle = pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: darkBlueColor);
    final subHeaderStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: secondaryColor);
    final labelStyle = pw.TextStyle(fontSize: 10, color: secondaryColor);
    final valueStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: darkBlueColor);
    final titleStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(salonName, style: headerStyle, textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 6),
                    pw.Text('OFFICIAL SALARY PAY SLIP', style: subHeaderStyle),
                  ]
                )
              ),
              pw.SizedBox(height: 30),
              pw.Divider(color: primaryColor),

              // Employee Details
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Employee Name:', style: labelStyle),
                      pw.Text(record.name, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: darkBlueColor)),
                      pw.SizedBox(height: 10),
                      pw.Text('Designation:', style: labelStyle),
                      pw.Text(record.role, style: valueStyle),
                    ]
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Salary Period:', style: labelStyle),
                      pw.Text('${record.month} ${record.year}', style: valueStyle),
                      pw.SizedBox(height: 10),
                      pw.Text('Attendance Summary:', style: labelStyle),
                      pw.Text('${record.present} Present / ${record.absent} Absent', style: valueStyle),
                    ]
                  )
                ]
              ),
              pw.SizedBox(height: 20),
              pw.Divider(color: primaryColor),
              pw.SizedBox(height: 10),

              // Earnings & Deductions Header
              pw.Text('Salary Breakdown Details', style: titleStyle),
              pw.SizedBox(height: 10),
              
              _pwBuildSlipRow('Basic Pay Rate:', '$currency ${record.basicSalary.toStringAsFixed(2)}', labelStyle: labelStyle, valueStyle: valueStyle),
              _pwBuildSlipRow('Salary Earned (Pro-rata):', '$currency ${record.salaryGenerated.toStringAsFixed(2)}', labelStyle: labelStyle, valueStyle: valueStyle),
              _pwBuildSlipRow('Commission:', '$currency ${record.commission.toStringAsFixed(2)}', labelStyle: labelStyle, valueStyle: valueStyle),
              if (record.bonus > 0)
                _pwBuildSlipRow('Bonus / Allowances:', '+ $currency ${record.bonus.toStringAsFixed(2)}', labelStyle: labelStyle, valueStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
              if (record.deductions > 0)
                _pwBuildSlipRow('Absence Deductions:', '- $currency ${record.deductions.toStringAsFixed(2)}', labelStyle: labelStyle, valueStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
              if (record.loanRepayment > 0)
                _pwBuildSlipRow('Loan Installment Deductions:', '- $currency ${record.loanRepayment.toStringAsFixed(2)}', labelStyle: labelStyle, valueStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
              
              pw.SizedBox(height: 15),
              pw.Divider(color: primaryColor, thickness: 1),
              _pwBuildSlipRow('Net Amount Paid:', '$currency ${record.amountPaid.toStringAsFixed(2)}', labelStyle: titleStyle, valueStyle: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: darkBlueColor)),
              
              pw.Spacer(),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Thank you for your hard work!', style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic, color: secondaryColor)),
                    pw.SizedBox(height: 4),
                    pw.Text('Powered by Salon Pro System', style: pw.TextStyle(fontSize: 8, color: greyColor)),
                  ]
                )
              )
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'SalarySlip_${record.name}_${record.month}_${record.year}.pdf',
    );
  }

  pw.Widget _pwBuildSlipRow(String label, String val, {required pw.TextStyle labelStyle, required pw.TextStyle valueStyle}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: labelStyle),
          pw.Text(val, style: valueStyle),
        ],
      ),
    );
  }

  void _showPrintSlipDialog(GeneratedSalaryRecord record) {
    final currency = ref.read(currencyProvider);
    final authState = ref.read(authProvider);
    final salon = authState?['salon'] ??
        (authState?['salonId'] != null
            ? {'name': authState?['salonName'] ?? 'SALON PRO', 'address': ''}
            : null);
    final salonName = salon?['name'] ?? 'SALON PRO';

    final staffAsync = _selectedSalonId != null
        ? ref.read(staffForSalonProvider(_selectedSalonId!))
        : ref.read(staffProvider);
    final staffList = staffAsync.value ?? [];
    final staff = staffList.cast<dynamic>().firstWhere(
          (s) => s['id']?.toString() == record.staffId,
          orElse: () => null,
        );
    final rawPhone = staff?['phone']?.toString() ?? '';

    showDialog(
        context: context,
        useRootNavigator: true,
        builder: (context) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Container(
              width: 380,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        const Icon(LucideIcons.scissors,
                            color: _kPrimary, size: 28),
                        const SizedBox(height: 6),
                        Text(salonName.toUpperCase(),
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _kPrimary),
                            textAlign: TextAlign.center),
                        Text('Official Salary Pay Slip',
                            style: GoogleFonts.outfit(
                                fontSize: 12, color: Colors.black45)),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  _buildSlipRow('Employee Name:', record.name),
                  _buildSlipRow('Designation:', record.role),
                  _buildSlipRow(
                      'Salary Period:', '${record.month} ${record.year}'),
                  _buildSlipRow('Attendance Days:',
                      '${record.present} Present / ${record.absent} Absent'),
                  const Divider(height: 16),
                  _buildSlipRow(
                      'Basic Pay Rate:', record.basicSalary.toStringAsFixed(2)),
                  _buildSlipRow('Salary Earned:',
                      record.salaryGenerated.toStringAsFixed(2)),
                  _buildSlipRow(
                      'Commission:', record.commission.toStringAsFixed(2)),
                  if (record.bonus > 0)
                    _buildSlipRow('Bonus / Allowances:',
                        '+ ${record.bonus.toStringAsFixed(2)}',
                        color: Colors.green),
                  if (record.deductions > 0)
                    _buildSlipRow('Absence Deductions:',
                        '- ${record.deductions.toStringAsFixed(2)}',
                        color: Colors.red),
                  if (record.loanRepayment > 0)
                    _buildSlipRow('Loan Installment Deduct:',
                        '- ${record.loanRepayment.toStringAsFixed(2)}',
                        color: Colors.orange),
                  const Divider(height: 16),
                  _buildSlipRow(
                      'Net Amount Paid:', record.amountPaid.toStringAsFixed(2),
                      isBold: true, color: _kPrimary),
                  const SizedBox(height: 24),
                  Center(
                    child: Text('Thank you for your hard work!',
                        style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.black38)),
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (rawPhone.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Employee phone number not found!')));
                              return;
                            }
                            var cleanPhone =
                                rawPhone.replaceAll(RegExp(r'\D'), '');
                            if (cleanPhone.startsWith('0')) {
                              cleanPhone = '92${cleanPhone.substring(1)}';
                            }

                            final message = '''
*SALARY SLIP - $salonName*
----------------------------------
*Employee Name:* ${record.name}
*Designation:* ${record.role}
*Salary Period:* ${record.month} ${record.year}
*Attendance Days:* ${record.present} Present / ${record.absent} Absent
----------------------------------
*Basic Pay Rate:* $currency ${record.basicSalary.toStringAsFixed(2)}
*Salary Earned:* $currency ${record.salaryGenerated.toStringAsFixed(2)}
*Commission:* $currency ${record.commission.toStringAsFixed(2)}
${record.bonus > 0 ? '*Bonus / Allowances:* + $currency ${record.bonus.toStringAsFixed(2)}\n' : ''}${record.deductions > 0 ? '*Absence Deductions:* - $currency ${record.deductions.toStringAsFixed(2)}\n' : ''}${record.loanRepayment > 0 ? '*Loan Installment:* - $currency ${record.loanRepayment.toStringAsFixed(2)}\n' : ''}----------------------------------
*Net Paid:* $currency ${record.amountPaid.toStringAsFixed(2)}
----------------------------------
Thank you for your hard work!
''';
                            final whatsappUrl = Uri.parse(
                                'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
                            if (await canLaunchUrl(whatsappUrl)) {
                              await launchUrl(whatsappUrl,
                                  mode: LaunchMode.externalApplication);
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Could not open WhatsApp.')));
                              }
                            }
                          },
                          icon: const Icon(LucideIcons.phone,
                              size: 14, color: Colors.white),
                          label: const Text('WhatsApp',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await _downloadOrPrintSlipPdf(
                                record, salonName, currency);
                          },
                          icon: const Icon(LucideIcons.printer,
                              size: 14, color: Colors.white),
                          label: const Text('Print/PDF',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
            ],
          );
        });
  }

  Widget _buildSlipRow(String label, String val,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54)),
          Text(val,
              style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: color ?? _kDark)),
        ],
      ),
    );
  }

  void _showCalculationBreakdownDialog(
      GeneratedSalaryRecord r, List<dynamic> staffList) {
    final currency = ref.read(currencyProvider);
    final staffProfile = staffList.firstWhere(
      (s) => s['id']?.toString() == r.staffId,
      orElse: () => null,
    );

    final double lateRate = staffProfile != null
        ? (double.tryParse(
                staffProfile['lateDeductionRate']?.toString() ?? '0') ??
            0.0)
        : 0.0;
    final double earlyRate = staffProfile != null
        ? (double.tryParse(
                staffProfile['earlyExitDeductionRate']?.toString() ?? '0') ??
            0.0)
        : 0.0;
    final int allowedLv = staffProfile != null
        ? (int.tryParse(staffProfile['allowedLeaves']?.toString() ?? '0') ?? 0)
        : 0;

    final int daysInM = DateTime(_startDate.year, _startDate.month + 1, 0).day;
    final int periodDays = _endDate.difference(_startDate).inDays + 1;
    final double dailyRate = r.basicSalary / daysInM;

    showDialog(
      context: context,
      builder: (ctx) {
        Widget detailRow(String label, String value,
            {bool isBold = false, Color? color}) {
          return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: GoogleFonts.outfit(
                          fontSize: 12, color: Colors.black54)),
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                      color: color ?? _kDark,
                    ),
                  ),
                ],
              ));
        }

        List<Widget> content = [];

        if (r.salaryType == 'MONTHLY' ||
            r.salaryType == 'MONTHLY_PLUS_COMMISSION') {
          final double gross = dailyRate * periodDays;
          final int unpaidLv =
              r.leaves > allowedLv ? (r.leaves - allowedLv) : 0;
          final int dedDays = r.absent + unpaidLv;
          final double absDeduct = dedDays * dailyRate;
          final double lateDeduct = r.lateDays * lateRate;
          final double earlyDeduct = r.earlyExit * earlyRate;

          content = [
            detailRow('Calculation Method', 'Monthly Base Salary',
                isBold: true),
            const Divider(),
            detailRow('Monthly Basic',
                '$currency ${r.basicSalary.toStringAsFixed(2)}'),
            detailRow('Days in Month', '$daysInM days'),
            detailRow(
                'Daily Wage Rate', '$currency ${dailyRate.toStringAsFixed(2)}'),
            detailRow('Period Selected', '$periodDays days'),
            detailRow(
                'Gross Period Salary', '$currency ${gross.toStringAsFixed(2)}',
                isBold: true),
            const Divider(),
            detailRow('Allowed Monthly Leaves', '$allowedLv days'),
            detailRow('Leaves Taken', '${r.leaves} days'),
            detailRow('Unpaid Leaves', '$unpaidLv days'),
            detailRow('Deduction Days (Absent + Unpaid Leaves)',
                '${r.absent} + $unpaidLv = $dedDays days'),
            detailRow('Absence Deduction',
                '-$currency ${absDeduct.toStringAsFixed(2)}',
                color: Colors.red),
            detailRow(
                'Late Days (Rate: $currency ${lateRate.toStringAsFixed(2)})',
                '${r.lateDays} days'),
            detailRow(
                'Late Deduction', '-$currency ${lateDeduct.toStringAsFixed(2)}',
                color: Colors.red),
            detailRow(
                'Early Exits (Rate: $currency ${earlyRate.toStringAsFixed(2)})',
                '${r.earlyExit} days'),
            detailRow('Early Exit Deduction',
                '-$currency ${earlyDeduct.toStringAsFixed(2)}',
                color: Colors.red),
            const Divider(),
            detailRow('Earned Base Salary',
                '$currency ${r.salaryGenerated.toStringAsFixed(2)}',
                isBold: true, color: Colors.green.shade700),
          ];
        } else if (r.salaryType == 'DAILY' ||
            r.salaryType == 'DAILY_PLUS_COMMISSION') {
          final int paidLeaves = r.leaves > allowedLv ? allowedLv : r.leaves;
          final double lateDeduct = r.lateDays * lateRate;
          final double earlyDeduct = r.earlyExit * earlyRate;
          final double totalPaidDaysAmount =
              r.salaryGenerated + lateDeduct + earlyDeduct;
          final double dailyWage = r.basicSalary;
          final double paidDaysCount =
              dailyWage > 0 ? (totalPaidDaysAmount / dailyWage) : 0.0;

          content = [
            detailRow('Calculation Method', 'Daily Wage Rate', isBold: true),
            const Divider(),
            detailRow('Daily Basic Rate',
                '$currency ${r.basicSalary.toStringAsFixed(2)}'),
            detailRow('Effective Paid Days',
                '${paidDaysCount.toStringAsFixed(1)} days'),
            detailRow('Gross Earned Salary',
                '$currency ${totalPaidDaysAmount.toStringAsFixed(2)}',
                isBold: true),
            const Divider(),
            detailRow(
                'Late Days (Rate: $currency ${lateRate.toStringAsFixed(2)})',
                '${r.lateDays} days'),
            detailRow(
                'Late Deduction', '-$currency ${lateDeduct.toStringAsFixed(2)}',
                color: Colors.red),
            detailRow(
                'Early Exits (Rate: $currency ${earlyRate.toStringAsFixed(2)})',
                '${r.earlyExit} days'),
            detailRow('Early Exit Deduction',
                '-$currency ${earlyDeduct.toStringAsFixed(2)}',
                color: Colors.red),
            const Divider(),
            detailRow('Earned Base Salary',
                '$currency ${r.salaryGenerated.toStringAsFixed(2)}',
                isBold: true, color: Colors.green.shade700),
          ];
        } else if (r.salaryType == 'COMMISSION') {
          content = [
            detailRow('Calculation Method', 'Commission-Only Structure',
                isBold: true),
            const Divider(),
            detailRow('Basic Base Salary', '$currency 0.00'),
            detailRow('Total Base Earned', '$currency 0.00',
                isBold: true, color: Colors.green.shade700),
          ];
        } else {
          content = [
            detailRow('Calculation Method', 'Fixed Salary Payout',
                isBold: true),
            const Divider(),
            detailRow('Basic Salary',
                '$currency ${r.basicSalary.toStringAsFixed(2)}'),
            detailRow('Earned Base Salary',
                '$currency ${r.salaryGenerated.toStringAsFixed(2)}',
                isBold: true, color: Colors.green.shade700),
          ];
        }

        content.addAll([
          const Divider(),
          detailRow('Commission Earned',
              '+$currency ${r.commission.toStringAsFixed(2)}',
              color: Colors.teal.shade700),
          detailRow('Loan/Advance Repay',
              '-$currency ${r.loanRepayment.toStringAsFixed(2)}',
              color: Colors.orange.shade900),
          const Divider(),
          detailRow('Final Net Payout',
              '$currency ${r.amountPaid.toStringAsFixed(2)}',
              isBold: true, color: _kPrimary),
        ]);

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(LucideIcons.info, color: _kPrimary, size: 24),
              const SizedBox(width: 10),
              Text('Salary Breakdown',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: content,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close',
                  style: GoogleFonts.outfit(
                      color: _kPrimary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogField(TextEditingController controller, String label,
      IconData icon, ValueChanged<String> onChanged) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      style: GoogleFonts.outfit(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final salonsAsync = ref.watch(salonsProvider);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Financial & Salaries',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Colors.black38,
                    fontWeight: FontWeight.w500)),
            Text('Payroll Portal',
                style: GoogleFonts.outfit(
                    color: _kDark, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
      ),
      body: salonsAsync.when(
        data: (salons) {
          if (_selectedSalonId == null && salons.isNotEmpty) {
            final userSalonId = user?['salonId']?.toString() ??
                user?['salon']?['id']?.toString();
            final autoId = salons.any((s) => s['id']?.toString() == userSalonId)
                ? userSalonId
                : salons.first['id']?.toString();
            // Use post-frame to avoid setState during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedSalonId == null) {
                setState(() => _selectedSalonId = autoId);
              }
            });
          }

          final staffAsync = _selectedSalonId != null
              ? ref.watch(staffForSalonProvider(_selectedSalonId!))
              : ref.watch(staffProvider);

          final attAsync = _selectedSalonId != null
              ? ref.watch(attendanceForSalonProvider(_selectedSalonId!))
              : ref.watch(attendanceProvider);

          return staffAsync.when(
            data: (staffList) => attAsync.when(
              data: (attendanceList) {
                final reportParams = ReportParams(
                  start: _startDate,
                  end: _endDate,
                  salonId: _selectedSalonId,
                );
                final reportsAsync = ref.watch(reportsProvider(reportParams));

                return reportsAsync.when(
                  data: (reportData) {
                    final salesList =
                        reportData['recentSales'] as List<dynamic>? ??
                            reportData['sales'] as List<dynamic>? ??
                            [];
                    final currency = ref.watch(currencyProvider);
                    final selectedSalonName = salons.cast<dynamic>().firstWhere(
                            (s) => s['id']?.toString() == _selectedSalonId,
                            orElse: () => null)?['name'] ??
                        'My Salon';

                    final userRole =
                        user?['role']?.toString().toUpperCase() ?? '';
                    final isStaff = userRole == 'STAFF';

                    // Filter staffList based on salary category selection & role restriction
                    final filteredStaffList = staffList.where((s) {
                      if (isStaff) {
                        return s['user']?['id']?.toString() ==
                                user?['id']?.toString() ||
                            s['userId']?.toString() == user?['id']?.toString();
                      }
                      if (_filterSalaryType == 'ALL') return true;
                      return s['salaryType']?.toString().toUpperCase() ==
                          _filterSalaryType.toUpperCase();
                    }).toList();

                    // Filter generated list for display based on selected Date Range & salonId & salaryType category
                    final String rangeLabel =
                        '${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM').format(_endDate)}';
                    final filterStart = DateTime(
                        _startDate.year, _startDate.month, _startDate.day);
                    final filterEnd =
                        DateTime(_endDate.year, _endDate.month, _endDate.day);

                    final filteredGenerated = _generatedSalaries.where((r) {
                      // Parse record start and end dates from id
                      DateTime? recordStart;
                      DateTime? recordEnd;
                      final parts = r.id.split('_');
                      if (parts.length >= 3) {
                        try {
                          final startStr = parts[parts.length - 2];
                          final endStr = parts[parts.length - 1];
                          recordStart = DateTime(
                            int.parse(startStr.substring(0, 4)),
                            int.parse(startStr.substring(4, 6)),
                            int.parse(startStr.substring(6, 8)),
                          );
                          recordEnd = DateTime(
                            int.parse(endStr.substring(0, 4)),
                            int.parse(endStr.substring(4, 6)),
                            int.parse(endStr.substring(6, 8)),
                          );
                        } catch (_) {}
                      }

                      if (recordStart != null && recordEnd != null) {
                        // Show only if the record's END DATE falls within the selected filter range.
                        // This prevents a May–Jul record from appearing on a "July only" filter.
                        // Records generated for "This Month" are capped to today so end date is key.
                        if (recordEnd.isBefore(filterStart) ||
                            recordEnd.isAfter(filterEnd)) {
                          return false;
                        }
                      } else {
                        // Fallback to exact match if parsing fails
                        if (r.month != rangeLabel || r.year != _startDate.year)
                          return false;
                      }

                      // Make sure other salon's staff are not shown here
                      final belongsToSalon = staffList
                          .any((s) => s['id']?.toString() == r.staffId);
                      if (!belongsToSalon) return false;

                      if (isStaff) {
                        final myProfile = staffList.cast<dynamic>().firstWhere(
                              (s) =>
                                  s['user']?['id']?.toString() ==
                                      user?['id']?.toString() ||
                                  s['userId']?.toString() ==
                                      user?['id']?.toString(),
                              orElse: () => null,
                            );
                        if (myProfile == null) return false;
                        return r.staffId == myProfile['id']?.toString();
                      }
                      if (_filterSalaryType == 'ALL') return true;
                      return r.salaryType.toUpperCase() ==
                          _filterSalaryType.toUpperCase();
                    }).toList();

                    // Math totals
                    double totalBasic = 0.0;
                    double totalGenerated = 0.0;
                    double totalPaid = 0.0;
                    double totalLoan = 0.0;
                    double totalDeductions = 0.0;
                    double totalCommission = 0.0;
                    for (var r in filteredGenerated) {
                      totalBasic += r.basicSalary;
                      totalGenerated += r.salaryGenerated;
                      totalPaid += r.amountPaid;
                      totalLoan += r.loanRepayment;
                      totalDeductions += r.deductions;
                      totalCommission += r.commission;
                    }

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Filter Panel and Staff Checklist Side-by-Side (or stacked on mobile)
                        if (isStaff)
                          _buildLeftFilterPanel(salons, filteredStaffList,
                              attendanceList, salesList, isStaff)
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 900;
                              if (isWide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        flex: 3,
                                        child: _buildLeftFilterPanel(
                                            salons,
                                            filteredStaffList,
                                            attendanceList,
                                            salesList,
                                            isStaff)),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        flex: 5,
                                        child: _buildRightStaffList(
                                            filteredStaffList)),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    _buildLeftFilterPanel(
                                        salons,
                                        filteredStaffList,
                                        attendanceList,
                                        salesList,
                                        isStaff),
                                    const SizedBox(height: 16),
                                    _buildRightStaffList(filteredStaffList),
                                  ],
                                );
                              }
                            },
                          ),
                        const SizedBox(height: 24),
                        // Generated Salaries Table
                        _buildGeneratedSalariesTable(
                            filteredGenerated,
                            selectedSalonName,
                            currency,
                            totalBasic,
                            totalGenerated,
                            totalPaid,
                            totalLoan,
                            totalDeductions,
                            totalCommission,
                            isStaff),
                      ],
                    );
                  },
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: _kPrimary)),
                  error: (e, _) => Center(
                      child: Text('Error loading sales: $e',
                          style: GoogleFonts.outfit())),
                );
              },
              loading: () => const Center(
                  child: CircularProgressIndicator(color: _kPrimary)),
              error: (e, _) => Center(
                  child: Text('Error loading attendance: $e',
                      style: GoogleFonts.outfit())),
            ),
            loading: () => const Center(
                child: CircularProgressIndicator(color: _kPrimary)),
            error: (e, _) => Center(
                child: Text('Error loading staff: $e',
                    style: GoogleFonts.outfit())),
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _kPrimary)),
        error: (e, _) => Center(
            child:
                Text('Error loading salons: $e', style: GoogleFonts.outfit())),
      ),
    );
  }

  Widget _buildLeftFilterPanel(List<dynamic> salons, List<dynamic> staffList,
      List<dynamic> attendanceList, List<dynamic> salesList, bool isStaff) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isStaff ? 'Salary Period & Filters' : 'Generate Salary',
              style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold, fontSize: 16, color: _kDark)),
          const SizedBox(height: 16),
          Text('Campus *',
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedSalonId,
                isExpanded: true,
                items: [
                  for (var s in salons)
                    DropdownMenuItem(
                      value: s['id']?.toString(),
                      child: Text(s['name']?.toString() ?? 'Salon',
                          style: GoogleFonts.outfit(fontSize: 13)),
                    ),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedSalonId = val;
                    _selectedStaffIds.clear();
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Date Range Mode',
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDateMode,
                isExpanded: true,
                style: GoogleFonts.outfit(fontSize: 13, color: Colors.black87),
                icon: const Icon(LucideIcons.chevronDown, size: 16),
                items: const [
                  DropdownMenuItem(
                      value: 'CUSTOM', child: Text('Custom Date Range')),
                  DropdownMenuItem(value: 'TODAY', child: Text('Today')),
                  DropdownMenuItem(
                      value: 'YESTERDAY', child: Text('Yesterday')),
                  DropdownMenuItem(
                      value: 'THIS_MONTH', child: Text('This Month')),
                  DropdownMenuItem(
                      value: 'LAST_MONTH', child: Text('Last Month')),
                  DropdownMenuItem(
                      value: 'SINGLE_DAY', child: Text('Select Single Day...')),
                  DropdownMenuItem(
                      value: 'ENTIRE_MONTH',
                      child: Text('Select Entire Month...')),
                ],
                onChanged: (val) async {
                  if (val == null) return;
                  if (val == 'CUSTOM') {
                    // Trigger Custom date range selector
                    final picked = await showDateRangePicker(
                      context: context,
                      initialDateRange:
                          DateTimeRange(start: _startDate, end: _endDate),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF0F4C81),
                              onPrimary: Colors.white,
                              surface: Colors.white,
                              onSurface: Colors.black87,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDateMode = 'CUSTOM';
                        _startDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
                        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
                      });
                    }
                  } else if (val == 'TODAY') {
                    setState(() {
                      _selectedDateMode = val;
                      final now = DateTime.now();
                      _startDate = DateTime(now.year, now.month, now.day);
                      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
                    });
                  } else if (val == 'YESTERDAY') {
                    setState(() {
                      _selectedDateMode = val;
                      final yesterday =
                          DateTime.now().subtract(const Duration(days: 1));
                      _startDate = DateTime(
                          yesterday.year, yesterday.month, yesterday.day);
                      _endDate = DateTime(
                          yesterday.year, yesterday.month, yesterday.day, 23, 59, 59, 999);
                    });
                  } else if (val == 'THIS_MONTH') {
                    setState(() {
                      _selectedDateMode = val;
                      final now = DateTime.now();
                      _startDate = DateTime(now.year, now.month, 1);
                      _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
                    });
                  } else if (val == 'LAST_MONTH') {
                    setState(() {
                      _selectedDateMode = val;
                      final now = DateTime.now();
                      final prevMonth = DateTime(now.year, now.month - 1, 1);
                      _startDate = DateTime(prevMonth.year, prevMonth.month, 1);
                      _endDate =
                          DateTime(prevMonth.year, prevMonth.month + 1, 0, 23, 59, 59, 999);
                    });
                  } else if (val == 'SINGLE_DAY') {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDateMode = val;
                        _startDate =
                            DateTime(picked.year, picked.month, picked.day);
                        _endDate =
                            DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999);
                      });
                    }
                  } else if (val == 'ENTIRE_MONTH') {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDateMode = val;
                        _startDate = DateTime(picked.year, picked.month, 1);
                        _endDate = DateTime(picked.year, picked.month + 1, 0, 23, 59, 59, 999);
                      });
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Selected Range *',
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange:
                    DateTimeRange(start: _startDate, end: _endDate),
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: Color(0xFF0F4C81),
                        onPrimary: Colors.white,
                        surface: Colors.white,
                        onSurface: Colors.black87,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() {
                  _selectedDateMode = 'CUSTOM';
                  _startDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
                  _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black12),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.calendar,
                      size: 16, color: Colors.black54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${DateFormat('MMM dd, yyyy').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
                      style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: _kDark,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Icon(LucideIcons.chevronDown,
                      size: 16, color: Colors.black54),
                ],
              ),
            ),
          ),
          if (!isStaff) ...[
            const SizedBox(height: 12),
            Text('Salary Category Filter *',
                style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterSalaryType,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'ALL',
                        child: Text('All Categories',
                            style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 'MONTHLY',
                        child: Text('Fixed Salary (MONTHLY)',
                            style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 'DAILY',
                        child: Text('Daily Wage (DAILY)',
                            style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 'COMMISSION',
                        child: Text('Commission Only (COMMISSION)',
                            style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 'MONTHLY_PLUS_COMMISSION',
                        child: Text('Monthly + Commission',
                            style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 'DAILY_PLUS_COMMISSION',
                        child: Text('Daily + Commission',
                            style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _filterSalaryType = val;
                        _selectedStaffIds.clear();
                      });
                    }
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // Apply visual filter
                setState(() {});
              },
              icon:
                  const Icon(LucideIcons.filter, size: 14, color: Colors.white),
              label: const Text('Filter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F4C81),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (!isStaff) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _generateSalaryForSelected(
                    staffList, attendanceList, salesList),
                icon: const Icon(LucideIcons.plusCircle,
                    size: 14, color: Colors.white),
                label: const Text('Generate Salary'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F4C81),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRightStaffList(List<dynamic> rawStaffList) {
    final staffList = rawStaffList;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Staff Code | Name | Designation',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.redAccent)),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        for (var s in staffList) {
                          _selectedStaffIds.add(s['id']?.toString() ?? '');
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Select All',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedStaffIds.clear();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Select None',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          staffList.isEmpty
              ? Container(
                  height: 150,
                  alignment: Alignment.center,
                  child: Text('No staff profiles created yet.',
                      style: GoogleFonts.outfit(color: Colors.black38)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: staffList.length,
                  itemBuilder: (context, index) {
                    final staff = staffList[index];
                    final staffId = staff['id']?.toString() ?? '';
                    final name = staff['name'] ?? 'Staff';
                    final role = staff['role'] ?? 'Staff';

                    final isChecked = _selectedStaffIds.contains(staffId);

                    final lastPaid = _getLastPaidDate(staffId);
                    DateTime effectiveStartDate =
                        (lastPaid != null && lastPaid.isAfter(_startDate))
                            ? lastPaid.add(const Duration(days: 1))
                            : _startDate;
                    effectiveStartDate = DateTime(effectiveStartDate.year,
                        effectiveStartDate.month, effectiveStartDate.day);

                    final today = DateTime(DateTime.now().year,
                        DateTime.now().month, DateTime.now().day);
                    var effectiveEndDate =
                        DateTime(_endDate.year, _endDate.month, _endDate.day);
                    if (effectiveEndDate.isAfter(today)) {
                      effectiveEndDate = today;
                    }

                    // Check for any PAID record that overlaps the effective period → truly blocked
                    final isPaid = _generatedSalaries.any((r) {
                      if (r.staffId != staffId || r.status != 'Paid')
                        return false;
                      final parts = r.id.split('_');
                      if (parts.length >= 3) {
                        try {
                          final startStr = parts[parts.length - 2];
                          final endStr = parts[parts.length - 1];
                          final rStart = DateTime(
                              int.parse(startStr.substring(0, 4)),
                              int.parse(startStr.substring(4, 6)),
                              int.parse(startStr.substring(6, 8)));
                          final rEnd = DateTime(
                              int.parse(endStr.substring(0, 4)),
                              int.parse(endStr.substring(4, 6)),
                              int.parse(endStr.substring(6, 8)));
                          return !rEnd.isBefore(effectiveStartDate) &&
                              !rStart.isAfter(effectiveEndDate);
                        } catch (_) {}
                      }
                      return false;
                    });

                    // Check for any PENDING record that overlaps (informational only, not blocking)
                    final isPending = !isPaid &&
                        _generatedSalaries.any((r) {
                          if (r.staffId != staffId || r.status != 'Pending')
                            return false;
                          final parts = r.id.split('_');
                          if (parts.length >= 3) {
                            try {
                              final startStr = parts[parts.length - 2];
                              final endStr = parts[parts.length - 1];
                              final rStart = DateTime(
                                  int.parse(startStr.substring(0, 4)),
                                  int.parse(startStr.substring(4, 6)),
                                  int.parse(startStr.substring(6, 8)));
                              final rEnd = DateTime(
                                  int.parse(endStr.substring(0, 4)),
                                  int.parse(endStr.substring(4, 6)),
                                  int.parse(endStr.substring(6, 8)));
                              return !rEnd.isBefore(effectiveStartDate) &&
                                  !rStart.isAfter(effectiveEndDate);
                            } catch (_) {}
                          }
                          return false;
                        });

                    final isBlocked =
                        effectiveStartDate.isAfter(effectiveEndDate);

                    final double balanceVal =
                        double.tryParse(staff['balance']?.toString() ?? '0') ??
                            0.0;
                    final hasLoan = balanceVal > 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFFFEF9E7), // Soft yellow background
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isChecked,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedStaffIds.add(staffId);
                                } else {
                                  _selectedStaffIds.remove(staffId);
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  'EMP-${staffId.substring(0, 4).toUpperCase()} | ',
                                  style: GoogleFonts.outfit(
                                      fontSize: 12, color: Colors.black54),
                                ),
                                Text(
                                  '$name | ',
                                  style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade900),
                                ),
                                Text(
                                  role,
                                  style: GoogleFonts.outfit(
                                      fontSize: 12, color: Colors.black54),
                                ),
                                if (hasLoan) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('Loan: 500.00/Instalment',
                                        style: GoogleFonts.outfit(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade900)),
                                  ),
                                ]
                              ],
                            ),
                          ),
                          if (isBlocked)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Paid ✓',
                                  style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700)),
                            )
                          else if (isPending)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Pending',
                                  style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildGeneratedSalariesTable(
    List<GeneratedSalaryRecord> records,
    String campusName,
    String currency,
    double totalBasic,
    double totalGenerated,
    double totalPaid,
    double totalLoan,
    double totalDeductions,
    double totalCommission,
    bool isStaff,
  ) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Generated Salaries',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _kDark)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F4C81),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$campusName - ${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM').format(_endDate)}',
                    style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          if (!isWide) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Basic:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: Colors.black54)),
                      Text('$currency ${totalBasic.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _kPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Earned:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: Colors.black54)),
                      Text('$currency ${totalGenerated.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Commission:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: Colors.black54)),
                      Text('$currency ${totalCommission.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Deductions:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: Colors.black54)),
                      Text('$currency ${totalDeductions.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Loan Repaid:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: Colors.black54)),
                      Text('$currency ${totalLoan.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Net Paid:',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _kDark)),
                      Text('$currency ${totalPaid.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _kPrimary)),
                    ],
                  ),
                ],
              ),
            ),
            if (records.isEmpty)
              Container(
                height: 150,
                alignment: Alignment.center,
                child: Text('No generated salaries found for this period.',
                    style: GoogleFonts.outfit(color: Colors.black38)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: records.length,
                itemBuilder: (context, index) {
                  final r = records[index];
                  return _buildTableRecordCard(r, currency, isStaff);
                },
              ),
            const SizedBox(height: 16),
          ] else ...[
            Scrollbar(
              thumbVisibility: true,
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
              child: Container(
                width: isStaff ? 1277 : 1327,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Table Header Row
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(
                            bottom: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      child: Row(
                        children: [
                          _buildTableHeaderCell('Name', 160),
                          _buildTableHeaderCell('Period', 95),
                          _buildTableHeaderCell('Action', 140),
                          _buildTableHeaderCell('Basic', 100),
                          _buildTableHeaderCell('Earned', 110),
                          _buildTableHeaderCell('Commission', 100),
                          _buildTableHeaderCell('Deduct', 90),
                          _buildTableHeaderCell('Net Pay', 110),
                          _buildTableHeaderCell('Loan', 100),
                          _buildTableHeaderCell('Present', 55),
                          _buildTableHeaderCell('Absent', 55),
                          _buildTableHeaderCell('Leaves', 55),
                          _buildTableHeaderCell('Status', 75),
                          if (!isStaff) _buildTableHeaderCell('Del', 50),
                        ],
                      ),
                    ),
                    // Table Body Rows
                    if (records.isEmpty)
                      Container(
                        height: 150,
                        alignment: Alignment.center,
                        child: Text(
                            'No generated salaries found for this period.',
                            style: GoogleFonts.outfit(color: Colors.black38)),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final r = records[index];
                          return _buildTableRecordRow(r, currency, isStaff);
                        },
                      ),
                    // Summary Totals Row
                    if (records.isNotEmpty)
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          border:
                              Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
                        child: Row(
                          children: [
                            Container(
                                width: 160,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 12),
                                child: Text('Total:',
                                    style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: _kDark))),
                            Container(width: 95), // month
                            Container(width: 140), // action
                            // Basic Sum
                            Container(
                              width: 100,
                              child: Text(
                                  '$currency ${totalBasic.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: _kPrimary)),
                            ),
                            // Generated Sum
                            Container(
                              width: 110,
                              child: Text(
                                  '$currency ${totalGenerated.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.green.shade800)),
                            ),
                            // Commission Sum
                            Container(
                              width: 100,
                              child: Text(
                                  '$currency ${totalCommission.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.teal.shade800)),
                            ),
                            // Deductions Sum
                            Container(
                              width: 90,
                              child: Text(
                                  '$currency ${totalDeductions.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.red.shade800)),
                            ),
                            // Amount Paid Sum
                            Container(
                              width: 110,
                              child: Text(
                                  '$currency ${totalPaid.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: _kPrimary)),
                            ),
                            // Loan Sum
                            Container(
                              width: 100,
                              child: Text(
                                  '$currency ${totalLoan.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.orange.shade900)),
                            ),
                            Container(width: 55),
                            Container(width: 55),
                            Container(width: 55),
                            Container(width: 75),
                            if (!isStaff) Container(width: 50),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildTableRecordCard(
      GeneratedSalaryRecord r, String currency, bool isStaff) {
    final statusColor = r.status == 'Paid' ? Colors.green : Colors.amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
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
                    Text(r.name,
                        style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _kDark)),
                    const SizedBox(height: 2),
                    Text(r.role,
                        style: GoogleFonts.outfit(
                            fontSize: 11, color: Colors.black45)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      r.status,
                      style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor.shade900),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${r.month} ${r.year}',
                    style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: Colors.black38,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCardMetric('Basic Salary',
                  '$currency ${r.basicSalary.toStringAsFixed(2)}',
                  sub: r.salaryType.toLowerCase()),
              _buildCardMetric(
                'Earned Salary',
                '$currency ${r.salaryGenerated.toStringAsFixed(2)}',
                color: Colors.green.shade700,
                onTap: () {
                  final staffList = _selectedSalonId != null
                      ? (ref
                              .read(staffForSalonProvider(_selectedSalonId!))
                              .value ??
                          [])
                      : (ref.read(staffProvider).value ?? []);
                  _showCalculationBreakdownDialog(r, staffList);
                },
              ),
              _buildCardMetric(
                  'Commission', '$currency ${r.commission.toStringAsFixed(2)}',
                  color: Colors.teal.shade700),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCardMetric(
                  'Deductions', '$currency ${r.deductions.toStringAsFixed(2)}',
                  color: Colors.red.shade700),
              _buildCardMetric('Loan Repay',
                  '$currency ${r.loanRepayment.toStringAsFixed(2)}',
                  color: Colors.orange.shade900),
              _buildCardMetric(
                'Net Paid',
                '$currency ${r.amountPaid.toStringAsFixed(2)}',
                color: _kPrimary,
                isBold: true,
                onTap: () {
                  final staffList = _selectedSalonId != null
                      ? (ref
                              .read(staffForSalonProvider(_selectedSalonId!))
                              .value ??
                          [])
                      : (ref.read(staffProvider).value ?? []);
                  _showCalculationBreakdownDialog(r, staffList);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Attendance: ',
                  style:
                      GoogleFonts.outfit(fontSize: 11, color: Colors.black45)),
              const SizedBox(width: 4),
              _buildCardBadge('P: ${r.present}', Colors.green),
              const SizedBox(width: 6),
              _buildCardBadge('A: ${r.absent}', Colors.red),
              const SizedBox(width: 6),
              _buildCardBadge('L: ${r.leaves}', Colors.blue),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (!isStaff)
                IconButton(
                  icon: const Icon(LucideIcons.trash2,
                      size: 18, color: Colors.redAccent),
                  onPressed: () => _deleteSalaryRecord(r.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                const SizedBox.shrink(),
              r.status == 'Paid'
                  ? ElevatedButton.icon(
                      onPressed: () => _showPrintSlipDialog(r),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(LucideIcons.printer, size: 14),
                      label: const Text('Print Slip',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  : (isStaff
                      ? Text(
                          'Pending Payout',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black45),
                        )
                      : ElevatedButton.icon(
                          onPressed: () => _showMakePaymentDialog(r),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(LucideIcons.banknote, size: 14),
                          label: const Text('Pay Now',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                        )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardMetric(String label, String value,
      {Color? color, bool isBold = false, String? sub, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style:
                      GoogleFonts.outfit(fontSize: 10, color: Colors.black38)),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                const Icon(LucideIcons.info, size: 8, color: Colors.black38),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: color ?? _kDark,
                ),
              ),
              if (sub != null) ...[
                const SizedBox(width: 2),
                Text(
                  sub,
                  style: GoogleFonts.outfit(fontSize: 8, color: Colors.black38),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: color.withValues(alpha: 0.9)),
      ),
    );
  }

  Widget _buildTableHeaderCell(String label, double width) {
    return Container(
      width: width,
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _kDark,
        ),
      ),
    );
  }

  Widget _buildTableRecordRow(
      GeneratedSalaryRecord r, String currency, bool isStaff) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          // Name and role
          Container(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name,
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kDark),
                    overflow: TextOverflow.ellipsis),
                Text(r.role,
                    style: GoogleFonts.outfit(
                        fontSize: 10, color: Colors.black38)),
              ],
            ),
          ),
          // Month badge
          Container(
            width: 95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${r.month} ${r.year}',
                  style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyan.shade900)),
            ),
          ),
          // Action button — column 3, always visible on screen
          Container(
            width: 140,
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: r.status == 'Paid'
                ? ElevatedButton.icon(
                    onPressed: () => _showPrintSlipDialog(r),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(LucideIcons.printer, size: 11),
                    label: const Text('Print Slip',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                : (isStaff
                    ? Center(
                        child: Text(
                          'Pending Payout',
                          style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black45),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () => _showMakePaymentDialog(r),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(LucideIcons.banknote, size: 11),
                        label: const Text('Pay Now',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold)),
                      )),
          ),
          // Basic Salary
          Container(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.basicSalary.toStringAsFixed(2),
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                Text(r.salaryType.toLowerCase(),
                    style:
                        GoogleFonts.outfit(fontSize: 9, color: Colors.black38)),
              ],
            ),
          ),
          // Salary Earned
          Container(
            width: 110,
            child: InkWell(
              onTap: () {
                final staffList = _selectedSalonId != null
                    ? (ref
                            .read(staffForSalonProvider(_selectedSalonId!))
                            .value ??
                        [])
                    : (ref.read(staffProvider).value ?? []);
                _showCalculationBreakdownDialog(r, staffList);
              },
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.salaryGenerated.toStringAsFixed(2),
                      style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700)),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.info, size: 10, color: Colors.black38),
                ],
              ),
            ),
          ),
          // Commission
          Container(
            width: 100,
            child: Text(r.commission.toStringAsFixed(2),
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade700)),
          ),
          // Deduct
          Container(
            width: 90,
            child: Text(r.deductions.toStringAsFixed(2),
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700)),
          ),
          // Net Amount Paid
          Container(
            width: 110,
            child: Text(r.amountPaid.toStringAsFixed(2),
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _kPrimary)),
          ),
          // Loan Repay
          Container(
            width: 100,
            child: Text(r.loanRepayment.toStringAsFixed(2),
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900)),
          ),
          // Present
          _buildBadgeCell(r.present.toString(), Colors.green, 55),
          // Absent
          _buildBadgeCell(r.absent.toString(), Colors.red, 55),
          // Leaves
          _buildBadgeCell(r.leaves.toString(), Colors.blue, 55),
          // Status
          Container(
            width: 75,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: r.status == 'Paid'
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(r.status,
                  style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: r.status == 'Paid'
                          ? Colors.green.shade800
                          : Colors.amber.shade900)),
            ),
          ),
          // Delete
          if (!isStaff)
            Container(
              width: 50,
              child: IconButton(
                icon: const Icon(LucideIcons.trash2,
                    size: 15, color: Colors.redAccent),
                onPressed: () => _deleteSalaryRecord(r.id),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBadgeCell(String val, Color color, double width) {
    return Container(
      width: width,
      alignment: Alignment.centerLeft,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Text(
          val,
          style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color.withValues(alpha: 0.9)),
        ),
      ),
    );
  }
}
