import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../providers/staff_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/salons_provider.dart';
import '../providers/reports_provider.dart';

const _kPrimary  = Color(0xFF0F4C81); // Premium Navy
const _kDark     = Color(0xFF1B1B3A); // Deep Slate
const _kBg       = Color(0xFFF4F6FB); // Soft Blue-Grey
const _kGreen    = Color(0xFF2ECD71);
const _kRed      = Color(0xFFE74C3C);
const _kOrange   = Color(0xFFF39C12);
const _kBlue     = Color(0xFF3498DB);

class TempAttendanceRecord {
  String status;
  TimeOfDay? checkInTime;
  TimeOfDay? checkOutTime;
  String lateMode;
  String earlyMode;
  bool isModified;

  TempAttendanceRecord({
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.lateMode = 'Auto',
    this.earlyMode = 'Auto',
    this.isModified = false,
  });
}

class AttendanceView extends ConsumerStatefulWidget {
  const AttendanceView({super.key});

  @override
  ConsumerState<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends ConsumerState<AttendanceView> {
  String? _selectedStaffId;
  String? _selectedSalonId;
  String _selectedStaffCategory = 'All';
  String _selectedType = 'Normal Attendance';
  String _selectedSalaryType = 'ALL';
  DateTime _selectedRegisterDate = DateTime.now();
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _notifyLateAbsent = 'No';

  String? _loadedKey;
  final Map<String, TempAttendanceRecord> _tempRecords = {};
  bool _isLocked = false;
  bool _isLoadingLock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLockStatus();
    });
  }

  Future<void> _checkLockStatus() async {
    if (mounted) setState(() => _isLoadingLock = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedRegisterDate);
      final api = ref.read(apiServiceProvider);
      final res = await api.getAttendanceLockStatus(dateStr);
      if (mounted) {
        setState(() {
          _isLocked = res['locked'] == true;
          _isLoadingLock = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLock = false);
    }
  }

  void _refresh() {
    ref.invalidate(attendanceProvider);
    if (_selectedSalonId != null) {
      ref.invalidate(attendanceForSalonProvider(_selectedSalonId!));
      ref.invalidate(staffForSalonProvider(_selectedSalonId!));
    }
    _checkLockStatus();
  }

  void _changeMonth(int increment) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + increment, 1);
    });
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'PRESENT': return Colors.green;
      case 'ABSENT': return Colors.red;
      case 'LEAVE': return Colors.blue;
      case 'LATE': return Colors.orange;
      case 'SUNDAY': return Colors.teal;
      case 'HOLIDAY': return Colors.amber;
      default: return Colors.transparent;
    }
  }



  TimeOfDay _parseTimeLimit(String? limitStr, TimeOfDay defaultTime) {
    if (limitStr == null || !limitStr.contains(':')) return defaultTime;
    final parts = limitStr.split(':');
    final hour = int.tryParse(parts[0]) ?? defaultTime.hour;
    final minute = int.tryParse(parts[1]) ?? defaultTime.minute;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<bool> _saveAttendance() async {
    if (_isLocked) return false;

    // Check if any present/late records have missing times
    final staffAsync = _selectedSalonId != null
        ? ref.read(staffForSalonProvider(_selectedSalonId!))
        : ref.read(staffProvider);
    final staffList = staffAsync.value ?? [];

    String? invalidStaffName;
    _tempRecords.forEach((staffId, record) {
      final isPresentOrLate = record.status == 'PRESENT' || record.status == 'LATE';
      if (isPresentOrLate && record.checkInTime == null) {
        final staffObj = staffList.firstWhere(
          (s) => s['id']?.toString() == staffId,
          orElse: () => null,
        );
        invalidStaffName = staffObj?['name']?.toString() ?? 'Staff';
      }
    });

    if (invalidStaffName != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Please set Check In time for $invalidStaffName.',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: _kPrimary)),
    );

    try {
      await _saveAttendanceLocal();

      Navigator.pop(context); // Dismiss loading spinner
      _refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _kGreen,
            content: Text(
              'Attendance saved successfully.',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      Navigator.pop(context); // Dismiss loading spinner
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _kRed,
            content: Text('Error saving attendance: $e', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _saveAttendanceLocal() async {
    final api = ref.read(apiServiceProvider);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedRegisterDate);

    final saveFutures = <Future<void>>[];
    _tempRecords.forEach((staffId, record) {
      if (record.status == 'NONE') return;

      final isTimeAllowed = record.status != 'ABSENT' && record.status != 'LEAVE';
      final checkInStr = (isTimeAllowed && record.checkInTime != null)
          ? DateTime(_selectedRegisterDate.year, _selectedRegisterDate.month, _selectedRegisterDate.day, record.checkInTime!.hour, record.checkInTime!.minute).toUtc().toIso8601String()
          : null;
      final checkOutStr = (isTimeAllowed && record.checkOutTime != null)
          ? DateTime(_selectedRegisterDate.year, _selectedRegisterDate.month, _selectedRegisterDate.day, record.checkOutTime!.hour, record.checkOutTime!.minute).toUtc().toIso8601String()
          : null;

      saveFutures.add(
        api.markAttendance({
          'staffId': staffId,
          'status': record.status,
          'date': dateStr,
          'checkIn': checkInStr,
          'checkOut': checkOutStr,
        })
      );
    });

    await Future.wait(saveFutures);
  }

  Future<void> _confirmAndLockDay() async {
    final staffAsync = _selectedSalonId != null
        ? ref.read(staffForSalonProvider(_selectedSalonId!))
        : ref.read(staffProvider);
    final staffList = staffAsync.value ?? [];

    // Check if any PRESENT or LATE staff records are missing check-in or check-out times
    String? incompleteStaffMessage;
    _tempRecords.forEach((staffId, record) {
      final isPresentOrLate = record.status == 'PRESENT' || record.status == 'LATE';
      if (isPresentOrLate && (record.checkInTime == null || record.checkOutTime == null)) {
        final staffObj = staffList.firstWhere(
          (s) => s['id']?.toString() == staffId,
          orElse: () => null,
        );
        final staffName = staffObj?['name']?.toString() ?? 'Staff Member';
        final missingType = (record.checkInTime == null && record.checkOutTime == null)
            ? 'Check-In and Check-Out'
            : (record.checkInTime == null ? 'Check-In' : 'Check-Out');
        incompleteStaffMessage = '$staffName is marked ${record.status} but missing $missingType time.';
      }
    });

    if (incompleteStaffMessage != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Cannot Lock: $incompleteStaffMessage',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Lock Day\'s Attendance?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to lock the attendance for ${DateFormat('MMMM dd, yyyy').format(_selectedRegisterDate)}? Once confirmed and locked, attendance records for this date CANNOT be changed or updated.', style: GoogleFonts.outfit()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Lock Attendance', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
      try {
        final api = ref.read(apiServiceProvider);
        final dateStr = DateFormat('yyyy-MM-dd').format(_selectedRegisterDate);
        
        // Save first
        await _saveAttendanceLocal();
        
        await api.lockAttendance(dateStr);
        Navigator.pop(context); // Dismiss spinner
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: _kGreen,
              content: Text('Attendance successfully confirmed and locked for this date.', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          );
        }
      } catch (e) {
        Navigator.pop(context); // Dismiss spinner
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: _kRed,
              content: Text('Error locking attendance: $e', style: GoogleFonts.outfit(color: Colors.white)),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isOwner = user?['role'] == 'OWNER' || user?['role'] == 'SUPER_ADMIN';
    final salonsAsync = ref.watch(salonsProvider);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isOwner ? 'Register & Review' : 'My Calendar', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w500)),
            Text('Attendance Portal', style: GoogleFonts.outfit(color: _kDark, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(LucideIcons.refreshCw, size: 20, color: Colors.black26)),
        ],
      ),
      body: salonsAsync.when(
        data: (salons) {
          if (isOwner && _selectedSalonId == null && salons.isNotEmpty) {
            final userSalonId = user?['salonId']?.toString() ?? user?['salon']?['id']?.toString();
            _selectedSalonId = salons.any((s) => s['id']?.toString() == userSalonId)
                ? userSalonId
                : salons.first['id']?.toString();
          }

          final staffAsync = _selectedSalonId != null
              ? ref.watch(staffForSalonProvider(_selectedSalonId!))
              : ref.watch(staffProvider);

          final attAsync = _selectedSalonId != null
              ? ref.watch(attendanceForSalonProvider(_selectedSalonId!))
              : ref.watch(attendanceProvider);

          return staffAsync.when(
            data: (staffList) => attAsync.when(
              data: (attendanceRecords) {
                if (isOwner) {
                  if (_selectedStaffId != null) {
                    final filteredData = attendanceRecords.where((r) => r['staffId'] == _selectedStaffId).toList();
                    return Column(
                      children: [
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(LucideIcons.arrowLeft, size: 18),
                                onPressed: () => setState(() => _selectedStaffId = null),
                              ),
                              Text('Back to Register', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _kPrimary)),
                            ],
                          ),
                        ),
                        _buildMonthHeader(),
                        Expanded(child: _buildCalendarGrid(filteredData, true)),
                      ],
                    );
                  }

                  // Setup temporary local register state
                  final dateStr = DateFormat('yyyy-MM-dd').format(_selectedRegisterDate);
                  final currentKey = '${_selectedSalonId}_$dateStr';
                  
                  if (_loadedKey != currentKey) {
                    _tempRecords.clear();
                    _loadedKey = currentKey;
                    
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _checkLockStatus();
                    });
                    
                    for (var s in staffList) {
                      final staffId = s['id']?.toString() ?? '';
                      dynamic existing;
                      for (var r in attendanceRecords) {
                        if (r['staffId']?.toString() == staffId && r['date']?.toString() == dateStr) {
                          existing = r;
                          break;
                        }
                      }
                      
                      final defaultStatus = existing?['status']?.toString().toUpperCase() ?? 'NONE';
                      final isPresentOrLate = defaultStatus == 'PRESENT' || defaultStatus == 'LATE';

                      _tempRecords[staffId] = TempAttendanceRecord(
                        status: defaultStatus,
                        checkInTime: existing?['checkIn'] != null 
                            ? TimeOfDay.fromDateTime(DateTime.parse(existing['checkIn']).toLocal()) 
                            : null,
                        checkOutTime: existing?['checkOut'] != null 
                            ? TimeOfDay.fromDateTime(DateTime.parse(existing['checkOut']).toLocal()) 
                            : null,
                        lateMode: 'Auto',
                        earlyMode: 'Auto',
                      );
                    }
                  }

                  // Filter staff list based on category dropdown selection and salary type category
                  final filteredStaff = staffList.where((s) {
                    if (_selectedStaffCategory != 'All' && s['role']?.toString() != _selectedStaffCategory) {
                      return false;
                    }
                    if (_selectedSalaryType != 'ALL') {
                      if (s['salaryType']?.toString().toUpperCase() != _selectedSalaryType.toUpperCase()) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();

                  dynamic selectedSalonObj;
                  for (var s in salons) {
                    if (s['id']?.toString() == _selectedSalonId) {
                      selectedSalonObj = s;
                      break;
                    }
                  }
                  final selectedSalonName = selectedSalonObj?['name'] ?? 'My Salon';
                  final lateTimeLimit = selectedSalonObj?['lateTimeLimit']?.toString() ?? '09:00';
                  final earlyExitTimeLimit = selectedSalonObj?['earlyExitTimeLimit']?.toString() ?? '17:45';

                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildFilterToolbar(salons, staffList),
                            _buildCampusBadge(selectedSalonName),
                            if (_isLocked) _buildLockedBanner(),
                            _buildActionButtonsToolbar(filteredStaff),
                            const SizedBox(height: 8),
                            _buildTable(filteredStaff, lateTimeLimit, earlyExitTimeLimit),
                          ],
                        ),
                      ),
                      _buildFooter(),
                    ],
                  );
                } else {
                  // Staff view - calendar only
                  final filteredData = attendanceRecords.where((r) => r['staff']?['userId'] == user?['id']).toList();
                  return Column(
                    children: [
                      _buildMonthHeader(),
                      Expanded(child: _buildCalendarGrid(filteredData, false)),
                    ],
                  );
                }
              },
              loading: () => const Center(child: CircularProgressIndicator(color: _kPrimary)),
              error: (e, _) => Center(child: Text('Error: $e', style: GoogleFonts.outfit())),
            ),
            loading: () => const Center(child: CircularProgressIndicator(color: _kPrimary)),
            error: (e, _) => Center(child: Text('Error loading staff: $e', style: GoogleFonts.outfit())),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: _kPrimary)),
        error: (e, _) => Center(child: Text('Error loading salons: $e', style: GoogleFonts.outfit())),
      ),
    );
  }

  Widget _buildFilterToolbar(List<dynamic> salons, List<dynamic> staffList) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final roles = {'All', ...staffList.map((s) => s['role']?.toString() ?? 'Staff').where((r) => r.isNotEmpty)};

    final campusDropdown = _buildDropdownField<String?>(
      value: _selectedSalonId,
      items: [
        for (var s in salons)
          DropdownMenuItem(
            value: s['id']?.toString(),
            child: Text(s['name']?.toString() ?? 'Salon', style: GoogleFonts.outfit(fontSize: 13)),
          ),
      ],
      onChanged: (val) async {
        if (val == null) return;
        final hasUnsaved = _tempRecords.values.any((r) => r.isModified == true);
        bool shouldProceed = true;
        if (hasUnsaved) {
          final result = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Unsaved Changes', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: const Text('You have unsaved attendance changes. Do you want to save them before changing salon?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text('Discard', style: const TextStyle(color: Colors.redAccent))),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
          if (result == 'save') {
            await _saveAttendance();
          } else if (result == 'cancel') {
            shouldProceed = false;
          }
        }
        if (shouldProceed) {
          setState(() {
            _selectedSalonId = val;
          });
        }
      },
    );

    final categoryDropdown = _buildDropdownField<String>(
      value: _selectedStaffCategory,
      items: [
        for (var r in roles)
          DropdownMenuItem(
            value: r,
            child: Text(r, style: GoogleFonts.outfit(fontSize: 13)),
          ),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedStaffCategory = val;
          });
        }
      },
    );

    final typeDropdown = _buildDropdownField<String>(
      value: _selectedType,
      items: [
        DropdownMenuItem(value: 'Normal Attendance', child: Text('Normal Attendance', style: GoogleFonts.outfit(fontSize: 13))),
        DropdownMenuItem(value: 'Overtime', child: Text('Overtime', style: GoogleFonts.outfit(fontSize: 13))),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedType = val;
          });
        }
      },
    );

    final salaryTypeDropdown = _buildDropdownField<String>(
      value: _selectedSalaryType,
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('All Wage Types', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'MONTHLY', child: Text('Fixed Salary (MONTHLY)', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'DAILY', child: Text('Daily Wage (DAILY)', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'COMMISSION', child: Text('Commission Only (COMMISSION)', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'MONTHLY_PLUS_COMMISSION', child: Text('Monthly + Commission', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'DAILY_PLUS_COMMISSION', child: Text('Daily + Commission', style: TextStyle(fontSize: 13))),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedSalaryType = val;
          });
        }
      },
    );

    final dateField = InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedRegisterDate.isAfter(now) ? now : _selectedRegisterDate,
          firstDate: DateTime(2020),
          lastDate: now,
        );
        if (picked != null) {
          final hasUnsaved = _tempRecords.values.any((r) => r.isModified == true);
          bool shouldProceed = true;
          if (hasUnsaved) {
            final result = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text('Unsaved Changes', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                content: const Text('You have unsaved attendance changes. Do you want to save them before changing the date?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text('Discard', style: const TextStyle(color: Colors.redAccent))),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, 'save'),
                    style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('Save', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            if (result == 'save') {
              await _saveAttendance();
            } else if (result == 'cancel') {
              shouldProceed = false;
            }
          }
          if (shouldProceed) {
            setState(() {
              _selectedRegisterDate = picked;
            });
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat('MM/dd/yyyy').format(_selectedRegisterDate),
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: _kDark),
            ),
            const Icon(LucideIcons.calendar, size: 16, color: Colors.black54),
          ],
        ),
      ),
    );

    final filterButton = ElevatedButton.icon(
      onPressed: _refresh,
      icon: const Icon(LucideIcons.filter, size: 14, color: Colors.white),
      label: Text('Filter', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    if (isWide) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Campus', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), campusDropdown])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Salary Type', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), salaryTypeDropdown])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Staff Category', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), categoryDropdown])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Type', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), typeDropdown])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Date', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), dateField])),
            const SizedBox(width: 16),
            filterButton,
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Campus', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), campusDropdown])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Salary Type', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), salaryTypeDropdown])),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Staff Category', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), categoryDropdown])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Type', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), typeDropdown])),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Date', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kDark)), const SizedBox(height: 6), dateField])),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: filterButton),
          ],
        ),
      );
    }
  }

  Widget _buildDropdownField<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(LucideIcons.chevronDown, size: 16, color: Colors.black38),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildLockedBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.lock, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance Locked',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red.shade900, fontSize: 14),
                ),
                Text(
                  'Attendance for this day has been finalized and cannot be modified.',
                  style: GoogleFonts.outfit(color: Colors.red.shade700, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampusBadge(String campusName) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F4C81),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Campus: $campusName',
          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildActionButtonsToolbar(List<dynamic> filteredStaff) {
    if (_isLocked) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildActionButton('Mark All Present', LucideIcons.checkCircle, Colors.green, () {
            setState(() {
              for (var s in filteredStaff) {
                final staffId = s['id']?.toString() ?? '';
                if (_tempRecords.containsKey(staffId)) {
                  _tempRecords[staffId]!.status = 'PRESENT';
                  _tempRecords[staffId]!.isModified = true;
                }
              }
            });
          }),
          _buildActionButton('Mark All Absent', LucideIcons.xCircle, Colors.red, () {
            setState(() {
              for (var s in filteredStaff) {
                final staffId = s['id']?.toString() ?? '';
                if (_tempRecords.containsKey(staffId)) {
                  _tempRecords[staffId]!.status = 'ABSENT';
                  _tempRecords[staffId]!.isModified = true;
                }
              }
            });
          }),
          _buildActionButton('Mark All Holiday', LucideIcons.calendar, Colors.amber, () {
            setState(() {
              for (var s in filteredStaff) {
                final staffId = s['id']?.toString() ?? '';
                if (_tempRecords.containsKey(staffId)) {
                  _tempRecords[staffId]!.status = 'HOLIDAY';
                  _tempRecords[staffId]!.isModified = true;
                }
              }
            });
          }),
          _buildActionButton('Mark All Sunday', LucideIcons.calendarCheck, Colors.teal, () {
            setState(() {
              for (var s in filteredStaff) {
                final staffId = s['id']?.toString() ?? '';
                if (_tempRecords.containsKey(staffId)) {
                  _tempRecords[staffId]!.status = 'SUNDAY';
                  _tempRecords[staffId]!.isModified = true;
                }
              }
            });
          }),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<dynamic> filteredStaff, String lateTimeLimit, String earlyExitTimeLimit) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          width: 952,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Row(
                  children: [
                    _buildHeaderCell('Emp. ID', 90),
                    _buildHeaderCell('Name', 150),
                    _buildHeaderCell('Designation', 110),
                    _buildHeaderCell('Attendance Status', 130),
                    _buildHeaderCell('Arrival Timing', 120),
                    _buildHeaderCell('Exit Timing', 120),
                    _buildHeaderCell('Late Arrival', 100),
                    _buildHeaderCell('Early Exit', 100),
                  ],
                ),
              ),
              // Data Rows
              if (filteredStaff.isEmpty)
                Container(
                  height: 200,
                  alignment: Alignment.center,
                  child: Text('No staff found matching filters.', style: GoogleFonts.outfit(color: Colors.black38)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredStaff.length,
                  itemBuilder: (context, index) {
                    final staff = filteredStaff[index];
                    final staffId = staff['id']?.toString() ?? '';
                    final record = _tempRecords[staffId] ?? TempAttendanceRecord(status: 'NONE');
                    
                    return AttendanceRowWidget(
                      key: ValueKey('${staffId}_${record.status}_${record.checkInTime}_${record.checkOutTime}'),
                      staff: staff,
                      record: record,
                      lateTimeLimit: lateTimeLimit,
                      earlyExitTimeLimit: earlyExitTimeLimit,
                      isLocked: _isLocked,
                      onNameClicked: () {
                        setState(() {
                          _selectedStaffId = staffId;
                        });
                      },
                      onRecordChanged: () {
                        setState(() {
                          record.isModified = true;
                        });
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String label, double width) {
    return Container(
      width: width,
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: _kDark,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.bellRing, size: 16, color: _kPrimary),
              const SizedBox(width: 8),
              Text(
                'Notify Late & Absent Staff:',
                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: _kDark),
              ),
              const SizedBox(width: 8),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: _kBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _notifyLateAbsent,
                    items: const [
                      DropdownMenuItem(value: 'No', child: Text('No')),
                      DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _notifyLateAbsent = val;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (!_isLocked) ...[
                ElevatedButton.icon(
                  onPressed: _confirmAndLockDay,
                  icon: const Icon(LucideIcons.lock, size: 16, color: Colors.white),
                  label: Text('Confirm & Lock Day', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: _isLocked ? null : _saveAttendance,
                icon: const Icon(LucideIcons.save, size: 16, color: Colors.white),
                label: Text('Save Attendance', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLocked ? Colors.grey : const Color(0xFF27AE60),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(LucideIcons.chevronLeft), onPressed: () => _changeMonth(-1)),
          Text(DateFormat('MMMM yyyy').format(_currentMonth), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          IconButton(icon: const Icon(LucideIcons.chevronRight), onPressed: () => _changeMonth(1)),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(List attendanceRecords, bool isOwner) {
    final Map<String, String> statusMap = {};
    for (var r in attendanceRecords) {
      if (r['date'] != null) {
        statusMap.putIfAbsent(r['date'], () => r['status']);
      }
    }

    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final emptyPrefix = firstWeekday - 1;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) =>
              SizedBox(width: 30, child: Center(child: Text(d, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.black38, fontSize: 12))))).toList(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: emptyPrefix + daysInMonth,
              itemBuilder: (context, index) {
                if (index < emptyPrefix) return const SizedBox();
                final day = index - emptyPrefix + 1;
                final dateStr = DateFormat('yyyy-MM-dd').format(DateTime(_currentMonth.year, _currentMonth.month, day));
                final status = statusMap[dateStr];

                final isToday = dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

                return InkWell(
                  onTap: () {
                    if (isOwner && _selectedStaffId != null) {
                      _showMarkDialog(DateTime(_currentMonth.year, _currentMonth.month, day), status);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: status != null ? _getStatusColor(status).withValues(alpha: 0.15) : (isToday ? _kPrimary.withValues(alpha: 0.05) : Colors.transparent),
                      borderRadius: BorderRadius.circular(8),
                      border: isToday ? Border.all(color: _kPrimary, width: 1.5) : null,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$day', style: GoogleFonts.outfit(
                            fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                            color: status != null ? _getStatusColor(status) : _kDark
                          )),
                          if (status != null)
                            Text(status[0], style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: _getStatusColor(status))),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegend('P', Colors.green, 'Present'),
              _buildLegend('A', Colors.red, 'Absent'),
              _buildLegend('L', Colors.blue, 'Leave'),
              _buildLegend('T', Colors.orange, 'Late'),
              _buildLegend('S', Colors.teal, 'Sunday'),
              _buildLegend('H', Colors.amber, 'Holiday'),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLegend(String letter, Color color, String label) {
    return Row(
      children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
          child: Center(child: Text(letter, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: color))),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.outfit(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  void _showMarkDialog(DateTime date, String? currentStatus) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Mark Attendance', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: _kDark)),
                Text(DateFormat('EEEE, MMM dd, yyyy').format(date), style: GoogleFonts.outfit(color: Colors.black54)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMarkButton('PRESENT', Colors.green, currentStatus, date),
                    _buildMarkButton('ABSENT', Colors.red, currentStatus, date),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMarkButton('LEAVE', Colors.blue, currentStatus, date),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildMarkButton(String status, Color color, String? currentStatus, DateTime date) {
    final isSelected = status == currentStatus;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await ref.read(apiServiceProvider).markAttendance({
                'staffId': _selectedStaffId,
                'status': status,
                'date': DateFormat('yyyy-MM-dd').format(date),
              });
              _refresh();
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? color : color.withValues(alpha: 0.1),
            foregroundColor: isSelected ? Colors.white : color,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(status, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class AttendanceRowWidget extends StatefulWidget {
  final dynamic staff;
  final TempAttendanceRecord record;
  final String lateTimeLimit;
  final String earlyExitTimeLimit;
  final bool isLocked;
  final VoidCallback onNameClicked;
  final VoidCallback onRecordChanged;

  const AttendanceRowWidget({
    super.key,
    required this.staff,
    required this.record,
    required this.lateTimeLimit,
    required this.earlyExitTimeLimit,
    required this.isLocked,
    required this.onNameClicked,
    required this.onRecordChanged,
  });

  @override
  State<AttendanceRowWidget> createState() => _AttendanceRowWidgetState();
}

class _AttendanceRowWidgetState extends State<AttendanceRowWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant AttendanceRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staffId = widget.staff['id']?.toString() ?? '';
    final name = widget.staff['name'] ?? 'Staff';
    final salaryTypeRaw = widget.staff['salaryType']?.toString() ?? '';
    final role = widget.staff['role'] ?? 'Staff';
    
    String salaryTypeLabel = 'full time';
    if (salaryTypeRaw == 'DAILY' || salaryTypeRaw == 'COMMISSION') {
      salaryTypeLabel = 'per hour';
    }

    final isInactive = widget.record.status == 'ABSENT' || widget.record.status == 'LEAVE' || widget.record.status == 'NONE';

    final resolvedLateLimit = widget.staff['lateTimeLimit']?.toString() ?? widget.lateTimeLimit;
    final resolvedEarlyExitLimit = widget.staff['earlyExitTimeLimit']?.toString() ?? widget.earlyExitTimeLimit;

    String lateDuration = '-';
    if (!isInactive && widget.record.checkInTime != null) {
      lateDuration = _calculateLateDuration(widget.record.checkInTime!, resolvedLateLimit);
    }

    String earlyDuration = '-';
    if (!isInactive && widget.record.checkOutTime != null) {
      earlyDuration = _calculateEarlyExitDuration(widget.record.checkOutTime!, resolvedEarlyExitLimit);
    }

    String totalHours = '';
    if (!isInactive && widget.record.checkInTime != null && widget.record.checkOutTime != null) {
      totalHours = _calculateTotalHours(widget.record.checkInTime!, widget.record.checkOutTime!);
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          // Emp ID
          Container(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'EMP-${staffId.length >= 4 ? staffId.substring(0, 4).toUpperCase() : staffId}',
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
                ),
                if (widget.staff['biometricPin'] != null && widget.staff['biometricPin'].toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.fingerprint, size: 10, color: Colors.purple),
                      const SizedBox(width: 3),
                      Text(
                        'PIN #${widget.staff['biometricPin']}',
                        style: GoogleFonts.outfit(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Name and Type
          Container(
            width: 150,
            child: InkWell(
              onTap: widget.isLocked ? null : widget.onNameClicked,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name, 
                    style: GoogleFonts.outfit(
                      fontSize: 13, 
                      fontWeight: FontWeight.bold, 
                      color: _kPrimary,
                      decoration: TextDecoration.underline,
                    )
                  ),
                  const SizedBox(height: 2),
                  Text(salaryTypeLabel, style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
                ],
              ),
            ),
          ),

          // Designation
          Container(
            width: 110,
            child: Text(
              role,
              style: GoogleFonts.outfit(fontSize: 12, color: Colors.black87),
            ),
          ),
          // Attendance Status
          Container(
            width: 130,
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: widget.record.status,
                  isExpanded: true,
                  style: GoogleFonts.outfit(fontSize: 12, color: _kDark),
                  items: const [
                    DropdownMenuItem(value: 'NONE', child: Text('None')),
                    DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                    DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                    DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                    DropdownMenuItem(value: 'SUNDAY', child: Text('Sunday')),
                    DropdownMenuItem(value: 'HOLIDAY', child: Text('Holiday')),
                  ],
                  onChanged: widget.isLocked ? null : (val) {
                    if (val != null) {
                      setState(() {
                        widget.record.status = val;
                        widget.record.checkInTime = null;
                        widget.record.checkOutTime = null;
                      });
                      widget.onRecordChanged();
                    }
                  },
                ),
              ),
            ),
          ),
          // Arrival Timing
          Container(
            width: 120,
            padding: const EdgeInsets.only(right: 12),
            child: isInactive
                ? Center(child: Text('-', style: GoogleFonts.outfit(color: Colors.black26)))
                : InkWell(
                    onTap: widget.isLocked ? null : () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: widget.record.checkInTime ?? const TimeOfDay(hour: 8, minute: 0),
                      );
                      if (picked != null) {
                        if (widget.record.checkOutTime != null) {
                          final inMins = picked.hour * 60 + picked.minute;
                          final outMins = widget.record.checkOutTime!.hour * 60 + widget.record.checkOutTime!.minute;
                          if (inMins >= outMins) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Check In time must be before Check Out time'),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                            ));
                            return;
                          }
                        }
                        setState(() {
                          widget.record.checkInTime = picked;
                          widget.record.status = 'PRESENT';
                        });
                        widget.onRecordChanged();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatTimeOfDay(widget.record.checkInTime), style: GoogleFonts.outfit(fontSize: 12)),
                          if (widget.record.checkInTime != null && !widget.isLocked)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  widget.record.checkInTime = null;
                                });
                                widget.onRecordChanged();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(LucideIcons.x, size: 10, color: Colors.redAccent),
                              ),
                            )
                          else
                            const Icon(LucideIcons.clock, size: 12, color: Colors.black38),
                        ],
                      ),
                    ),
                  ),
          ),
          // Exit Timing
          Container(
            width: 120,
            padding: const EdgeInsets.only(right: 12),
            child: isInactive
                ? Center(child: Text('-', style: GoogleFonts.outfit(color: Colors.black26)))
                : InkWell(
                    onTap: widget.isLocked ? null : () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: widget.record.checkOutTime ?? const TimeOfDay(hour: 17, minute: 0),
                      );
                      if (picked != null) {
                        if (widget.record.checkInTime != null) {
                          final inMins = widget.record.checkInTime!.hour * 60 + widget.record.checkInTime!.minute;
                          final outMins = picked.hour * 60 + picked.minute;
                          if (outMins <= inMins) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Check Out time must be after Check In time'),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                            ));
                            return;
                          }
                        }
                        setState(() {
                          widget.record.checkOutTime = picked;
                        });
                        widget.onRecordChanged();
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatTimeOfDay(widget.record.checkOutTime), style: GoogleFonts.outfit(fontSize: 12)),
                              if (widget.record.checkOutTime != null && !widget.isLocked)
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      widget.record.checkOutTime = null;
                                    });
                                    widget.onRecordChanged();
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: Icon(LucideIcons.x, size: 10, color: Colors.redAccent),
                                  ),
                                )
                              else
                                const Icon(LucideIcons.clock, size: 12, color: Colors.black38),
                            ],
                          ),
                        ),
                        if (totalHours.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(totalHours, style: GoogleFonts.outfit(fontSize: 10, color: Colors.black38)),
                        ]
                      ],
                    ),
                  ),
          ),
          // Late Arrival Badge
          Container(
            width: 100,
            child: isInactive
                ? Center(child: Text('-', style: GoogleFonts.outfit(color: Colors.black26)))
                : Row(
                    children: [
                      Text(widget.record.lateMode, style: GoogleFonts.outfit(fontSize: 11, color: Colors.black54)),
                      const SizedBox(width: 4),
                      if (lateDuration != '-')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            lateDuration,
                            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                          ),
                        ),
                    ],
                  ),
          ),
          // Early Exit Badge
          Container(
            width: 100,
            child: isInactive
                ? Center(child: Text('-', style: GoogleFonts.outfit(color: Colors.black26)))
                : Row(
                    children: [
                      Text(widget.record.earlyMode, style: GoogleFonts.outfit(fontSize: 11, color: Colors.black54)),
                      const SizedBox(width: 4),
                      if (earlyDuration != '-')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            earlyDuration,
                            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay? time) {
    if (time == null) return '-';
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  String _calculateLateDuration(TimeOfDay checkIn, String limitStr) {
    try {
      final parts = limitStr.split(':');
      final limitHour = int.parse(parts[0]);
      final limitMin = int.parse(parts[1]);
      
      final checkInMins = checkIn.hour * 60 + checkIn.minute;
      final limitMins = limitHour * 60 + limitMin;
      
      if (checkInMins > limitMins) {
        final diff = checkInMins - limitMins;
        final hours = diff ~/ 60;
        final mins = diff % 60;
        return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    return '-';
  }

  String _calculateEarlyExitDuration(TimeOfDay checkOut, String limitStr) {
    try {
      final parts = limitStr.split(':');
      final limitHour = int.parse(parts[0]);
      final limitMin = int.parse(parts[1]);
      
      final checkOutMins = checkOut.hour * 60 + checkOut.minute;
      final limitMins = limitHour * 60 + limitMin;
      
      if (checkOutMins < limitMins) {
        final diff = limitMins - checkOutMins;
        final hours = diff ~/ 60;
        final mins = diff % 60;
        return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    return '-';
  }

  String _calculateTotalHours(TimeOfDay checkIn, TimeOfDay checkOut) {
    final checkInMins = checkIn.hour * 60 + checkIn.minute;
    final checkOutMins = checkOut.hour * 60 + checkOut.minute;
    if (checkOutMins > checkInMins) {
      final diff = checkOutMins - checkInMins;
      final hours = diff / 60.0;
      return 'Total: ${hours.toStringAsFixed(2)} hrs';
    }
    return '';
  }
}
