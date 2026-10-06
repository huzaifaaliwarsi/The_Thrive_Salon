import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';

class SalonSettingsView extends ConsumerStatefulWidget {
  const SalonSettingsView({super.key});

  @override
  ConsumerState<SalonSettingsView> createState() => _SalonSettingsViewState();
}

class _SalonSettingsViewState extends ConsumerState<SalonSettingsView> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _vatNumberController = TextEditingController();
  final _qrDomainController = TextEditingController(text: 'salonpro.app');
  String? _logoBase64;
  Uint8List? _logoBytes;
  bool _isLoading = false;
  String _timezone = 'Asia/Karachi';

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

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    final user = ref.read(authProvider);
    final salon = user?['salon'];
    if (salon != null) {
      _nameController.text = salon['name'] ?? '';
      _addressController.text = salon['address'] ?? '';
      _vatNumberController.text = salon['vatNumber'] ?? '';
      _qrDomainController.text = salon['qrDomain'] ?? 'salonpro.app';
      _timezone = salon['timezone'] ?? 'Asia/Karachi';
      _logoBase64 = salon['logo'];
      if (_logoBase64 != null && _logoBase64!.startsWith('data:image')) {
        try {
          final base64Str = _logoBase64!.split(',').last;
          _logoBytes = base64.decode(base64Str);
        } catch (e) {
          debugPrint('Error decoding logo: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _vatNumberController.dispose();
    _qrDomainController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (mounted && result != null && result.files.first.bytes != null) {
        final bytes = result.files.first.bytes!;
        final extension = result.files.first.extension ?? 'png';
        setState(() {
          _logoBytes = bytes;
          _logoBase64 = 'data:image/$extension;base64,${base64.encode(bytes)}';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _removeLogo() {
    setState(() {
      _logoBase64 = null;
      _logoBytes = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logo removed. Tap Save Changes to apply.'),
      ),
    );
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(apiServiceProvider).updateSalonSettings({
        'name': _nameController.text,
        'address': _addressController.text,
        'vatNumber': _vatNumberController.text,
        'qrDomain': _qrDomainController.text,
        'logo': _logoBase64,
        'timezone': _timezone,
      });
      
      // Refresh user profile in global state
      final freshUser = await ref.read(apiServiceProvider).getProfile();
      await ref.read(authProvider.notifier).refreshUser(freshUser);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings updated successfully. Please restart the app to see all changes.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Salon Settings', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(60),
                      border: Border.all(color: Colors.black12),
                      image: _logoBytes != null 
                        ? DecorationImage(image: MemoryImage(_logoBytes!), fit: BoxFit.cover)
                        : null,
                    ),
                    child: _logoBytes == null 
                      ? const Icon(LucideIcons.image, size: 40, color: Colors.black26)
                      : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: FloatingActionButton.small(
                      onPressed: _isLoading ? null : _pickLogo,
                      tooltip: 'Upload logo',
                      backgroundColor: const Color(0xFF6366F1),
                      child: const Icon(LucideIcons.camera, size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            if (_logoBase64?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: _isLoading ? null : _removeLogo,
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: Text('Remove logo',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            Text('Salon Name', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Enter salon name',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            Text('Tax Number', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _vatNumberController,
              decoration: InputDecoration(
                hintText: 'Enter Tax Number (e.g. 3121252266700003)',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            Text('Address', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter salon address',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 24),
            Text('Salon Timezone', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _timezone,
                  isExpanded: true,
                  items: _timezones.map((tz) => DropdownMenuItem(value: tz, child: Text(tz, style: GoogleFonts.outfit(fontSize: 15)))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _timezone = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text('Save Changes', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            _buildZktecoIntegrationSection(),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            Text('Advanced Maintenance', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.redAccent)),
            const SizedBox(height: 8),
            Text(
              'If your Dashboard Cash Drawer balance appears out of sync, use this tool to mathematically recalculate it from all historical transactions.',
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Recalculate Cash Drawer?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      content: Text('This will recalculate your cash drawer balance based on all historical cash flows. Continue?', style: GoogleFonts.outfit()),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          child: const Text('Recalculate', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && mounted) {
                    setState(() => _isLoading = true);
                    try {
                      await ref.read(apiServiceProvider).recalculateCashDrawer();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cash Drawer recalculated successfully')));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                label: Text('Recalculate Cash Drawer', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZktecoIntegrationSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(apiServiceProvider).getZktecoConfig(),
      builder: (context, snapshot) {
        final config = snapshot.data ?? {};
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final isEnabled = config['enabled'] == true;
        final deviceSn = config['deviceSn']?.toString() ?? '';
        final lastSync = config['lastSync']?.toString();
        final staffEnrollments = (config['staffEnrollments'] as List<dynamic>?) ?? [];

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.fingerprint, color: Color(0xFF8B5CF6), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ZKTeco Biometric Machine Integration', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B))),
                        Text('Real-time biometric attendance sync for this branch', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45)),
                      ],
                    ),
                  ),
                  if (isEnabled)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('Active & Synced', style: GoogleFonts.outfit(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Connect your standalone ZKTeco fingerprint or facial device (K40, UFace, MB20, etc.) on Namecheap Stellar Plus hosting via Cloud ADMS (Port 443 / HTTPS) or Local Network Sync.',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 16),
              
              // Device Details
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                ),
                child: Column(
                  children: [
                    _buildConfigRow('Device Serial Number (SN)', deviceSn.isNotEmpty ? deviceSn : 'Not Registered', LucideIcons.cpu, copyable: deviceSn.isNotEmpty),
                    const Divider(height: 16),
                    _buildConfigRow('Server Host / Domain', Uri.tryParse(ApiConfig.baseUrl)?.host.isNotEmpty == true ? Uri.tryParse(ApiConfig.baseUrl)!.host : 'localhost', LucideIcons.globe, copyable: true),
                    const Divider(height: 16),
                    _buildConfigRow('Server Port', (Uri.tryParse(ApiConfig.baseUrl)?.hasPort == true) ? Uri.tryParse(ApiConfig.baseUrl)!.port.toString() : ((Uri.tryParse(ApiConfig.baseUrl)?.scheme == 'https') ? '443 (HTTPS)' : '80 (HTTP)'), LucideIcons.shieldCheck, copyable: true),
                    const Divider(height: 16),
                    _buildConfigRow('Cloud Push URL', '${ApiConfig.baseUrl}/api/zkteco/iclock/cdata', LucideIcons.link, copyable: true),
                    if (lastSync != null) ...[
                      const Divider(height: 16),
                      _buildConfigRow('Last Biometric Punch', lastSync.replaceAll('T', ' ').substring(0, 19), LucideIcons.clock, copyable: false),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Staff Enrollment Matrix
              Text('Staff Machine Enrollment Roster (Biometric PINs):', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 8),
              if (staffEnrollments.isEmpty)
                Text('No staff members registered in this salon yet.', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black38))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: staffEnrollments.map((st) {
                    final pin = st['biometricPin']?.toString() ?? 'Auto';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.user, size: 12, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text('${st['name']}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('PIN #$pin', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),

              // Edit Device Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showEditZktecoDialog(config),
                  icon: const Icon(LucideIcons.settings, size: 16),
                  label: Text('Configure ZKTeco Device SN & Token', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8B5CF6),
                    side: const BorderSide(color: Color(0xFF8B5CF6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConfigRow(String title, String value, IconData icon, {bool copyable = false}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF8B5CF6)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.outfit(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.w500)),
              Text(value, style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF1E293B), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        if (copyable)
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 14, color: Colors.black38),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied $title to clipboard!'), duration: const Duration(seconds: 2)),
              );
            },
          ),
      ],
    );
  }

  void _showEditZktecoDialog(Map<String, dynamic> config) {
    final snCtrl = TextEditingController(text: config['deviceSn']?.toString() ?? '');
    final nameCtrl = TextEditingController(text: config['deviceName']?.toString() ?? 'ZKTeco K40');
    bool enabled = config['enabled'] == true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(LucideIcons.fingerprint, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 10),
              Text('ZKTeco Machine Setup', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: snCtrl,
                    decoration: InputDecoration(
                      labelText: 'Device Serial Number (SN)',
                      hintText: 'e.g. CKT821947291',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(LucideIcons.cpu, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Device Name',
                      hintText: 'e.g. Main Entrance Biometric',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(LucideIcons.tag, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text('Enable Biometric Sync', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('Automatically log attendance punches from this device', style: GoogleFonts.outfit(fontSize: 11)),
                    value: enabled,
                    activeColor: const Color(0xFF8B5CF6),
                    onChanged: (val) => setDialogState(() => enabled = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () async {
                try {
                  await ref.read(apiServiceProvider).updateZktecoConfig({
                    'deviceSn': snCtrl.text.trim(),
                    'deviceName': nameCtrl.text.trim(),
                    'enabled': enabled,
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ZKTeco device settings updated!')));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: Text('Save Settings', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

