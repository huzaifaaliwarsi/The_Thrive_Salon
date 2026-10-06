import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/sync_repository.dart';

final staffProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(syncRepositoryProvider).getStaff();
});

final staffForSalonProvider = FutureProvider.family<List<dynamic>, String>((ref, salonId) async {
  return ref.watch(syncRepositoryProvider).getStaff(salonId: salonId);
});
