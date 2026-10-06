import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'dart:convert';
import '../providers/clients_provider.dart';
import '../providers/auth_provider.dart';
import 'ledger_view.dart';

const _kPrimary = Color(0xFF6A11CB);
const _kDark = Color(0xFF1B1B3A);
const _kBg = Color(0xFFF4F6FB);

class ClientsView extends ConsumerStatefulWidget {
  const ClientsView({super.key});

  @override
  ConsumerState<ClientsView> createState() => _ClientsViewState();
}

class _ClientsViewState extends ConsumerState<ClientsView> {
  final _searchController = TextEditingController();
  final Set<String> _selectedClients = {};
  bool _isSelectionMode = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    if (user?['role'] == 'STAFF') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(child: Text('You do not have permission to view clients.')),
      );
    }

    final clientsAsync = ref.watch(clientsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Clientele'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(LucideIcons.messageSquare),
              onPressed: _showBulkMessageDialog,
              tooltip: 'Send Bulk Message',
            ),
            IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () => setState(() {
                _isSelectionMode = false;
                _selectedClients.clear();
              }),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(LucideIcons.fileInput, size: 20),
              onPressed: () async {
                print('[ClientsView] Import button clicked');
                try {
                  await _importClients();
                } catch (e, st) {
                  print('[ClientsView] Error triggered by import button: $e');
                  print(st);
                }
              },
              tooltip: 'Import CSV',
            ),
            IconButton(
              icon: const Icon(LucideIcons.checkSquare, size: 20),
              onPressed: () => setState(() => _isSelectionMode = true),
              tooltip: 'Selection Mode',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search clients by name or phone...',
                prefixIcon: const Icon(LucideIcons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() {}),
            ),
          ),
          Expanded(
            child: clientsAsync.when(
              data: (clients) {
                final filtered = clients.where((c) {
                  final name = c['name']?.toString().toLowerCase() ?? '';
                  final phone = c['phone']?.toString() ?? '';
                  final query = _searchController.text.toLowerCase();
                  return name.contains(query) || phone.contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No clients found'));
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final client = filtered[index];
                    final isSelected = _selectedClients.contains(client['id']);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.withValues(alpha: 0.1),
                          child: Text(
                            client['name']?[0]?.toUpperCase() ?? '?',
                            style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(client['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(client['phone'] ?? 'No phone'),
                                const SizedBox(width: 8),
                                _buildSourceBadge(client['source']),
                              ],
                            ),
                            if (client['balance'] != null && double.parse(client['balance'].toString()) != 0)
                                Text(
                                  'Receivable: PKR ${client['balance']}',
                                style: TextStyle(
                                  color: double.parse(client['balance'].toString()) > 0 ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        trailing: _isSelectionMode
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedClients.add(client['id']);
                                    } else {
                                      _selectedClients.remove(client['id']);
                                    }
                                  });
                                },
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(LucideIcons.messageCircle, color: Colors.green),
                                    onPressed: () => _launchWhatsApp(client['phone']),
                                  ),
                                  IconButton(
                                    icon: const Icon(LucideIcons.edit2, size: 20),
                                    onPressed: () => _showAddEditDialog(client),
                                  ),
                                  IconButton(
                                    icon: const Icon(LucideIcons.book, size: 20, color: Colors.indigo),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LedgerView(
                                          clientId: client['id'],
                                          title: '${client['name']}\'s Ledger',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        onTap: _isSelectionMode
                            ? () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedClients.remove(client['id']);
                                  } else {
                                    _selectedClients.add(client['id']);
                                  }
                                });
                              }
                            : null,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(LucideIcons.plus),
      ),
    );
  }

  Future<void> _importClients() async {
    print('[Import] Method called');
    try {
      print('[Import] Preparing to call FilePicker...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        withData: true,
      );
      print('[Import] File picker result: $result');

      if (result == null || result.files.isEmpty) {
        print('[Import] No file selected');
        return;
      }

      List<List<dynamic>> fields = [];
      try {
        final fileName = result.files.single.name.toLowerCase();
        final bytes = result.files.single.bytes;
        print('[Import] File selected: $fileName (${bytes?.length ?? 0} bytes)');
        if (bytes == null) throw Exception('Could not read file data. Try a smaller file.');

        print('[Import] File selected: $fileName');
        if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
          // Handle Excel files
          try {
            print('[Import] Decoding Excel bytes...');
            final excel = Excel.decodeBytes(bytes);
            print('[Import] Excel decoded. Sheets: ${excel.tables.keys}');
            for (var table in excel.tables.keys) {
              final sheet = excel.tables[table];
              if (sheet != null) {
                print('[Import] Processing sheet: $table (${sheet.maxRows} rows, ${sheet.maxColumns} cols)');
                // Convert Excel rows to dynamic list for processing
                fields = [];
                final maxRows = sheet.maxRows;
                final maxColumns = sheet.maxColumns;
                
                for (int r = 0; r < maxRows; r++) {
                  final List<dynamic> row = [];
                  for (int c = 0; c < maxColumns; c++) {
                    try {
                      row.add(sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value);
                    } catch (e) {
                      print('[Import] Error reading cell ($r, $c): $e');
                      row.add(null);
                    }
                  }
                  fields.add(row);
                }
                if (fields.isNotEmpty) {
                  print('[Import] Successfully read ${fields.length} rows from sheet $table');
                  break; 
                }
              }
            }
          } catch (e) {
             print('[Import] Excel Error: $e');
             throw Exception('Excel decoding failed: $e');
          }
        } else {
          // Handle CSV files
          print('[Import] Decoding CSV bytes...');
          String content;
          try {
            content = utf8.decode(bytes);
          } catch (_) {
            print('[Import] UTF-8 failed, trying Latin-1...');
            try {
              content = latin1.decode(bytes);
            } catch (e) {
               throw Exception('Failed to decode CSV file.');
            }
          }
          fields = const CsvToListConverter().convert(content);
          print('[Import] CSV decoded. Rows: ${fields.length}');
        }
      } catch (e) {
        throw Exception('Failed to read file: $e');
      }

      if (fields.isEmpty) throw Exception('No data found in the selected file');

      // Expected columns: Name, Phone, Email, Notes
      // Skip header if it exists
      int startIdx = 0;
      if (fields.isNotEmpty && fields[0].isNotEmpty && 
          fields[0][0].toString().toLowerCase().contains('name')) {
        startIdx = 1;
      }

      final List<Map<String, dynamic>> clientsToImport = [];
      for (int i = startIdx; i < fields.length; i++) {
        final row = fields[i];
        if (row.isEmpty || row[0] == null || row[0].toString().trim().isEmpty) continue;
        
        clientsToImport.add({
          'name': row[0].toString().trim(),
          'phone': row.length > 1 ? (row[1]?.toString().trim() ?? '') : '',
          'email': row.length > 2 ? (row[2]?.toString().trim() ?? '') : '',
          'notes': row.length > 3 ? (row[3]?.toString().trim() ?? '') : '',
        });
      }

      if (clientsToImport.isEmpty) throw Exception('No valid clients found in the CSV');

      if (!mounted) return;
      
      // Show confirmation
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import Clients'),
          content: Text('Found ${clientsToImport.length} clients in the file. Proceed with import?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
          ],
        ),
      );

      if (confirm != true) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importing clients...')));
      await ref.read(clientsProvider.notifier).bulkAddClients(clientsToImport);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully imported ${clientsToImport.length} clients'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddEditDialog([Map<String, dynamic>? client]) {
    final nameController = TextEditingController(text: client?['name']);
    final phoneController = TextEditingController(text: client?['phone']);
    final emailController = TextEditingController(text: client?['email']);
    final notesController = TextEditingController(text: client?['notes']);
    String selectedSource = client?['source'] ?? 'WALK_IN';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(client == null ? 'Add Client' : 'Edit Client', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark)),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(nameController, 'Name *', LucideIcons.user),
                      _field(phoneController, 'Phone', LucideIcons.phone, type: TextInputType.phone),
                      _field(emailController, 'Email', LucideIcons.mail, type: TextInputType.emailAddress),
                      _field(notesController, 'Notes', LucideIcons.fileText, maxLines: 2),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedSource,
                        style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                        decoration: InputDecoration(
                          labelText: 'How Customer Came',
                          prefixIcon: Icon(LucideIcons.compass, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: _kBg,
                          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'WALK_IN', child: Text('Walk-in')),
                          DropdownMenuItem(value: 'REFERRAL', child: Text('Referral')),
                          DropdownMenuItem(value: 'SOCIAL_MEDIA', child: Text('Social Media')),
                          DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedSource = val;
                            });
                          }
                        },
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
                    if (nameController.text.isEmpty) return;
                    final data = {
                      'name': nameController.text,
                      'phone': phoneController.text,
                      'email': emailController.text,
                      'notes': notesController.text,
                      'source': selectedSource,
                    };
                    try {
                      if (client == null) {
                        await ref.read(clientsProvider.notifier).addClient(data);
                      } else {
                        await ref.read(clientsProvider.notifier).updateClient(client['id'], data);
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
                  child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }
  void _showBulkMessageDialog() {
    final authState = ref.read(authProvider);
    final salonName = authState?['salon']?['name'] ?? 'Salon Pro';
    final messageController = TextEditingController();
    final headerController = TextEditingController(text: salonName);
    final footerController = TextEditingController(text: "Thank you for choosing us! ✨\n*Powered by Salon Pro System*");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Message ${_selectedClients.length} Clients', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WhatsApp requires individual sending. We will guide you through each client.',
                style: GoogleFonts.outfit(fontSize: 13, color: Colors.black45),
              ),
              const SizedBox(height: 20),
              _buildMessageField('Header / Salon Name', headerController, 1),
              const SizedBox(height: 12),
              _buildMessageField('Your Message', messageController, 4, hint: 'Enter your promotion or update...'),
              const SizedBox(height: 12),
              _buildMessageField('Footer', footerController, 2),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              final message = messageController.text;
              final header = headerController.text;
              final footer = footerController.text;
              if (message.isEmpty) return;
              Navigator.pop(context);
              _startMessagingQueue(message, footer, header);
            },
            child: Text('Start Queue', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
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

  void _startMessagingQueue(String message, String footer, String header) {
    final clients = ref.read(clientsProvider).asData?.value ?? [];
    final selectedList = clients.where((c) => _selectedClients.contains(c['id'])).toList();
    int currentIndex = 0;

    final authState = ref.read(authProvider);
    final salonName = authState?['salon']?['name'] ?? 'Salon Pro';
    final fullMessage = "*$header*\n\n$message\n\n$footer";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentClient = selectedList[currentIndex];
          final progress = (currentIndex + 1) / selectedList.length;

          return AlertDialog(
            title: const Text('Sending Progress'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 16),
                Text('Client ${currentIndex + 1} of ${selectedList.length}'),
                Text(
                  currentClient['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(currentClient['phone'] ?? 'No phone'),
                const SizedBox(height: 16),
                const Text(
                  'Click "Send" to open WhatsApp. Once you send the message, return to this app to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _isSelectionMode = false;
                    _selectedClients.clear();
                  });
                },
                child: const Text('Stop'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _launchWhatsApp(currentClient['phone'], fullMessage);
                  if (currentIndex < selectedList.length - 1) {
                    setDialogState(() => currentIndex++);
                  } else {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All messages processed!')),
                    );
                    setState(() {
                      _isSelectionMode = false;
                      _selectedClients.clear();
                    });
                  }
                },
                child: Text(currentIndex < selectedList.length - 1 ? 'Send & Next' : 'Send & Finish'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _launchWhatsApp(String? phone, [String? message]) async {
    if (phone == null || phone.isEmpty) return;
    
    // Clean phone number
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final whatsappUrl = Uri.parse("whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(message ?? '')}");
    
    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl);
    } else {
      // Fallback to web link
      final webUrl = Uri.parse("https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message ?? '')}");
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildSourceBadge(String? source) {
    if (source == null || source.isEmpty) return const SizedBox.shrink();
    
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;
    
    switch (source.toUpperCase()) {
      case 'WALK_IN':
        bgColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        label = 'Walk-in';
        icon = LucideIcons.userCheck;
        break;
      case 'REFERRAL':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        label = 'Referral';
        icon = LucideIcons.users;
        break;
      case 'SOCIAL_MEDIA':
        bgColor = Colors.purple.shade50;
        textColor = Colors.purple.shade700;
        label = 'Social Media';
        icon = LucideIcons.share2;
        break;
      case 'OTHER':
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        label = 'Other';
        icon = LucideIcons.helpCircle;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? type, int? maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        maxLines: maxLines,
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
