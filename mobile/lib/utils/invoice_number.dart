/// Display number only. Always use the original sale ID for API requests.
String invoiceNumber(dynamic saleId, {dynamic savedNumber}) {
  final number = savedNumber?.toString().trim() ?? '';
  if (number.isNotEmpty) return number;
  final id = saleId?.toString().trim() ?? '';
  if (id.isEmpty) return '';
  return 'INV-${(id.length > 8 ? id.substring(0, 8) : id).toUpperCase()}';
}
