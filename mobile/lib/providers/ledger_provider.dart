import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class LedgerParams {
  final String? clientId;
  final String? vendorId;
  final String? staffId;
  final String? salonId;
  final int limit;
  final int offset;
  final bool? includeOnline;

  const LedgerParams({
    this.clientId,
    this.vendorId,
    this.staffId,
    this.salonId,
    this.limit = 100,
    this.offset = 0,
    this.includeOnline,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedgerParams &&
          runtimeType == other.runtimeType &&
          clientId == other.clientId &&
          vendorId == other.vendorId &&
          staffId == other.staffId &&
          salonId == other.salonId &&
          limit == other.limit &&
          offset == other.offset &&
          includeOnline == other.includeOnline;

  @override
  int get hashCode =>
      clientId.hashCode ^
      vendorId.hashCode ^
      staffId.hashCode ^
      salonId.hashCode ^
      limit.hashCode ^
      offset.hashCode ^
      includeOnline.hashCode;
}

final ledgerProvider = FutureProvider.family<Map<String, dynamic>, LedgerParams>((ref, params) async {
  final res = await ref.read(apiServiceProvider).getLedger(
    clientId: params.clientId,
    vendorId: params.vendorId,
    staffId: params.staffId,
    salonId: params.salonId,
    limit: params.limit,
    offset: params.offset,
    includeOnline: params.includeOnline,
  );
  return res as Map<String, dynamic>;
});
