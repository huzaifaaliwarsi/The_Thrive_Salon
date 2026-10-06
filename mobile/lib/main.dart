import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Add this for kIsWeb
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'repositories/sync_repository.dart';
import 'views/login_view.dart';
import 'views/dashboard_view.dart';
import 'views/super_admin_dashboard.dart';
import 'views/public_invoice_view.dart';
import 'providers/auth_provider.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Background isolate needs its own initialization
      WidgetsFlutterBinding.ensureInitialized();
      await Hive.initFlutter();
      await Hive.openBox('auth');
      
      final container = ProviderContainer();
      await container.read(syncRepositoryProvider).syncPendingChanges();
      return true;
    } catch (e) {
      debugPrint('Background Sync Error: $e');
      return false;
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Add Global Error Handling
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('GLOBAL FLUTTER ERROR: ${details.exception}');
    debugPrint('STACK TRACE: ${details.stack}');
  };
  
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('GLOBAL PLATFORM ERROR: $error');
    debugPrint('STACK TRACE: $stack');
    return true;
  };

  // Initialize Hive
  await Hive.initFlutter();
  await Hive.openBox('auth');
  
  // Initialize Workmanager for background sync
  if (!kIsWeb) {
    Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    Workmanager().registerPeriodicTask(
      "1", 
      "syncTask", 
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
  }

  runApp(const ProviderScope(child: SalonApp()));
}

class SalonApp extends StatelessWidget {
  const SalonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Salon Management System',
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A11CB),
          primary: const Color(0xFF6A11CB),
          secondary: const Color(0xFFD4AF37),
          surface: const Color(0xFFFDFBF7),
          onSurface: const Color(0xFF1B1B3A),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFDFBF7),
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const LoginView(),
      },
      onGenerateRoute: (settings) {
        if (settings.name != null && settings.name!.startsWith('/invoice/')) {
          final uri = Uri.parse(settings.name!);
          final invoiceId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
          final verifyHash = uri.queryParameters['verify'];
          if (invoiceId != null && invoiceId.isNotEmpty) {
            return MaterialPageRoute(
              builder: (context) => PublicInvoiceView(
                invoiceId: invoiceId,
                verifyHash: verifyHash,
              ),
            );
          }
        }
        return null;
      },
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    if (authState != null) {
      if (authState['role'] == 'SUPER_ADMIN') {
        return const SuperAdminDashboard();
      } else {
        return const DashboardView();
      }
    }
    
    return const LoginView();
  }
}
