import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/sync_repository.dart';
import '../models/service_model.dart';
import '../view_models/pos_view_model.dart';

final servicesProvider = FutureProvider<List<Service>>((ref) async {
  return ref.watch(syncRepositoryProvider).getServices();
});

final filteredServicesProvider = Provider<List<Service>>((ref) {
  final servicesAsync = ref.watch(servicesProvider);
  final selectedCategory = ref.watch(posProvider.select((s) => s.selectedCategory));
  final searchQuery = ref.watch(posProvider.select((s) => s.searchQuery)).trim().toLowerCase();

  return servicesAsync.when(
    data: (services) {
      return services.where((s) {
        final matchesCat = selectedCategory == 'All' ||
            (selectedCategory == 'Packages' ? s.isPackage : s.category == selectedCategory);

        if (searchQuery.isEmpty) return matchesCat;

        final matchesName = s.name.toLowerCase().contains(searchQuery);
        final matchesArabic = s.arabicName?.toLowerCase().contains(searchQuery) ?? false;
        final matchesCategory = s.category.toLowerCase().contains(searchQuery);
        final matchesBundled = s.isPackage && s.bundledServices != null &&
            s.bundledServices!.any((bs) => bs.name.toLowerCase().contains(searchQuery));

        return matchesCat && (matchesName || matchesArabic || matchesCategory || matchesBundled);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

