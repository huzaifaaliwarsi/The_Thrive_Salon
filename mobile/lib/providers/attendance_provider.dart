import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final attendanceProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(apiServiceProvider).getAttendance();
});
