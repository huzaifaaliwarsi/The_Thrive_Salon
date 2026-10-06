import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/staff_provider.dart';
import '../providers/services_provider.dart';
import '../providers/expenses_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/appointments_provider.dart';
import '../providers/salons_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/clients_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/reports_provider.dart';
import '../providers/logo_provider.dart';
import '../providers/navigation_provider.dart';
import '../view_models/dashboard_view_model.dart';
import '../view_models/pos_view_model.dart';

const _kPrimary = Color(0xFF6A11CB);
const _kDark    = Color(0xFF1B1B3A);

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFDFBF7), Color(0xFFF0EBFF), Color(0xFFE0E7FF)],
                ),
              ),
            ),
          ),
          // Decorative blobs
          Positioned(
            top: -80, right: -80,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kPrimary.withValues(alpha: 0.06),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat()).moveY(begin: -15, end: 15, duration: 4.seconds, curve: Curves.easeInOut),
          Positioned(
            bottom: -100, left: -60,
            child: Container(
              width: 380, height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4AF37).withValues(alpha: 0.06),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat()).moveX(begin: -20, end: 20, duration: 5.seconds, curve: Curves.easeInOut),

          // Login Card
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: _kPrimary.withValues(alpha: 0.08),
                              blurRadius: 40,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [_kPrimary, Color(0xFF2575FC)]),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: _kPrimary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
                              ),
                              child: const Icon(LucideIcons.store, color: Colors.white, size: 32),
                            ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),

                            const SizedBox(height: 20),

                            Text(
                              'Salon Pro',
                              style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.bold, color: _kDark, letterSpacing: 0.5),
                            ).animate().fadeIn(delay: 200.ms),
                            Text(
                              'Management System',
                              style: GoogleFonts.outfit(fontSize: 14, color: Colors.black45),
                            ).animate().fadeIn(delay: 350.ms),

                            const SizedBox(height: 36),

                            // Email
                            _buildField(
                              controller: _emailController,
                              label: 'Email Address',
                              icon: LucideIcons.mail,
                              type: TextInputType.emailAddress,
                            ).animate().slideY(begin: 0.2, duration: 450.ms, curve: Curves.easeOut),

                            const SizedBox(height: 14),

                            // Password
                            _buildField(
                              controller: _passwordController,
                              label: 'Password',
                              icon: LucideIcons.lock,
                              isPassword: true,
                            ).animate().slideY(begin: 0.2, delay: 80.ms, duration: 450.ms, curve: Curves.easeOut),

                            const SizedBox(height: 28),

                            // Login button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [_kPrimary, Color(0xFF2575FC)]),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [BoxShadow(color: _kPrimary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8))],
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                      : Text('Sign In', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                              ),
                            ).animate().scale(delay: 500.ms, duration: 350.ms, curve: Curves.elasticOut),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType? type,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: type,
      style: GoogleFonts.outfit(color: _kDark, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: Colors.black38, fontSize: 14),
        prefixIcon: Icon(icon, color: _kPrimary.withValues(alpha: 0.5), size: 18),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 18, color: Colors.black26),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFFF4F4F8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kPrimary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email and password', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.login(_emailController.text.trim().toLowerCase(), _passwordController.text.trim());

      if (!mounted) return;
      final user = response['user'];
      // Use refreshUser to ensure old cached data is cleared before setting new data
      await ref.read(authProvider.notifier).refreshUser(Map<String, dynamic>.from(user));
      final role = user['role'];

      if (role != 'SUPER_ADMIN' && user['salon'] != null) {
        final salon = user['salon'];
        final subEndStr = salon['subscriptionEnd']?.toString() ?? '';
        final parsedDate = DateTime.tryParse(subEndStr);
        final isLifetime = subEndStr.isEmpty || (parsedDate != null && parsedDate.year >= 2099);
        final subEnd = isLifetime
            ? DateTime(2099, 12, 31)
            : (parsedDate ?? DateTime.now().add(const Duration(days: 30)));
        final isSuspended = salon['isSuspended'] == 'true';
        final isExpired = !isLifetime && subEnd.isBefore(DateTime.now());
        if (isSuspended) throw Exception('Access Suspended. Please contact the administrator.');
        if (isExpired) throw Exception('Subscription Expired. Please contact admin to recharge.');
      }

      // Invalidate all user-specific cached providers to ensure clean state
      ref.invalidate(dashboardViewModelProvider);
      ref.invalidate(dashboardMetricsProvider);
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
      // Navigator handles the transition automatically via AuthWrapper
      // because authState changes in the line above.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
