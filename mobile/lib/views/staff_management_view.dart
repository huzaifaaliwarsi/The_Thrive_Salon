import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../utils/web_download_helper.dart';
import '../services/api_service.dart';
import '../providers/staff_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/currency_provider.dart';

const _kPrimary = Color(0xFF6A11CB);
const _kDark    = Color(0xFF1B1B3A);

class StaffManagementView extends ConsumerStatefulWidget {
  const StaffManagementView({super.key});

  @override
  ConsumerState<StaffManagementView> createState() => _StaffManagementViewState();
}

class _StaffManagementViewState extends ConsumerState<StaffManagementView> {
  String _searchQuery = '';
  String _selectedRole = 'All';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(staffProvider);
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('Staff', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20, color: Colors.black38),
            onPressed: _refresh,
          ),
        ],
      ),
      body: ref.watch(staffProvider).when(
        data: (rawList) {
          final staffList = List<dynamic>.from(rawList);
          staffList.sort((a, b) {
            final valA = double.tryParse(a['salaryValue']?.toString() ?? '0') ?? 0.0;
            final valB = double.tryParse(b['salaryValue']?.toString() ?? '0') ?? 0.0;
            return valB.compareTo(valA);
          });

          if (staffList.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(LucideIcons.users, size: 56, color: Colors.black12),
                const SizedBox(height: 14),
                Text('No staff members yet', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 16)),
                const SizedBox(height: 8),
                Text('Tap + to add your first staff member', style: GoogleFonts.outfit(color: Colors.black26, fontSize: 13)),
              ]),
            );
          }

          if (_selectedRole != 'All' && _selectedRole != 'Salaried' && _selectedRole != 'Commission') {
            _selectedRole = 'All';
          }

          final filteredStaff = staffList.where((staff) {
            final name = (staff['name'] ?? '').toString().toLowerCase();
            final matchesSearch = name.contains(_searchQuery.trim().toLowerCase());
            
            final salaryType = (staff['salaryType'] ?? 'MONTHLY').toString().toUpperCase();
            
            bool matchesCategory = true;
            if (_selectedRole == 'Salaried') {
              matchesCategory = salaryType == 'MONTHLY' || salaryType == 'DAILY';
            } else if (_selectedRole == 'Commission') {
              matchesCategory = salaryType.contains('COMMISSION');
            }
            
            return matchesSearch && matchesCategory;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        style: GoogleFonts.outfit(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search staff by name...',
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF8F9FD),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FD),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedRole,
                                  isExpanded: true,
                                  style: GoogleFonts.outfit(fontSize: 13, color: Colors.black87),
                                  icon: const Icon(LucideIcons.chevronDown, size: 16),
                                  items: const [
                                    DropdownMenuItem(value: 'All', child: Text('All Staff')),
                                    DropdownMenuItem(value: 'Salaried', child: Text('Salaried Staff')),
                                    DropdownMenuItem(value: 'Commission', child: Text('Commission Staff')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedRole = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _kPrimary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.users, size: 16, color: _kPrimary),
                                const SizedBox(width: 6),
                                Text(
                                  filteredStaff.length == staffList.length
                                      ? '${staffList.length} Registered'
                                      : '${filteredStaff.length} of ${staffList.length} Staff',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _kPrimary,
                                  ),
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
              Expanded(
                child: filteredStaff.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.users, size: 56, color: Colors.black12),
                            const SizedBox(height: 14),
                            Text('No matching staff members', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: filteredStaff.length,
                        itemBuilder: (context, index) {
                          final staff = filteredStaff[index];
                          final user = staff['user'] is Map ? staff['user'] as Map : null;
                          final bool isActive = user != null ? (user['isActive'] != 'false' && user['isActive'] != false) : true;
                          final String role = (user != null && user['role'] != null)
                              ? (user['role'] as String).replaceAll('_', ' ')
                              : 'STAFF';
                          final String initials = (staff['name'] as String? ?? 'S')
                              .trim()
                              .split(' ')
                              .take(2)
                              .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
                              .join();
                          final salesCount = staff['salesCount'] ?? 0;
                          final rev = double.tryParse(staff['totalSalesRevenue']?.toString() ?? '0') ?? 0.0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // Initials avatar
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [_kPrimary, Color(0xFF2575FC)]),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(initials, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                  ),
                                  const SizedBox(width: 14),
                                  // Info
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(staff['name'], style: GoogleFonts.outfit(color: _kDark, fontSize: 15, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Row(children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _kPrimary.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(role, style: GoogleFonts.outfit(color: _kPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (isActive ? Colors.green : Colors.red).withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isActive ? 'Active' : 'Locked',
                                            style: GoogleFonts.outfit(color: isActive ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        if (staff['biometricPin'] != null && staff['biometricPin'].toString().isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(LucideIcons.fingerprint, size: 11, color: Colors.purple),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'PIN #${staff['biometricPin']}',
                                                  style: GoogleFonts.outfit(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ]),
                                      if (user != null && user['email'] != null && user['email'] != '***@***.com' && user['email'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(LucideIcons.mail, size: 12, color: Colors.grey.shade400),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                user['email'].toString(),
                                                style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if ((staff['phone'] != null && staff['phone'] != '***' && staff['phone'].toString().isNotEmpty) || (user != null && user['phone'] != null && user['phone'] != '***' && user['phone'].toString().isNotEmpty)) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(LucideIcons.phone, size: 12, color: Colors.grey.shade400),
                                            const SizedBox(width: 4),
                                            Text(
                                              (staff['phone'] != null && staff['phone'] != '***' && staff['phone'].toString().isNotEmpty) ? staff['phone'].toString() : (user != null ? user['phone']?.toString() ?? '' : ''),
                                              style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45),
                                            ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      // Salary info if not confidential
                                      if (staff['salaryType'] != 'CONFIDENTIAL') ...[
                                        Row(
                                          children: [
                                            Icon(LucideIcons.coins, size: 12, color: Colors.orange.shade300),
                                            const SizedBox(width: 4),
                                            Text(
                                              _formatSalary(staff['salaryType'] ?? '', staff['salaryValue'], staff['commissionPercentage'], currency),
                                              style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                      ],
                                      if (staff['joiningDate'] != null || staff['joining_date'] != null) ...[
                                        Row(
                                          children: [
                                            Icon(LucideIcons.calendar, size: 12, color: Colors.blue.shade300),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Joined: ${staff['joiningDate'] ?? staff['joining_date']}',
                                              style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                      ],
                                      Row(
                                        children: [
                                          Icon(LucideIcons.shoppingBag, size: 12, color: Colors.blue.shade300),
                                          const SizedBox(width: 4),
                                          Text('$salesCount sales', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45)),
                                          const SizedBox(width: 12),
                                          Icon(LucideIcons.banknote, size: 12, color: Colors.green.shade300),
                                          const SizedBox(width: 4),
                                          Text('$currency ${rev.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45)),
                                        ],
                                      ),
                                    ]),
                                  ),
                                  // Actions popup
                                  if (ref.read(authProvider.select((u) => u?['role'])) != 'STAFF')
                                    PopupMenuButton<String>(
                                      icon: const Icon(LucideIcons.moreVertical, color: Colors.black38, size: 20),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(children: [
                                            const Icon(LucideIcons.edit2, size: 16, color: Colors.indigo),
                                            const SizedBox(width: 10),
                                            Text('Edit Details', style: GoogleFonts.outfit()),
                                          ]),
                                        ),
                                        PopupMenuItem(
                                          value: 'toggle',
                                          child: Row(children: [
                                            Icon(isActive ? LucideIcons.lock : LucideIcons.unlock, size: 16, color: isActive ? Colors.orange : Colors.green),
                                            const SizedBox(width: 10),
                                            Text(isActive ? 'Lock Account' : 'Unlock Account', style: GoogleFonts.outfit()),
                                          ]),
                                        ),
                                        PopupMenuItem(
                                          value: 'resetpw',
                                          child: Row(children: [
                                            const Icon(LucideIcons.key, size: 16, color: Colors.blue),
                                            const SizedBox(width: 10),
                                            Text('Reset Password', style: GoogleFonts.outfit()),
                                          ]),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(children: [
                                            const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                                            const SizedBox(width: 10),
                                            Text('Delete', style: GoogleFonts.outfit(color: Colors.red)),
                                          ]),
                                        ),
                                      ],
                                      onSelected: (action) async {
                                        if (action == 'edit') {
                                          _showEditStaffDialog(staff);
                                        } else if (action == 'toggle') {
                                          if (user != null && user['id'] != null) {
                                            try {
                                              await ref.read(apiServiceProvider).toggleUserLock(user['id']);
                                              _refresh();
                                            } catch (e) {
                                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                                            }
                                          }
                                        } else if (action == 'resetpw') {
                                          if (user != null && user['id'] != null) {
                                            _showResetPasswordDialog(user['id']);
                                          }
                                        } else if (action == 'delete') {
                                          _confirmDeleteStaff(staff['id'], staff['name']);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ).animate().fadeIn(delay: (index * 60).ms).slideY(begin: 0.08);
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: _kPrimary)),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(LucideIcons.wifiOff, size: 48, color: Colors.black12),
            const SizedBox(height: 12),
            Text('Failed to load staff: $e', style: GoogleFonts.outfit(color: Colors.black38)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
          ]),
        ),
      ),
      floatingActionButton: ref.watch(authProvider.select((u) => u?['role'])) == 'STAFF'
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'bulkStaffBtn',
                onPressed: () => _showBulkAddStaffDialog(),
                backgroundColor: const Color(0xFF2575FC),
                elevation: 2,
                icon: const Icon(LucideIcons.fileSpreadsheet, color: Colors.white, size: 18),
                label: Text('Bulk Upload (Excel)', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              FloatingActionButton.extended(
                heroTag: 'addStaffBtn',
                onPressed: () => _showAddStaffDialog(),
                backgroundColor: _kPrimary,
                elevation: 2,
                icon: const Icon(LucideIcons.userPlus, color: Colors.white, size: 18),
                label: Text('Add Staff', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
    );
  }

  Future<void> _importStaffFromExcelOrCsv(Function setDialogState, List<Map<String, TextEditingController>> rows) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.size > 20 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File size exceeds 20MB limit. Please upload a smaller file.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) return;

      final ext = file.extension?.toLowerCase() ?? '';
      final parsedRows = <List<dynamic>>[];

      if (ext == 'csv') {
        String content;
        try {
          content = utf8.decode(bytes);
        } catch (_) {
          content = String.fromCharCodes(bytes);
        }
        content = content.replaceAll('\r\n', '\n');
        final csvData = const CsvToListConverter(eol: '\n').convert(content);
        parsedRows.addAll(csvData);
      } else {
        final excel = excel_pkg.Excel.decodeBytes(bytes);
        for (var table in excel.tables.keys) {
          for (var row in excel.tables[table]!.rows) {
            parsedRows.add(row.map((cell) => cell?.value?.toString() ?? '').toList());
          }
          break;
        }
      }

      if (parsedRows.isEmpty) return;

      int startIdx = 0;
      if (parsedRows.length > 1) {
        final firstCol = parsedRows[0][0]?.toString().toLowerCase() ?? '';
        if (firstCol.contains('name') || firstCol.contains('staff')) {
          startIdx = 1;
        }
      }

      setDialogState(() {
        for (int i = startIdx; i < parsedRows.length; i++) {
          final row = parsedRows[i];
          if (row.isEmpty) continue;
          final name = row.isNotEmpty ? row[0]?.toString().trim() ?? '' : '';
          if (name.isEmpty) continue;

          final email = row.length > 1 ? row[1]?.toString().trim() ?? '' : '';
          final password = row.length > 2 ? row[2]?.toString().trim() ?? 'Staff@123' : 'Staff@123';
          final phone = row.length > 3 ? row[3]?.toString().trim() ?? '' : '';
          final salaryType = row.length > 4 ? row[4]?.toString().trim().toUpperCase() ?? 'MONTHLY' : 'MONTHLY';
          final salaryValue = row.length > 5 ? row[5]?.toString().trim() ?? '0' : '0';
          final comm = row.length > 6 ? row[6]?.toString().trim() ?? '0' : '0';

          rows.add({
            'name': TextEditingController(text: name),
            'email': TextEditingController(text: email.isNotEmpty ? email : '${name.toLowerCase().replaceAll(' ', '')}@salon.com'),
            'password': TextEditingController(text: password.isNotEmpty ? password : 'Staff@123'),
            'phone': TextEditingController(text: phone),
            'salaryType': TextEditingController(text: salaryType.isNotEmpty ? salaryType : 'MONTHLY'),
            'salaryValue': TextEditingController(text: salaryValue),
            'commissionPercentage': TextEditingController(text: comm),
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded ${parsedRows.length - startIdx} staff members from Excel/CSV file.', style: GoogleFonts.outfit(color: Colors.white)),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading Excel/CSV file: $e', style: GoogleFonts.outfit(color: Colors.white)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _downloadStaffExcelTemplate() async {
    try {
      const csvHeader = 'Name,Email,Password,Phone,SalaryType,SalaryValue,CommissionPercentage\n';
      const sample1 = 'Ahmad Khan,ahmad@salon.com,Staff@123,+923001234567,MONTHLY,25000,10\n';
      const sample2 = 'Sara Ali,sara@salon.com,Staff@123,+923007654321,COMMISSION,0,15\n';
      final fullCsv = csvHeader + sample1 + sample2;

      if (kIsWeb) {
        downloadCsv(fullCsv, 'Staff_Import_Template');
        return;
      }

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Template',
          fileName: 'Staff_Import_Template.csv',
        );
        if (outputFile != null) {
          await File(outputFile).writeAsString(fullCsv);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $outputFile')));
          }
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/Staff_Import_Template.csv');
        await file.writeAsString(fullCsv);
        await Share.shareXFiles([XFile(file.path)], text: 'Download Staff Excel / CSV Import Template');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error downloading template: $e')));
      }
    }
  }

  void _showBulkAddStaffDialog() {
    final rows = <Map<String, TextEditingController>>[
      {
        'name': TextEditingController(),
        'email': TextEditingController(),
        'password': TextEditingController(text: 'Staff@123'),
        'phone': TextEditingController(),
        'salaryType': TextEditingController(text: 'MONTHLY'),
        'salaryValue': TextEditingController(),
        'commissionPercentage': TextEditingController(text: '0'),
      },
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.users, color: _kPrimary),
                    const SizedBox(width: 10),
                    Text('Bulk Upload Staff', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ],
                ),
                TextButton.icon(
                  onPressed: _downloadStaffExcelTemplate,
                  icon: const Icon(LucideIcons.download, size: 14, color: _kPrimary),
                  label: Text('Template', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kPrimary)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 550,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.fileSpreadsheet, color: Color(0xFF2563EB), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Upload Excel (.xlsx) or CSV file to import staff list.', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF1E40AF))),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _importStaffFromExcelOrCsv(setDialogState, rows),
                            icon: const Icon(LucideIcons.upload, size: 14, color: Colors.white),
                            label: Text('Upload Excel', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(rows.length, (idx) {
                      final r = rows[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Staff Member #${idx + 1}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: _kPrimary)),
                                if (rows.length > 1)
                                  IconButton(
                                    icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent),
                                    onPressed: () => setDialogState(() => rows.removeAt(idx)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: r['name'],
                                    style: GoogleFonts.outfit(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Full Name',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: r['email'],
                                    style: GoogleFonts.outfit(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Email (login)',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: r['phone'],
                                    style: GoogleFonts.outfit(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Phone',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: r['password'],
                                    style: GoogleFonts.outfit(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Password',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: r['salaryValue'],
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.outfit(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Salary Amount',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: r['commissionPercentage'],
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.outfit(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Commission %',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            rows.add({
                              'name': TextEditingController(),
                              'email': TextEditingController(),
                              'password': TextEditingController(text: 'Staff@123'),
                              'phone': TextEditingController(),
                              'salaryType': TextEditingController(text: 'MONTHLY'),
                              'salaryValue': TextEditingController(),
                              'commissionPercentage': TextEditingController(text: '0'),
                            });
                          });
                        },
                        icon: const Icon(LucideIcons.plus, size: 16, color: _kPrimary),
                        label: Text('Add Another Staff Row', style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black45)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final staffToSave = <Map<String, dynamic>>[];
                  for (var r in rows) {
                    final n = r['name']!.text.trim();
                    final e = r['email']!.text.trim();
                    final p = r['password']!.text.trim();
                    final ph = r['phone']!.text.trim();
                    final sType = r['salaryType']!.text.trim();
                    final sVal = r['salaryValue']!.text.trim();
                    final comm = r['commissionPercentage']!.text.trim();

                    if (n.isNotEmpty && e.isNotEmpty) {
                      staffToSave.add({
                        'name': n,
                        'email': e,
                        'password': p.isNotEmpty ? p : 'Staff@123',
                        'phone': ph,
                        'salaryType': sType.isNotEmpty ? sType : 'MONTHLY',
                        'salaryValue': sVal.isNotEmpty ? sVal : '0',
                        'commissionPercentage': comm.isNotEmpty ? comm : '0',
                      });
                    }
                  }

                  if (staffToSave.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Please fill in at least one staff member name and email.', style: GoogleFonts.outfit(color: Colors.white)),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  try {
                    await ref.read(apiServiceProvider).bulkCreateStaff(staffToSave);
                    ref.invalidate(staffProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (err) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bulk staff error: $err')));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Save All Staff', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddStaffDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final biometricPinCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    final commissionCtrl = TextEditingController();
    final inTimeCtrl = TextEditingController();
    final outTimeCtrl = TextEditingController();
    final lateTimeCtrl = TextEditingController();
    final earlyExitCtrl = TextEditingController();
    final lateDeductCtrl = TextEditingController(text: '0');
    final earlyDeductCtrl = TextEditingController(text: '0');
    final leavesCtrl = TextEditingController(text: '0');
    String salaryType = 'MONTHLY';
    DateTime joiningDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('Add New Staff', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: _kDark)),
                const SizedBox(height: 20),
                _field(nameCtrl, 'Full Name', LucideIcons.user),
                _field(emailCtrl, 'Email', LucideIcons.mail, type: TextInputType.emailAddress),
                _field(passwordCtrl, 'Password', LucideIcons.lock, obscure: true),
                _field(phoneCtrl, 'Phone (optional)', LucideIcons.phone, type: TextInputType.phone),
                _field(biometricPinCtrl, 'ZKTeco Biometric Machine PIN / Staff ID (optional)', LucideIcons.fingerprint, type: TextInputType.text),
                DropdownButtonFormField<String>(
                  value: salaryType,
                  decoration: _inputDeco('Salary Type', LucideIcons.banknote),
                  items: [
                    'MONTHLY', 
                    'DAILY', 
                    'COMMISSION', 
                    'MONTHLY_PLUS_COMMISSION', 
                    'DAILY_PLUS_COMMISSION'
                  ].map((t) => DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' ')))).toList(),
                  onChanged: (v) => setS(() => salaryType = v!),
                ),
                const SizedBox(height: 12),
                if (salaryType != 'COMMISSION')
                  _field(salaryCtrl, 'Base Salary / Daily Wage', LucideIcons.hash, type: TextInputType.number),
                if (salaryType.contains('COMMISSION'))
                  _field(commissionCtrl, 'Commission Percentage (%)', LucideIcons.percent, type: TextInputType.number),
                const Divider(height: 24),
                Text('Timing & Deductions', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: _kDark)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _timeField(context, inTimeCtrl, 'In Time (HH:MM)', LucideIcons.logIn, setS)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField(context, outTimeCtrl, 'Out Time (HH:MM)', LucideIcons.logOut, setS)),
                ]),
                Row(children: [
                  Expanded(child: _timeField(context, lateTimeCtrl, 'Late After (HH:MM)', LucideIcons.alarmClock, setS)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField(context, earlyExitCtrl, 'Early Exit Before', LucideIcons.alarmClock, setS)),
                ]),
                Row(children: [
                  Expanded(child: _field(lateDeductCtrl, 'Late Deduction Rate', LucideIcons.minusCircle, type: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: _field(earlyDeductCtrl, 'Early Exit Ded. Rate', LucideIcons.minusCircle, type: TextInputType.number)),
                ]),
                _field(leavesCtrl, 'Allowed Leaves / Month', LucideIcons.calendarOff, type: TextInputType.number),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Joining Date', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: _kDark)),
                  subtitle: Text(
                    '${joiningDate.year}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
                    style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(LucideIcons.calendar, size: 20, color: _kPrimary),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: joiningDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setS(() => joiningDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
                        _showError(context, 'Please enter Name, Email, and Password');
                        return;
                      }

                      final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegExp.hasMatch(emailCtrl.text.trim())) {
                        _showError(context, 'Please enter a valid email address');
                        return;
                      }

                      if (passwordCtrl.text.length < 6) {
                        _showError(context, 'Password must be at least 6 characters long');
                        return;
                      }

                      if (phoneCtrl.text.isNotEmpty) {
                        final phoneRegExp = RegExp(r'^[+0-9\s\-()]{5,20}$');
                        if (!phoneRegExp.hasMatch(phoneCtrl.text.trim())) {
                          _showError(context, 'Please enter a valid phone number');
                          return;
                        }
                      }

                      if (salaryType != 'COMMISSION') {
                        final salVal = double.tryParse(salaryCtrl.text);
                        if (salVal == null || salVal < 0) {
                          _showError(context, 'Please enter a valid salary/wage amount');
                          return;
                        }
                      }

                      if (salaryType.contains('COMMISSION')) {
                        final commVal = double.tryParse(commissionCtrl.text);
                        if (commVal == null || commVal < 0 || commVal > 100) {
                          _showError(context, 'Commission percentage must be between 0 and 100%');
                          return;
                        }
                      }

                      final lateVal = double.tryParse(lateDeductCtrl.text);
                      final earlyVal = double.tryParse(earlyDeductCtrl.text);
                      final leavesVal = int.tryParse(leavesCtrl.text);
                      if (lateVal == null || lateVal < 0 || earlyVal == null || earlyVal < 0) {
                        _showError(context, 'Deduction rates must be valid non-negative numbers');
                        return;
                      }
                      if (leavesVal == null || leavesVal < 0) {
                        _showError(context, 'Allowed leaves must be a valid non-negative number');
                        return;
                      }

                      // Require all time fields to be filled
                      final timeFields = {
                        'Check-In Time (In Time Limit)': inTimeCtrl.text.trim(),
                        'Check-Out Time (Out Time Limit)': outTimeCtrl.text.trim(),
                        'Late Arrival Limit': lateTimeCtrl.text.trim(),
                        'Early Exit Limit': earlyExitCtrl.text.trim(),
                      };
                      final missingFields = timeFields.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
                      if (missingFields.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: Row(
                              children: [
                                Icon(LucideIcons.clock, color: Colors.redAccent, size: 22),
                                const SizedBox(width: 8),
                                Text('Missing Shift Times', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Please fill in the following required time fields before registering staff:', style: GoogleFonts.outfit(color: Colors.black54, fontSize: 13)),
                                const SizedBox(height: 12),
                                ...missingFields.map((f) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
                                      const SizedBox(width: 6),
                                      Text(f, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.redAccent)),
                                    ],
                                  ),
                                )),
                              ],
                            ),
                            actions: [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                child: Text('OK, Fix It', style: GoogleFonts.outfit(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      final inMins = _parseTimeToMinutes(inTimeCtrl.text.trim());
                      final outMins = _parseTimeToMinutes(outTimeCtrl.text.trim());
                      final lateMins = _parseTimeToMinutes(lateTimeCtrl.text.trim());
                      final earlyMins = _parseTimeToMinutes(earlyExitCtrl.text.trim());

                      if (inMins != null && outMins != null && inMins != 0 && outMins != 0 && outMins < inMins) {
                        _showError(context, 'Out Time (Checkout) must be after In Time (Check-in)');
                        return;
                      }
                      if (inMins != null && lateMins != null && lateMins != 0 && inMins != 0 && lateMins < inMins) {
                        _showError(context, 'Late Limit must be after In Time');
                        return;
                      }
                      if (outMins != null && earlyMins != null && earlyMins != 0 && outMins != 0 && earlyMins > outMins) {
                        _showError(context, 'Early Exit Limit must be before Out Time');
                        return;
                      }

                      try {
                        await ref.read(apiServiceProvider).createStaff({
                          'name': nameCtrl.text,
                          'email': emailCtrl.text.trim().toLowerCase(),
                          'password': passwordCtrl.text,
                          'phone': phoneCtrl.text,
                          'biometricPin': biometricPinCtrl.text.trim(),
                          'salaryType': salaryType,
                          'salaryValue': double.tryParse(salaryCtrl.text) ?? 0,
                          'commissionPercentage': double.tryParse(commissionCtrl.text) ?? 0,
                          'inTimeLimit': inTimeCtrl.text.trim(),
                          'outTimeLimit': outTimeCtrl.text.trim(),
                          'lateTimeLimit': lateTimeCtrl.text.trim(),
                          'earlyExitTimeLimit': earlyExitCtrl.text.trim(),
                          'lateDeductionRate': double.tryParse(lateDeductCtrl.text) ?? 0,
                          'earlyExitDeductionRate': double.tryParse(earlyDeductCtrl.text) ?? 0,
                          'allowedLeaves': int.tryParse(leavesCtrl.text) ?? 0,
                          'joiningDate': '${joiningDate.year}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
                        });
                        if (mounted) { Navigator.pop(context); _refresh(); }
                      } catch (e) {
                        String errMsg = e.toString();
                        if (errMsg.startsWith('Exception: ')) {
                          errMsg = errMsg.replaceFirst('Exception: ', '');
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(errMsg, style: GoogleFonts.outfit(color: Colors.white)),
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 4),
                              behavior: SnackBarBehavior.floating,
                            )
                          );
                        }
                      }
                    },
                    child: Text('Add Staff Member', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType? type, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        obscureText: obscure,
        style: GoogleFonts.outfit(fontSize: 14),
        decoration: _inputDeco(label, icon),
      ),
    );
  }

  Widget _timeField(BuildContext context, TextEditingController c, String label, IconData icon, StateSetter setS) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey((c, c.text)),
        initialValue: _displayStaffTime(c.text),
        readOnly: true,
        onTap: () async {
          TimeOfDay initial = const TimeOfDay(hour: 0, minute: 0);
          if (c.text.isNotEmpty) {
            final parts = c.text.split(':');
            if (parts.length == 2) {
              final h = int.tryParse(parts[0]);
              final m = int.tryParse(parts[1]);
              if (h != null && m != null) {
                initial = TimeOfDay(hour: h, minute: m);
              }
            }
          }
          final picked = await showTimePicker(
            context: context,
            initialTime: initial,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
              child: child!,
            ),
          );
          if (picked != null) {
            final hourStr = picked.hour.toString().padLeft(2, '0');
            final minuteStr = picked.minute.toString().padLeft(2, '0');
            setS(() {
              c.text = '$hourStr:$minuteStr';
            });
          }
        },
        style: GoogleFonts.outfit(fontSize: 14),
        decoration: InputDecoration(
          labelText: label.replaceAll(' (HH:MM)', ''),
          prefixIcon: Icon(icon, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
          suffixIcon: c.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                  onPressed: () {
                    setS(() {
                      c.clear();
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF8F9FD),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          labelStyle: GoogleFonts.outfit(fontSize: 14),
        ),
      ),
    );
  }

  // Keep the controller's HH:mm value for validation and API requests;
  // only the read-only input displays the selected AM/PM time.
  String _displayStaffTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return value;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) return value;
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final minutes = minute.toString().padLeft(2, '0');
    return '$displayHour:$minutes ${hour < 12 ? 'AM' : 'PM'}';
  }

  int? _parseTimeToMinutes(String timeStr) {
    if (timeStr.isEmpty) return null;
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.outfit(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
    filled: true,
    fillColor: const Color(0xFFF8F9FD),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    labelStyle: GoogleFonts.outfit(fontSize: 14),
  );

  void _showResetPasswordDialog(String userId) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Reset Password', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: _inputDeco('New Password', LucideIcons.lock),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () async {
              try {
                await ref.read(apiServiceProvider).resetUserPassword(userId, ctrl.text);
                if (mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset!'))); }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: Text('Reset', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteStaff(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete $name?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: Text('This will permanently delete this staff member and their login account.', style: GoogleFonts.outfit(color: Colors.black54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await ref.read(apiServiceProvider).deleteStaff(id);
                if (mounted) { Navigator.pop(ctx); _refresh(); }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatSalary(String type, dynamic val, dynamic commission, String currency) {
    final value = double.tryParse(val?.toString() ?? '0') ?? 0.0;
    final comm = double.tryParse(commission?.toString() ?? '0') ?? 0.0;
    
    switch (type) {
      case 'MONTHLY':
        return 'Monthly: $currency ${value.toStringAsFixed(0)}';
      case 'DAILY':
        return 'Daily: $currency ${value.toStringAsFixed(0)}';
      case 'COMMISSION':
        return 'Commission: ${comm.toStringAsFixed(1)}%';
      case 'MONTHLY_PLUS_COMMISSION':
        return 'Monthly: $currency ${value.toStringAsFixed(0)} + ${comm.toStringAsFixed(1)}% Comm';
      case 'DAILY_PLUS_COMMISSION':
        return 'Daily: $currency ${value.toStringAsFixed(0)} + ${comm.toStringAsFixed(1)}% Comm';
      default:
        return type;
    }
  }

  void _showEditStaffDialog(dynamic staffMember) {
    final user = staffMember['user'] ?? {};
    final nameCtrl = TextEditingController(text: staffMember['name'] ?? '');
    final emailCtrl = TextEditingController(text: user['email'] ?? '');
    final phoneCtrl = TextEditingController(text: staffMember['phone'] ?? user['phone'] ?? '');
    final biometricPinCtrl = TextEditingController(text: staffMember['biometricPin']?.toString() ?? '');
    final salaryCtrl = TextEditingController(text: staffMember['salaryValue']?.toString() ?? '');
    final commissionCtrl = TextEditingController(text: staffMember['commissionPercentage']?.toString() ?? '');
    final inTimeVal = staffMember['inTimeLimit']?.toString() ?? '';
    final outTimeVal = staffMember['outTimeLimit']?.toString() ?? '';
    final lateTimeVal = staffMember['lateTimeLimit']?.toString() ?? '';
    final earlyExitVal = staffMember['earlyExitTimeLimit']?.toString() ?? '';
    final inTimeCtrl = TextEditingController(text: inTimeVal);
    final outTimeCtrl = TextEditingController(text: outTimeVal);
    final lateTimeCtrl = TextEditingController(text: lateTimeVal);
    final earlyExitCtrl = TextEditingController(text: earlyExitVal);
    final lateDeductCtrl = TextEditingController(text: staffMember['lateDeductionRate']?.toString() ?? '0');
    final earlyDeductCtrl = TextEditingController(text: staffMember['earlyExitDeductionRate']?.toString() ?? '0');
    final leavesCtrl = TextEditingController(text: staffMember['allowedLeaves']?.toString() ?? '0');
    String salaryType = staffMember['salaryType'] ?? 'MONTHLY';
    
    DateTime effectiveDate = DateTime.now();
    final joiningDateVal = staffMember['joiningDate'] ?? staffMember['joining_date'] ?? '';
    DateTime joiningDate = joiningDateVal.isNotEmpty ? DateTime.tryParse(joiningDateVal) ?? DateTime.now() : DateTime.now();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('Edit Staff Details', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: _kDark)),
                const SizedBox(height: 20),
                _field(nameCtrl, 'Full Name', LucideIcons.user),
                _field(emailCtrl, 'Email', LucideIcons.mail, type: TextInputType.emailAddress),
                _field(phoneCtrl, 'Phone (optional)', LucideIcons.phone, type: TextInputType.phone),
                _field(biometricPinCtrl, 'ZKTeco Biometric Machine PIN / Staff ID', LucideIcons.fingerprint, type: TextInputType.text),
                DropdownButtonFormField<String>(
                  value: salaryType,
                  decoration: _inputDeco('Salary Type', LucideIcons.banknote),
                  items: [
                    'MONTHLY', 
                    'DAILY', 
                    'COMMISSION', 
                    'MONTHLY_PLUS_COMMISSION', 
                    'DAILY_PLUS_COMMISSION'
                  ].map((t) => DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' ')))).toList(),
                  onChanged: (v) => setS(() => salaryType = v!),
                ),
                const SizedBox(height: 12),
                if (salaryType != 'COMMISSION')
                  _field(salaryCtrl, 'Base Salary / Daily Wage', LucideIcons.hash, type: TextInputType.number),
                if (salaryType.contains('COMMISSION'))
                  _field(commissionCtrl, 'Commission Percentage (%)', LucideIcons.percent, type: TextInputType.number),
                
                const Divider(height: 24),
                Text('Timing & Deductions', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: _kDark)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _timeField(context, inTimeCtrl, 'In Time (HH:MM)', LucideIcons.logIn, setS)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField(context, outTimeCtrl, 'Out Time (HH:MM)', LucideIcons.logOut, setS)),
                ]),
                Row(children: [
                  Expanded(child: _timeField(context, lateTimeCtrl, 'Late After (HH:MM)', LucideIcons.alarmClock, setS)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField(context, earlyExitCtrl, 'Early Exit Before', LucideIcons.alarmClock, setS)),
                ]),
                Row(children: [
                  Expanded(child: _field(lateDeductCtrl, 'Late Deduction Rate', LucideIcons.minusCircle, type: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: _field(earlyDeductCtrl, 'Early Exit Ded. Rate', LucideIcons.minusCircle, type: TextInputType.number)),
                ]),
                _field(leavesCtrl, 'Allowed Leaves / Month', LucideIcons.calendarOff, type: TextInputType.number),

                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Joining Date', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: _kDark)),
                  subtitle: Text(
                    '${joiningDate.year}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
                    style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(LucideIcons.calendar, size: 20, color: _kPrimary),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: joiningDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setS(() => joiningDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 6),
                // Effective Date picker for salary changes
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Salary Effective Date', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: _kDark)),
                  subtitle: Text(
                    '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}',
                    style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(LucideIcons.calendar, size: 20, color: _kPrimary),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: effectiveDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setS(() => effectiveDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: isSubmitting ? null : () async {
                      if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty) {
                        _showError(context, 'Please enter Name and Email');
                        return;
                      }

                      final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegExp.hasMatch(emailCtrl.text.trim())) {
                        _showError(context, 'Please enter a valid email address');
                        return;
                      }

                      if (phoneCtrl.text.isNotEmpty) {
                        final phoneRegExp = RegExp(r'^[+0-9\s\-()]{5,20}$');
                        if (!phoneRegExp.hasMatch(phoneCtrl.text.trim())) {
                          _showError(context, 'Please enter a valid phone number');
                          return;
                        }
                      }

                      if (salaryType != 'COMMISSION') {
                        final salVal = double.tryParse(salaryCtrl.text);
                        if (salVal == null || salVal < 0) {
                          _showError(context, 'Please enter a valid salary/wage amount');
                          return;
                        }
                      }

                      if (salaryType.contains('COMMISSION')) {
                        final commVal = double.tryParse(commissionCtrl.text);
                        if (commVal == null || commVal < 0 || commVal > 100) {
                          _showError(context, 'Commission percentage must be between 0 and 100%');
                          return;
                        }
                      }

                      final lateVal = double.tryParse(lateDeductCtrl.text);
                      final earlyVal = double.tryParse(earlyDeductCtrl.text);
                      final leavesVal = int.tryParse(leavesCtrl.text);
                      if (lateVal == null || lateVal < 0 || earlyVal == null || earlyVal < 0) {
                        _showError(context, 'Deduction rates must be valid non-negative numbers');
                        return;
                      }
                      if (leavesVal == null || leavesVal < 0) {
                        _showError(context, 'Allowed leaves must be a valid non-negative number');
                        return;
                      }

                      // Require all time fields to be filled
                      final timeFields = {
                        'Check-In Time (In Time Limit)': inTimeCtrl.text.trim(),
                        'Check-Out Time (Out Time Limit)': outTimeCtrl.text.trim(),
                        'Late Arrival Limit': lateTimeCtrl.text.trim(),
                        'Early Exit Limit': earlyExitCtrl.text.trim(),
                      };
                      final missingFields = timeFields.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
                      if (missingFields.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: Row(
                              children: [
                                Icon(LucideIcons.clock, color: Colors.redAccent, size: 22),
                                const SizedBox(width: 8),
                                Text('Missing Shift Times', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Please fill in the following required time fields before updating staff:', style: GoogleFonts.outfit(color: Colors.black54, fontSize: 13)),
                                const SizedBox(height: 12),
                                ...missingFields.map((f) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
                                      const SizedBox(width: 6),
                                      Text(f, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.redAccent)),
                                    ],
                                  ),
                                )),
                              ],
                            ),
                            actions: [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                child: Text('OK, Fix It', style: GoogleFonts.outfit(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      final inMins = _parseTimeToMinutes(inTimeCtrl.text.trim());
                      final outMins = _parseTimeToMinutes(outTimeCtrl.text.trim());
                      final lateMins = _parseTimeToMinutes(lateTimeCtrl.text.trim());
                      final earlyMins = _parseTimeToMinutes(earlyExitCtrl.text.trim());

                      if (inMins != null && outMins != null && inMins != 0 && outMins != 0 && outMins < inMins) {
                        _showError(context, 'Out Time (Checkout) must be after In Time (Check-in)');
                        return;
                      }
                      if (inMins != null && lateMins != null && lateMins != 0 && inMins != 0 && lateMins < inMins) {
                        _showError(context, 'Late Limit must be after In Time');
                        return;
                      }
                      if (outMins != null && earlyMins != null && earlyMins != 0 && outMins != 0 && earlyMins > outMins) {
                        _showError(context, 'Early Exit Limit must be before Out Time');
                        return;
                      }

                      setS(() => isSubmitting = true);

                      try {
                        final data = {
                          'name': nameCtrl.text.trim(),
                          'email': emailCtrl.text.trim().toLowerCase(),
                          'phone': phoneCtrl.text.trim(),
                          'biometricPin': biometricPinCtrl.text.trim(),
                          'salaryType': salaryType,
                          'salaryValue': double.tryParse(salaryCtrl.text) ?? 0.0,
                          'commissionPercentage': double.tryParse(commissionCtrl.text) ?? 0.0,
                          'effectiveDate': '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}',
                          'inTimeLimit': inTimeCtrl.text.trim(),
                          'outTimeLimit': outTimeCtrl.text.trim(),
                          'lateTimeLimit': lateTimeCtrl.text.trim(),
                          'earlyExitTimeLimit': earlyExitCtrl.text.trim(),
                          'lateDeductionRate': double.tryParse(lateDeductCtrl.text) ?? 0,
                          'earlyExitDeductionRate': double.tryParse(earlyDeductCtrl.text) ?? 0,
                          'allowedLeaves': int.tryParse(leavesCtrl.text) ?? 0,
                          'joiningDate': '${joiningDate.year}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
                        };

                        await ref.read(apiServiceProvider).updateStaff(staffMember['id'], data);
                        if (mounted) { 
                          Navigator.pop(context); 
                          _refresh(); 
                        }
                      } catch (e) {
                        String errMsg = e.toString();
                        if (errMsg.startsWith('Exception: ')) {
                          errMsg = errMsg.replaceFirst('Exception: ', '');
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(errMsg, style: GoogleFonts.outfit(color: Colors.white)),
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 4),
                              behavior: SnackBarBehavior.floating,
                            )
                          );
                        }
                      } finally {
                        setS(() => isSubmitting = false);
                      }
                    },
                    child: isSubmitting 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Update Details', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
