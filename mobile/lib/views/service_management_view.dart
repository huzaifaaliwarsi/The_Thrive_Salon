import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/foundation.dart';
import '../utils/web_download_helper.dart';
import '../services/api_service.dart';
import '../providers/services_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/dashboard_provider.dart';
import '../view_models/dashboard_view_model.dart';
import '../models/service_model.dart';

const _kPrimary = Color(0xFF6A11CB);
const _kDark = Color(0xFF1B1B3A);
const _kBg = Color(0xFFF4F6FB);
const _kAccent = Color(0xFF2575FC);

class ServiceManagementView extends ConsumerStatefulWidget {
  const ServiceManagementView({super.key});

  @override
  ConsumerState<ServiceManagementView> createState() =>
      _ServiceManagementViewState();
}

class _ServiceManagementViewState extends ConsumerState<ServiceManagementView> {
  String _filterType = 'All'; // 'All', 'Services', 'Packages'
  String _filterCategory = 'All';
  String _sortBy = 'Name'; // 'Name', 'Price', 'Category'

  void _refresh() {
    ref.invalidate(servicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Price List',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Colors.black38,
                    fontWeight: FontWeight.w500)),
            Text('Services',
                style: GoogleFonts.outfit(
                    color: _kDark, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw,
                size: 20, color: Colors.black26),
            onPressed: _refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ref.watch(servicesProvider).when(
            data: (services) {
              // Extract unique categories dynamically
              final categories = services.map((s) => s.category).toSet().toList();

              // Filter services dynamically
              final filtered = services.where((s) {
                // Exclude products from services view entirely
                if (s.category == 'Products' || s.id.startsWith('inv_')) return false;

                // Type filter
                if (_filterType == 'Services') {
                  if (s.isPackage) return false;
                } else if (_filterType == 'Packages') {
                  if (!s.isPackage) return false;
                }

                // Category filter
                if (_filterCategory != 'All' && s.category != _filterCategory) return false;

                return true;
              }).toList();

              // Sort filtered list dynamically
              filtered.sort((a, b) {
                if (_sortBy == 'Price') {
                  final pA = double.tryParse(a.price) ?? 0.0;
                  final pB = double.tryParse(b.price) ?? 0.0;
                  return pA.compareTo(pB);
                } else if (_sortBy == 'Category') {
                  return a.category.compareTo(b.category);
                } else {
                  return a.name.compareTo(b.name);
                }
              });

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.white,
                    child: Column(
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (var type in ['All', 'Services', 'Packages'])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(type, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                                    selected: _filterType == type,
                                    onSelected: (val) {
                                      if (val) setState(() => _filterType = type);
                                    },
                                    selectedColor: _kPrimary,
                                    labelStyle: TextStyle(color: _filterType == type ? Colors.white : Colors.black87),
                                  ),
                                )
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: _kBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _filterCategory,
                                    isExpanded: true,
                                    style: GoogleFonts.outfit(fontSize: 13, color: Colors.black87),
                                    items: [
                                      const DropdownMenuItem(value: 'All', child: Text('All Categories')),
                                      ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _filterCategory = val);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: _kBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _sortBy,
                                    isExpanded: true,
                                    style: GoogleFonts.outfit(fontSize: 13, color: Colors.black87),
                                    items: const [
                                      DropdownMenuItem(value: 'Name', child: Text('Sort by Name')),
                                      DropdownMenuItem(value: 'Price', child: Text('Sort by Price')),
                                      DropdownMenuItem(value: 'Category', child: Text('Sort by Category')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _sortBy = val);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final service = filtered[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4))
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(colors: [
                                            _kPrimary.withValues(alpha: 0.1),
                                            _kAccent.withValues(alpha: 0.1)
                                          ]),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(LucideIcons.scissors,
                                            color: _kPrimary, size: 20),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(service.name,
                                                style: GoogleFonts.outfit(
                                                    fontWeight: FontWeight.bold,
                                                    color: _kDark,
                                                    fontSize: 16)),
                                            if (service.description != null && service.description!.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(service.description!,
                                                  style: GoogleFonts.outfit(
                                                      color: Colors.black38,
                                                      fontSize: 12)),
                                            ],
                                            if (service.isPackage) ...[
                                              Container(
                                                margin: const EdgeInsets.only(top: 4),
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: _kPrimary.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text('Package', style: GoogleFonts.outfit(fontSize: 10, color: _kPrimary, fontWeight: FontWeight.bold)),
                                              ),
                                              if (service.bundledServices != null && service.bundledServices!.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 4,
                                                  runSpacing: 4,
                                                  children: service.bundledServices!.map((bundled) => Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF0F4C81).withValues(alpha: 0.05),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: const Color(0xFF0F4C81).withValues(alpha: 0.1)),
                                                    ),
                                                    child: Text(
                                                      bundled.name,
                                                      style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF0F4C81), fontWeight: FontWeight.w600),
                                                    ),
                                                  )).toList(),
                                                ),
                                              ],
                                            ],
                                            const SizedBox(height: 2),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                  color: _kBg,
                                                  borderRadius: BorderRadius.circular(6)),
                                              child: Text(service.category,
                                                  style: GoogleFonts.outfit(
                                                      color: Colors.black45,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(currency,
                                              style: GoogleFonts.outfit(
                                                  fontSize: 10,
                                                  color: Colors.black26,
                                                  fontWeight: FontWeight.bold)),
                                          Text(service.price,
                                              style: GoogleFonts.outfit(
                                                  color: _kPrimary,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 17)),
                                        ],
                                      ),
                                      const SizedBox(width: 8),
                                      if (ref.watch(authProvider.select((u) => u?['role'])) != 'STAFF') ...[
                                        IconButton(
                                          icon: const Icon(LucideIcons.edit2,
                                              size: 18, color: Colors.indigo),
                                          onPressed: () =>
                                              _showAddServiceSheet(service: service),
                                        ),
                                        IconButton(
                                          icon: const Icon(LucideIcons.trash2,
                                              size: 18, color: Colors.redAccent),
                                          onPressed: () =>
                                              _confirmDelete(context, ref, service.id),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.05);
                            },
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(
                child: CircularProgressIndicator(color: _kPrimary)),
            error: (e, _) =>
                Center(child: Text('Error: $e', style: GoogleFonts.outfit())),
          ),
      floatingActionButton: ref.watch(authProvider.select((u) => u?['role'])) == 'STAFF' 
        ? null 
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'bulkAddBtn',
                onPressed: () => _showBulkAddServicesDialog(),
                backgroundColor: _kAccent,
                elevation: 4,
                icon: const Icon(LucideIcons.layers, color: Colors.white, size: 20),
                label: Text('Bulk Add',
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ).animate().scale(delay: 200.ms, curve: Curves.easeOutBack),
              const SizedBox(width: 10),
              FloatingActionButton.extended(
                heroTag: 'addSingleBtn',
                onPressed: () => _showAddServiceSheet(),
                backgroundColor: _kPrimary,
                elevation: 4,
                icon: const Icon(LucideIcons.plus, color: Colors.white, size: 20),
                label: Text('Add Service',
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ).animate().scale(delay: 300.ms, curve: Curves.easeOutBack),
            ],
          ),
    );
  }

  Future<void> _importServicesFromExcelOrCsv(Function setDialogState, List<Map<String, TextEditingController>> rows) async {
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
        if (firstCol.contains('name') || firstCol.contains('service')) {
          startIdx = 1;
        }
      }

      setDialogState(() {
        for (int i = startIdx; i < parsedRows.length; i++) {
          final row = parsedRows[i];
          if (row.isEmpty) continue;
          final name = row.isNotEmpty ? row[0]?.toString().trim() ?? '' : '';
          if (name.isEmpty) continue;

          final category = row.length > 1 ? row[1]?.toString().trim() ?? 'General' : 'General';
          final price = row.length > 2 ? row[2]?.toString().trim() ?? '0' : '0';

          rows.add({
            'name': TextEditingController(text: name),
            'category': TextEditingController(text: category.isNotEmpty ? category : 'General'),
            'price': TextEditingController(text: price),
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully loaded ${parsedRows.length - startIdx} services from file.', style: GoogleFonts.outfit(color: Colors.white)),
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

  Future<void> _downloadServicesExcelTemplate() async {
    try {
      const csvHeader = 'Name,Category,Price,Description\n';
      const sample1 = 'Haircut & Styling,General,1500,Standard hair styling\n';
      const sample2 = 'Hydra Facial,Skincare,3500,Deep skin cleansing\n';
      const sample3 = 'Manicure & Pedicure,Nails,2500,Complete hand and feet treatment\n';
      final fullCsv = csvHeader + sample1 + sample2 + sample3;

      if (kIsWeb) {
        downloadCsv(fullCsv, 'Services_Import_Template');
        return;
      }

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Template',
          fileName: 'Services_Import_Template.csv',
        );
        if (outputFile != null) {
          await File(outputFile).writeAsString(fullCsv);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $outputFile')));
          }
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/Services_Import_Template.csv');
        await file.writeAsString(fullCsv);
        await Share.shareXFiles([XFile(file.path)], text: 'Download Services Excel / CSV Import Template');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error downloading template: $e')));
      }
    }
  }

  void _showBulkAddServicesDialog() {
    final rows = <Map<String, TextEditingController>>[
      {'name': TextEditingController(), 'category': TextEditingController(text: 'General'), 'price': TextEditingController()},
      {'name': TextEditingController(), 'category': TextEditingController(text: 'General'), 'price': TextEditingController()},
      {'name': TextEditingController(), 'category': TextEditingController(text: 'General'), 'price': TextEditingController()},
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
                    const Icon(LucideIcons.layers, color: _kPrimary),
                    const SizedBox(width: 10),
                    Text('Bulk Add Services', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ],
                ),
                TextButton.icon(
                  onPressed: _downloadServicesExcelTemplate,
                  icon: const Icon(LucideIcons.download, size: 14, color: _kPrimary),
                  label: Text('Template', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kPrimary)),
                ),
              ],
            ),
            content: SingleChildScrollView(
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
                          child: Text('Upload Excel (.xlsx) or CSV file to fill services automatically.', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF1E40AF))),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _importServicesFromExcelOrCsv(setDialogState, rows),
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
                              Text('Service #${idx + 1}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: _kPrimary)),
                              if (rows.length > 1)
                                IconButton(
                                  icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent),
                                  onPressed: () {
                                    setDialogState(() {
                                      rows.removeAt(idx);
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: r['name'],
                            style: GoogleFonts.outfit(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Service Name (e.g. Haircut)',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: r['category'],
                                  style: GoogleFonts.outfit(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Category',
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: r['price'],
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.outfit(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Price',
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
                            'category': TextEditingController(text: 'General'),
                            'price': TextEditingController(),
                          });
                        });
                      },
                      icon: const Icon(LucideIcons.plus, size: 16, color: _kPrimary),
                      label: Text('Add Another Row', style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black45)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final servicesToSave = <Map<String, dynamic>>[];
                  for (var r in rows) {
                    final n = r['name']!.text.trim();
                    final p = double.tryParse(r['price']!.text.trim()) ?? 0.0;
                    final c = r['category']!.text.trim();
                    if (n.isNotEmpty && p > 0) {
                      servicesToSave.add({
                        'name': n,
                        'category': c.isNotEmpty ? c : 'General',
                        'price': p,
                      });
                    }
                  }

                  if (servicesToSave.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Please fill in at least one service name and price.', style: GoogleFonts.outfit(color: Colors.white)),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  try {
                    await ref.read(apiServiceProvider).bulkCreateServices(servicesToSave);
                    ref.invalidate(servicesProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bulk add error: $e')));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Save All', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 20)
                ]),
            child: Icon(LucideIcons.layers,
                size: 64, color: Colors.black.withValues(alpha: 0.1)),
          ),
          const SizedBox(height: 24),
          Text('No services defined',
              style: GoogleFonts.outfit(color: Colors.black26, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Add your salon services to get started',
              style: GoogleFonts.outfit(color: Colors.black12, fontSize: 13)),
        ],
      ),
    );
  }

  void _showAddServiceSheet({Service? service}) {
    final nameController = TextEditingController(text: service?.name);
    final arabicNameController = TextEditingController(text: service?.arabicName);
    final categoryController = TextEditingController(text: service?.category);
    final priceController = TextEditingController(text: service?.price);
    final descriptionController = TextEditingController(text: service?.description);
    bool isPackage = service?.isPackage ?? false;
    List<Map<String, dynamic>> selectedServices = service?.bundledServices?.map((s) => {
      'serviceId': s.id,
      'priceController': TextEditingController(text: s.price),
    }).toList() ?? [];
    final availableServices = ref.read(servicesProvider).value ?? [];
    final currency = ref.read(currencyProvider);
    String bundledSearchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24),
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 24),
                Text(service != null ? 'Edit Service' : 'New Service',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: _kDark)),
                const SizedBox(height: 20),
                Text('Service Type', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setModalState(() => isPackage = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !isPackage ? _kPrimary : Colors.transparent,
                            border: Border.all(color: !isPackage ? _kPrimary : Colors.black12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text('Single Service', style: GoogleFonts.outfit(color: !isPackage ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => setModalState(() => isPackage = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isPackage ? _kPrimary : Colors.transparent,
                            border: Border.all(color: isPackage ? _kPrimary : Colors.black12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text('Service Package', style: GoogleFonts.outfit(color: isPackage ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _field(nameController, 'Service Name (English)', LucideIcons.scissors),
                _field(arabicNameController, 'Service Name (Arabic) صبغة شعر', LucideIcons.languages),
                _field(categoryController, 'Category (e.g. Haircut)',
                    LucideIcons.layers),
                _field(descriptionController, 'Description (optional)',
                    LucideIcons.fileText),
                _field(priceController, 'Price ($currency)', LucideIcons.banknote,
                    type: TextInputType.number),
                
                if (isPackage) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Bundled Services', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: _kDark)),
                      if (selectedServices.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: Text('${selectedServices.length} Selected', style: GoogleFonts.outfit(color: _kPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: _kBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: TextField(
                      onChanged: (val) => setModalState(() => bundledSearchQuery = val),
                      style: GoogleFonts.outfit(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search service to add in package...',
                        hintStyle: GoogleFonts.outfit(color: Colors.black38, fontSize: 13),
                        prefixIcon: const Icon(LucideIcons.search, size: 18, color: _kPrimary),
                        suffixIcon: bundledSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(LucideIcons.x, size: 16, color: Colors.black45),
                                onPressed: () => setModalState(() => bundledSearchQuery = ''),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                    ),
                    child: RawScrollbar(
                      thumbColor: _kPrimary.withValues(alpha: 0.4),
                      radius: const Radius.circular(8),
                      thickness: 5,
                      thumbVisibility: true,
                      child: ListView.builder(
                        itemCount: availableServices.length,
                        itemBuilder: (ctx, i) {
                          final srv = availableServices[i];
                          if (srv.isPackage) return const SizedBox.shrink(); // Nested packages not allowed for now
                          
                          if (bundledSearchQuery.trim().isNotEmpty) {
                            final q = bundledSearchQuery.trim().toLowerCase();
                            final nameMatch = srv.name.toLowerCase().contains(q);
                            final arMatch = srv.arabicName?.toLowerCase().contains(q) ?? false;
                            final catMatch = srv.category.toLowerCase().contains(q);
                            if (!nameMatch && !arMatch && !catMatch) return const SizedBox.shrink();
                          }

                          final selectedItemIdx = selectedServices.indexWhere((item) => item['serviceId'] == srv.id);
                          final isSelected = selectedItemIdx != -1;

                          return ListTile(
                            title: Text(srv.name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${srv.category} • $currency ${srv.price}', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black45)),
                                if (isSelected) ...[
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: selectedServices[selectedItemIdx]['priceController'],
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(
                                      hintText: 'Package Price for ${srv.name}',
                                      prefixIcon: const Icon(LucideIcons.banknote, size: 16, color: _kPrimary),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.black12)),
                                    ),
                                    onChanged: (val) {
                                      double total = 0;
                                      for (var item in selectedServices) {
                                        total += double.tryParse(item['priceController'].text) ?? 0;
                                      }
                                      priceController.text = total.toString();
                                    },
                                  ),
                                ],
                              ],
                            ),
                            trailing: IconButton(
                              icon: Icon(isSelected ? LucideIcons.minusCircle : LucideIcons.plusCircle, color: isSelected ? Colors.redAccent : _kPrimary, size: 24),
                              onPressed: () {
                                setModalState(() {
                                  if (isSelected) {
                                    selectedServices.removeAt(selectedItemIdx);
                                  } else {
                                    selectedServices.add({
                                      'serviceId': srv.id,
                                      'priceController': TextEditingController(text: srv.price),
                                    });
                                  }
                                  double total = 0;
                                  for (var item in selectedServices) {
                                    total += double.tryParse(item['priceController'].text) ?? 0;
                                  }
                                  priceController.text = total.toString();
                                });
                              },
                            ),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isEmpty ||
                          priceController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
                        return;
                      }
                      try {
                        final payload = {
                          'name': nameController.text,
                          'arabicName': arabicNameController.text,
                          'category': categoryController.text,
                          'price': double.parse(priceController.text),
                          'isPackage': isPackage,
                          'bundledServices': selectedServices.map((e) => {
                            'serviceId': e['serviceId'],
                            'price': double.tryParse(e['priceController'].text) ?? 0.0,
                          }).toList(),
                          'description': descriptionController.text,
                        };
                        if (service != null) {
                          await ref.read(apiServiceProvider).updateService(service.id, payload);
                        } else {
                          await ref.read(apiServiceProvider).createService(payload);
                        }
                        ref.invalidate(servicesProvider);
                        ref.invalidate(dashboardMetricsProvider);
                        ref.invalidate(dashboardViewModelProvider);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0),
                    child: Text('Save Service',
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete Service?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: Text(
              'This will permanently remove the service from all menus.',
              style: GoogleFonts.outfit()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.outfit(color: Colors.black38))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(apiServiceProvider).deleteService(id);
                ref.invalidate(servicesProvider);
                ref.invalidate(dashboardMetricsProvider);
                ref.invalidate(dashboardViewModelProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Service deleted')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        style: GoogleFonts.outfit(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon:
              Icon(icon, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
          filled: true,
          fillColor: _kBg,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
        ),
      ),
    );
  }
}
