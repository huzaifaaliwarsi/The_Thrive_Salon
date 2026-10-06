import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../providers/appointments_provider.dart';
import '../providers/staff_provider.dart';
import '../providers/services_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/clients_provider.dart';
import '../models/service_model.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';

const _kPrimary  = Color(0xFF6A11CB);
const _kDark     = Color(0xFF1B1B3A);
const _kBg       = Color(0xFFF4F6FB);
const _kAccent   = Color(0xFF2575FC);

class AppointmentsView extends ConsumerStatefulWidget {
  const AppointmentsView({super.key});

  @override
  ConsumerState<AppointmentsView> createState() => _AppointmentsViewState();
}

class _AppointmentsViewState extends ConsumerState<AppointmentsView> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isCalendarVisible = false;
  String? _filterStaffId;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    final appointmentsAsync = ref.watch(appointmentsProvider);
    final user = ref.watch(authProvider);
    final isStaff = user?['role'] == 'STAFF';
    final staffListAsync = ref.watch(staffProvider);

    // Find myStaffId
    String? myStaffId;
    if (isStaff && staffListAsync.hasValue) {
      final myStaff = staffListAsync.value!.cast<dynamic>().firstWhere(
        (s) => s['userId'] == user?['id'] || s['user']?['id'] == user?['id'],
        orElse: () => null,
      );
      if (myStaff != null) {
        myStaffId = myStaff['id']?.toString();
      }
    }

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick View', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w500)),
            Text(ref.watch(authProvider)?['salon']?['name'] ?? 'Appointments', 
                 style: GoogleFonts.outfit(color: _kDark, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: Icon(_isCalendarVisible ? LucideIcons.list : LucideIcons.calendar, size: 18, color: _kPrimary),
            label: Text(
              _isCalendarVisible ? 'Show List' : 'Show Calendar',
              style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            onPressed: () => setState(() => _isCalendarVisible = !_isCalendarVisible),
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20, color: Colors.black26),
            onPressed: () => ref.invalidate(appointmentsProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: appointmentsAsync.when(
        data: (appointments) {
          final filteredAppointments = appointments.where((a) {
            final dateStr = a['appointmentTime'] ?? a['date'];
            var date = DateTime.tryParse(dateStr?.toString() ?? '');
            if (date == null) return false;
            if (a['appointmentTime'] != null) {
              date = date.toLocal();
            }
            final isSameDate = isSameDay(date, _selectedDay);
            if (!isSameDate) return false;
            if (isStaff && myStaffId != null) {
              final sdStr = a['serviceDetails']?.toString() ?? '';
              return a['staffId'] == myStaffId || sdStr.contains(myStaffId);
            } else if (!isStaff && _filterStaffId != null) {
              final sdStr = a['serviceDetails']?.toString() ?? '';
              return a['staffId'] == _filterStaffId || sdStr.contains(_filterStaffId!);
            }
            return true;
          }).toList();

          return Column(
            children: [
              _buildCalendar(appointments, isStaff, myStaffId),
              if (!isStaff) _buildStaffFilter(context, ref),
              Expanded(
                child: filteredAppointments.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: filteredAppointments.length,
                        itemBuilder: (context, index) => _AppointmentCard(appointment: filteredAppointments[index], index: index),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: _kPrimary)),
        error: (e, _) => Center(child: Text('Error: $e', style: GoogleFonts.outfit())),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBookingSheet(context),
        backgroundColor: _kPrimary,
        elevation: 4,
        icon: const Icon(LucideIcons.calendarPlus, color: Colors.white, size: 20),
        label: Text('New Booking', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
      ).animate().scale(delay: 300.ms, curve: Curves.easeOutBack),
    );
  }

  void _showBookingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const BookingSheet(),
    ).then((_) => ref.invalidate(appointmentsProvider));
  }

  Widget _buildCalendar(List<dynamic> appointments, bool isStaff, String? myStaffId) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: TableCalendar(
        firstDay: DateTime.now().subtract(const Duration(days: 365)),
        lastDay: DateTime.now().add(const Duration(days: 365)),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        calendarFormat: _isCalendarVisible ? CalendarFormat.month : CalendarFormat.week,
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        eventLoader: (day) {
          return appointments.where((a) {
            final dateStr = a['appointmentTime'] ?? a['date'];
            var date = DateTime.tryParse(dateStr?.toString() ?? '');
            if (date == null) return false;
            if (a['appointmentTime'] != null) {
              date = date.toLocal();
            }
            final isMatch = isSameDay(date, day);
            if (!isMatch) return false;
            if (isStaff && myStaffId != null) {
              final sdStr = a['serviceDetails']?.toString() ?? '';
              return a['staffId'] == myStaffId || sdStr.contains(myStaffId);
            } else if (!isStaff && _filterStaffId != null) {
              final sdStr = a['serviceDetails']?.toString() ?? '';
              return a['staffId'] == _filterStaffId || sdStr.contains(_filterStaffId!);
            }
            return true;
          }).toList();
        },
        calendarStyle: CalendarStyle(
          selectedDecoration: const BoxDecoration(color: _kPrimary, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.1), shape: BoxShape.circle),
          todayTextStyle: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.bold),
          defaultTextStyle: GoogleFonts.outfit(),
          weekendTextStyle: GoogleFonts.outfit(color: Colors.redAccent),
          markerDecoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
          markersMaxCount: 3,
          outsideDaysVisible: false,
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20)]),
            child: Icon(LucideIcons.calendarX, size: 64, color: Colors.black.withValues(alpha: 0.1)),
          ),
          const SizedBox(height: 24),
          Text('No appointments scheduled', style: GoogleFonts.outfit(color: Colors.black26, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Tap the button below to add one', style: GoogleFonts.outfit(color: Colors.black12, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStaffFilter(BuildContext context, WidgetRef ref) {
    final staffListAsync = ref.watch(staffProvider);
    return staffListAsync.when(
      data: (staffList) {
        if (staffList.isEmpty) return const SizedBox.shrink();
        return Container(
          height: 48,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text('All Staff', style: GoogleFonts.outfit(fontSize: 12, fontWeight: _filterStaffId == null ? FontWeight.bold : FontWeight.normal)),
                  selected: _filterStaffId == null,
                  onSelected: (val) {
                    setState(() {
                      _filterStaffId = null;
                    });
                  },
                  selectedColor: _kPrimary.withValues(alpha: 0.2),
                  checkmarkColor: _kPrimary,
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _filterStaffId == null ? _kPrimary : Colors.black12)),
                ),
              ),
              ...staffList.map((s) {
                final isSelected = _filterStaffId == s.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(s.name, style: GoogleFonts.outfit(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        _filterStaffId = val ? s.id : null;
                      });
                    },
                    selectedColor: _kPrimary.withValues(alpha: 0.2),
                    checkmarkColor: _kPrimary,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? _kPrimary : Colors.black12)),
                  ),
                );
              }),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _AppointmentCard extends ConsumerWidget {
  final dynamic appointment;
  final int index;
  const _AppointmentCard({required this.appointment, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = DateTime.parse(appointment['appointmentTime']).toLocal();
    final isPending = appointment['status'] == 'PENDING';
    final statusColor = _getStatusColor(appointment['status']);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_kPrimary.withValues(alpha: 0.1), _kAccent.withValues(alpha: 0.1)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.user, size: 20, color: _kPrimary),
          ),
          title: Text(appointment['customerName'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kDark, fontSize: 16)),
          subtitle: Row(
            children: [
              const Icon(LucideIcons.clock, size: 12, color: Colors.black26),
              const SizedBox(width: 4),
              Text(
                DateFormat('hh:mm a • MMM dd').format(time),
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(
              appointment['status'],
              style: GoogleFonts.outfit(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  const Divider(height: 20, color: Color(0xFFF4F6FB)),
                  _infoRow(LucideIcons.phone, appointment['customerPhone'] ?? 'No phone'),
                  const SizedBox(height: 8),
                  _infoRow(
                    LucideIcons.scissors, 
                    'Services: ${(() {
                      final List<dynamic>? resolvedServices = appointment['services'] as List<dynamic>?;
                      if (resolvedServices != null && resolvedServices.isNotEmpty) {
                        return resolvedServices.map((s) => s['name'] ?? '').join(', ');
                      }
                      return appointment['service']?['name'] ?? 'N/A';
                    })()}',
                  ),
                  const SizedBox(height: 8),
                  _infoRow(LucideIcons.userCheck, 'Assigned: ${(() {
                    final staffNameSet = <String>{};
                    if (appointment['staff']?['name'] != null && appointment['staff']['name'].toString().isNotEmpty) {
                      staffNameSet.add(appointment['staff']['name'].toString());
                    }
                    try {
                      final sdRaw = appointment['serviceDetails'];
                      if (sdRaw != null) {
                        List<dynamic>? sdList;
                        if (sdRaw is List) {
                          sdList = sdRaw;
                        } else if (sdRaw is String && sdRaw.trim().startsWith('[')) {
                          sdList = jsonDecode(sdRaw);
                        }
                        if (sdList != null) {
                          for (var item in sdList) {
                            final sName = item['staffName']?.toString();
                            if (sName != null && sName.isNotEmpty && sName != 'Unassigned') {
                              staffNameSet.add(sName);
                            }
                          }
                        }
                      }
                    } catch (_) {}
                    return staffNameSet.isNotEmpty ? staffNameSet.join(', ') : 'Unassigned';
                  })()}'),
                  if (appointment['notes'] != null && appointment['notes'].isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _infoRow(LucideIcons.fileText, appointment['notes']),
                  ],
                  const SizedBox(height: 20),
                  _buildActions(context, ref, appointment, isPending),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (index * 60).ms).slideY(begin: 0.1);
  }

  Widget _buildActions(BuildContext context, WidgetRef ref, dynamic appointment, bool isPending) {
    final role = ref.watch(authProvider)?['role'];
    final isStaff = role == 'STAFF';
    final isOwner = role == 'OWNER' || role == 'SUPER_ADMIN';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () => _showShareCustomDialog(context, ref, appointment),
            icon: const Icon(LucideIcons.share2, size: 16, color: Colors.green),
            label: Text('Share via WhatsApp', style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.green),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (appointment['staffId'] == null && isStaff)
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _claimAppointment(context, ref, appointment['id']),
              icon: const Icon(LucideIcons.hand, size: 16, color: Colors.white),
              label: Text('Claim & Confirm', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        if (isPending && (appointment['staffId'] != null || isOwner))
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _updateStatus(context, ref, appointment['id'], 'CANCELLED'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _updateStatus(context, ref, appointment['id'], 'CONFIRMED'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: Text('Confirm', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        if (appointment['status'] == 'CONFIRMED' || appointment['status'] == 'PENDING') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => BookingSheet(appointment: appointment),
                    ).then((_) => ref.invalidate(appointmentsProvider));
                  },
                  icon: const Icon(LucideIcons.calendarClock, size: 16, color: _kPrimary),
                  label: Text('Reschedule', style: GoogleFonts.outfit(color: _kPrimary, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      // Mark appointment as PENDING_CHECKOUT in backend
                      await ref.read(apiServiceProvider).updateAppointmentStatus(
                        appointment['id'].toString(),
                        'PENDING_CHECKOUT',
                      );
                      ref.invalidate(appointmentsProvider);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.teal,
                            content: Text(
                              "Appointment checked out! Sent to Owner's POS Queue for final processing.",
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red,
                            content: Text("Failed to check out: $e"),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(LucideIcons.shoppingBag, size: 16, color: Colors.white),
                  label: Text('Checkout', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _kPrimary.withValues(alpha: 0.5)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: GoogleFonts.outfit(fontSize: 13, color: _kDark.withValues(alpha: 0.7)))),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING': return Colors.orange;
      case 'CONFIRMED': return _kAccent;
      case 'COMPLETED': return Colors.green;
      case 'CANCELLED': return Colors.red;
      default: return Colors.grey;
    }
  }

  void _claimAppointment(BuildContext context, WidgetRef ref, String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      final staff = await api.getStaff();
      final user = ref.read(authProvider);
      final myProfile = staff.firstWhere((s) => s['userId'] == user?['id']);
      
      await api.updateAppointmentStatus(id, 'CONFIRMED', staffId: myProfile['id']);
      ref.invalidate(appointmentsProvider);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment claimed!')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _updateStatus(BuildContext context, WidgetRef ref, String id, String status) async {
    try {
      await ref.read(apiServiceProvider).updateAppointmentStatus(id, status);
      ref.invalidate(appointmentsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showShareCustomDialog(BuildContext context, WidgetRef ref, dynamic appointment) {
    final authState = ref.read(authProvider);
    final salonName = authState?['salon']?['name'] ?? 'Salon Pro';
    final salonAddress = authState?['salon']?['address'] ?? '';

    final time = DateTime.parse(appointment['appointmentTime']).toLocal();
    final formattedTime = DateFormat('hh:mm a • MMM dd, yyyy').format(time);
    final List<dynamic>? resolvedServices = appointment['services'] as List<dynamic>?;
    final serviceName = resolvedServices != null && resolvedServices.isNotEmpty
        ? resolvedServices.map((s) => s['name'] ?? '').join(', ')
        : (appointment['service']?['name'] ?? 'Service');
    final staffName = appointment['staff']?['name'] ?? 'Unassigned';

    String appointmentBody = "Customer: ${appointment['customerName']}\n"
        "Service: $serviceName\n"
        "Staff: $staffName\n"
        "Time: $formattedTime\n"
        "Status: ${appointment['status']}";

    final messageController = TextEditingController(text: "We look forward to seeing you!");
    final headerController = TextEditingController(text: salonName);
    final footerController = TextEditingController(text: "Thank you for choosing us! ✨\n*Powered by Salon Pro System*");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Customize Message', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
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
              const Text('Appointment Details:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text(appointmentBody, style: const TextStyle(fontSize: 11, color: Colors.black54)),
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
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final header = headerController.text;
              final fullMessage = "*$header*\n" + 
                                  (salonAddress.isNotEmpty ? "📍 $salonAddress\n" : "") +
                                  "\n*Appointment Details*\n$appointmentBody\n\n" +
                                  "${messageController.text}\n\n" +
                                  "${footerController.text}";
              
              Navigator.pop(context);
              await _shareAppointmentMessage(appointment, fullMessage);
            },
            child: const Text('Share to WhatsApp'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareAppointmentMessage(dynamic appointment, String message) async {
    String phone = appointment['customerPhone']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (phone.startsWith('0') && phone.length == 11) {
      phone = '92${phone.substring(1)}';
    }
    if (phone.isNotEmpty) {
      final urlStr = "https://wa.me/$phone?text=${Uri.encodeComponent(message)}";
      final uri = Uri.parse(urlStr);
      try {
        final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (success) return;
      } catch (_) {}
    }
    
    await Share.share(message, subject: 'Salon Appointment');
  }
}

class BookingSheet extends ConsumerStatefulWidget {
  final dynamic appointment;
  const BookingSheet({super.key, this.appointment});

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<BookingSheet> {
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _notes = TextEditingController();
  final List<String> _selectedServiceIds = [];
  final Map<String, String?> _serviceStaffMap = {};
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    final app = widget.appointment;
    if (app != null) {
      _customerName.text = app['customerName'] ?? '';
      _customerPhone.text = app['customerPhone'] ?? '';
      _notes.text = app['notes'] ?? '';
      if (app['appointmentTime'] != null) {
        final parsed = DateTime.tryParse(app['appointmentTime'].toString())?.toLocal();
        if (parsed != null) {
          _selectedDate = parsed;
          _selectedTime = TimeOfDay.fromDateTime(parsed);
        }
      }
      if (app['services'] != null) {
        for (var s in app['services']) {
          final sId = s['id']?.toString() ?? '';
          _selectedServiceIds.add(sId);
        }
      } else if (app['serviceId'] != null) {
        _selectedServiceIds.add(app['serviceId'].toString());
      }
      if (app['serviceDetails'] != null) {
        try {
          final List<dynamic> details = app['serviceDetails'] is String ? jsonDecode(app['serviceDetails']) : app['serviceDetails'];
          for (var item in details) {
            final pkgId = item['packageId']?.toString();
            final srvId = item['serviceId'].toString();
            final staffId = item['staffId']?.toString();
            if (pkgId != null && pkgId != 'null') {
              _serviceStaffMap['${pkgId}_$srvId'] = staffId;
            } else {
              _serviceStaffMap[srvId] = staffId;
            }
          }
        } catch (_) {}
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final user = ref.read(authProvider);
        if (user?['role'] == 'STAFF') {
          final staffList = ref.read(staffProvider).value ?? [];
          final myStaff = staffList.cast<dynamic>().firstWhere(
            (s) => s['userId'] == user?['id'] || s['user']?['id'] == user?['id'],
            orElse: () => null,
          );
          if (myStaff != null) {
            // No global staff id anymore
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _customerName.dispose();
    _customerPhone.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(servicesProvider);
    final staffAsync = ref.watch(staffProvider);

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Text(widget.appointment != null ? 'Reschedule Appointment' : 'New Booking', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22, color: _kDark)),
            const SizedBox(height: 20),
            _field(_customerName, 'Customer Name', LucideIcons.user, suffix: IconButton(
              icon: const Icon(LucideIcons.search, size: 18, color: _kPrimary),
              onPressed: _showClientSearchDialog,
            )),
            _field(_customerPhone, 'Phone Number', LucideIcons.phone, type: TextInputType.phone),
            _buildExistingClientSelector(),
            const SizedBox(height: 12),
            servicesAsync.when(
              data: (allServices) {
                final services = allServices.where((s) => !s.id.startsWith('inv_') && s.category != 'INVENTORY').toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Services', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _showServicesMultiSelect(context, services),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FD),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.scissors, size: 18, color: _kPrimary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _selectedServiceIds.isEmpty
                                    ? 'Select Services (Tap to Choose)'
                                    : services
                                        .where((s) => _selectedServiceIds.contains(s.id))
                                        .map((s) => s.name)
                                        .join(', '),
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  color: _selectedServiceIds.isEmpty ? Colors.black38 : _kDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(LucideIcons.chevronRight, size: 16, color: Colors.black26),
                          ],
                        ),
                      ),
                    ),
                    if (_selectedServiceIds.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ..._selectedServiceIds.expand((id) {
                        final s = services.firstWhere((srv) => srv.id == id, orElse: () => Service(id: '', name: 'Unknown', price: '0', category: '', duration: 0));
                        
                        Widget buildDropdown(String itemName, String mapKey) {
                          final user = ref.watch(authProvider);
                          final isStaff = user?['role'] == 'STAFF';
                          final staffList = staffAsync.value ?? [];
                          final myProfile = isStaff ? staffList.cast<dynamic>().firstWhere(
                            (st) => (st is Map ? st['userId'] : st.userId) == user?['id'],
                            orElse: () => null,
                          ) : null;
                          final myStaffId = myProfile != null ? (myProfile is Map ? myProfile['id']?.toString() : myProfile.id?.toString()) : null;

                          if (isStaff && myStaffId != null) {
                            _serviceStaffMap[mapKey] = myStaffId;
                          }

                          final filteredStaff = isStaff && myStaffId != null
                              ? staffList.where((st) => (st is Map ? st['id']?.toString() : st.id?.toString()) == myStaffId).toList()
                              : staffList;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFFF8F9FD), borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                Expanded(flex: 2, child: Text(itemName, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: _kDark))),
                                Expanded(
                                  flex: 3,
                                  child: staffAsync.when(
                                    data: (_) => Container(
                                      height: 36,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _serviceStaffMap[mapKey],
                                          isExpanded: true,
                                          icon: const Icon(LucideIcons.chevronDown, size: 14),
                                          hint: Text('Assign Staff', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black38)),
                                          items: filteredStaff.map((st) {
                                            final id = st is Map ? st['id']?.toString() : st.id?.toString();
                                            final name = st is Map ? st['name']?.toString() : st.name?.toString();
                                            return DropdownMenuItem<String>(value: id, child: Text(name ?? 'Staff', style: GoogleFonts.outfit(fontSize: 13)));
                                          }).toList(),
                                          onChanged: isStaff ? null : (v) => setState(() => _serviceStaffMap[mapKey] = v),
                                        ),
                                      ),
                                    ),
                                    loading: () => const SizedBox(),
                                    error: (_, __) => const SizedBox(),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedServiceIds.remove(s.id);
                                      if (s.isPackage && s.bundledServices != null) {
                                        for (var bs in s.bundledServices!) {
                                          _serviceStaffMap.remove('${s.id}_${bs.id}');
                                        }
                                      } else {
                                        _serviceStaffMap.remove(s.id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(LucideIcons.trash2, size: 14, color: Colors.redAccent),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        if (s.isPackage && s.bundledServices != null && s.bundledServices!.isNotEmpty) {
                          return [
                            Container(
                              margin: const EdgeInsets.only(bottom: 6, top: 4),
                              child: Row(
                                children: [
                                  const Icon(LucideIcons.package, size: 14, color: _kPrimary),
                                  const SizedBox(width: 6),
                                  Text('${s.name} (Package)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: _kPrimary)),
                                ],
                              ),
                            ),
                            ...s.bundledServices!.map((bs) => buildDropdown(bs.name, '${s.id}_${bs.id}'))
                          ];
                        } else {
                          return [buildDropdown(s.name, s.id)];
                        }
                      }),
                    ],
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Error loading services'),
            ),
            Row(
              children: [
                Expanded(child: _pickerBox(LucideIcons.calendar, DateFormat('MMM dd').format(_selectedDate), _pickDate)),
                const SizedBox(width: 12),
                Expanded(child: _pickerBox(LucideIcons.clock, _selectedTime.format(context), _pickTime)),
              ],
            ),
            const SizedBox(height: 12),
            _field(_notes, 'Notes (Optional)', LucideIcons.fileText, maxLines: 2),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                child: Text(widget.appointment != null ? 'Reschedule' : 'Create Booking', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType? type, int maxLines = 1, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        maxLines: maxLines,
        style: GoogleFonts.outfit(fontSize: 14),
        decoration: _inputDeco(label, icon).copyWith(suffixIcon: suffix),
      ),
    );
  }

  Widget _dropdown(String label, String? value, List<DropdownMenuItem<String>> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      style: GoogleFonts.outfit(fontSize: 14, color: _kDark),
      decoration: _inputDeco(label, LucideIcons.layers),
    );
  }

  Widget _pickerBox(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(color: const Color(0xFFF8F9FD), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _kPrimary),
            const SizedBox(width: 10),
            Text(label, style: GoogleFonts.outfit(fontSize: 14, color: _kDark)),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 18, color: _kPrimary.withValues(alpha: 0.5)),
    filled: true,
    fillColor: const Color(0xFFF8F9FD),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    labelStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.black38),
  );

  void _pickDate() async {
    final date = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date != null) setState(() => _selectedDate = date);
  }

  void _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _selectedTime);
    if (time != null) setState(() => _selectedTime = time);
  }

  Widget _buildExistingClientSelector() {
    final clientsAsync = ref.watch(clientsProvider);
    return clientsAsync.when(
      data: (clients) {
        if (clients.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Or Select Existing Client:', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black45)),
              const SizedBox(height: 6),
              Container(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: clients.length,
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(client['name'], style: GoogleFonts.outfit(fontSize: 11)),
                        onPressed: () {
                          setState(() {
                            _customerName.text = client['name'];
                            _customerPhone.text = client['phone'] ?? '';
                          });
                        },
                        backgroundColor: _kPrimary.withValues(alpha: 0.05),
                        side: BorderSide(color: _kPrimary.withValues(alpha: 0.1)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showServicesMultiSelect(BuildContext context, List<Service> services) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  Text('Select Services', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: services.length,
                      itemBuilder: (context, index) {
                        final service = services[index];
                        final isSelected = _selectedServiceIds.contains(service.id);
                        return CheckboxListTile(
                          title: Text(service.name, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                          subtitle: Text('PKR ${service.price}', style: GoogleFonts.outfit(fontSize: 12)),
                          value: isSelected,
                          activeColor: _kPrimary,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                _selectedServiceIds.add(service.id);
                              } else {
                                _selectedServiceIds.remove(service.id);
                                if (service.isPackage && service.bundledServices != null) {
                                  for (var s in service.bundledServices!) {
                                    _serviceStaffMap.remove('${service.id}_${s.id}');
                                  }
                                } else {
                                  _serviceStaffMap.remove(service.id);
                                }
                              }
                            });
                            setState(() {});
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Done', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _submit() async {
    if (_customerName.text.isEmpty || _selectedServiceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer Name and at least one Service are required', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
      return;
    }
    final appointmentTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute);
    if (appointmentTime.isBefore(DateTime.now().subtract(const Duration(minutes: 5)))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment time must be in the future', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
      return;
    }
    try {
      final services = ref.read(servicesProvider).value ?? [];
      
      final payload = {
        'customerName': _customerName.text,
        'customerPhone': _customerPhone.text,
        'serviceIds': _selectedServiceIds,
        'serviceDetails': _selectedServiceIds.expand((id) {
          final s = services.firstWhere((srv) => srv.id == id, orElse: () => Service(id: '', name: '', price: '0', category: '', duration: 0));
          final staffList = ref.read(staffProvider).value ?? [];
          if (s.isPackage && s.bundledServices != null && s.bundledServices!.isNotEmpty) {
            return s.bundledServices!.map((bs) {
              final stId = _serviceStaffMap['${s.id}_${bs.id}'];
              final stObj = staffList.firstWhere((st) => (st is Map ? st['id']?.toString() : st.id?.toString()) == stId, orElse: () => null);
              final stName = stObj != null ? (stObj is Map ? stObj['name'] : stObj.name) : null;
              return {'serviceId': bs.id, 'serviceName': bs.name, 'staffId': stId, 'staffName': stName, 'packageId': s.id};
            });
          }
          final stId = _serviceStaffMap[id];
          final stObj = staffList.firstWhere((st) => (st is Map ? st['id']?.toString() : st.id?.toString()) == stId, orElse: () => null);
          final stName = stObj != null ? (stObj is Map ? stObj['name'] : stObj.name) : null;
          return [{'serviceId': id, 'serviceName': s.name, 'staffId': stId, 'staffName': stName}];
        }).toList(),
        'staffId': null,
        'appointmentTime': appointmentTime.toUtc().toIso8601String(),
        'notes': _notes.text,
      };

      if (widget.appointment != null) {
        await ref.read(apiServiceProvider).updateAppointment(widget.appointment['id'], payload);
      } else {
        await ref.read(apiServiceProvider).createAppointment(payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showClientSearchDialog() {
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
                              onTap: () {
                                setState(() {
                                  _customerName.text = client['name'];
                                  _customerPhone.text = client['phone'] ?? '';
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
