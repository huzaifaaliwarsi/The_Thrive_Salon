import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../utils/pdf_invoice_generator.dart';
import '../utils/invoice_number.dart';

class PublicInvoiceView extends ConsumerStatefulWidget {
  final String invoiceId;
  final String? verifyHash;

  const PublicInvoiceView({
    super.key,
    required this.invoiceId,
    this.verifyHash,
  });

  @override
  ConsumerState<PublicInvoiceView> createState() => _PublicInvoiceViewState();
}

class _PublicInvoiceViewState extends ConsumerState<PublicInvoiceView> {
  bool _isLoading = true;
  String? _error;
  dynamic _sale;
  Map<String, dynamic>? _salon;

  @override
  void initState() {
    super.initState();
    _fetchInvoice();
  }

  Future<void> _fetchInvoice() async {
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.getPublicSale(widget.invoiceId, widget.verifyHash);
      
      setState(() {
        _sale = response['sale'];
        _salon = response['salon'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Could not load invoice',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_sale == null) {
      return const Scaffold(
        body: Center(child: Text('Invoice not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(invoiceNumber(_sale['id'], savedNumber: _sale['invoiceNumber']), style: const TextStyle(fontSize: 16)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        build: (format) async {
          // Reconstruct InvoiceData from the fetched JSON
          final dateStr = _sale['createdAt']?.toString() ?? DateTime.now().toIso8601String();
          final List<dynamic> itemsList = _sale['saleItems'] ?? [];
          final items = itemsList.map((item) {
            return InvoiceItemData(
              name: item['service']?['name'] ?? item['product']?['name'] ?? item['name'] ?? '',
              savedTax: double.tryParse(item['taxAmount']?.toString() ?? ''),
              savedDiscount: double.tryParse(item['discountAmount']?.toString() ?? ''),
              quantity: int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
              price: double.tryParse(item['price']?.toString() ?? '0') ?? 0.0,
            );
          }).toList();

          final total = double.tryParse(_sale['total']?.toString() ?? '') ?? 0.0;
          final paid = double.tryParse(_sale['amountPaid']?.toString() ?? '') ?? 0.0;
          List<InvoicePaymentAccountInfo>? paymentAccountsInfo;
          final method = _sale['paymentMethod']?.toString().toUpperCase() ?? '';
          if (method == 'ONLINE') {
            final breakdownRaw = _sale['paymentBreakdown'];
            final paymentAccountRaw = _sale['paymentAccount'];
            final list = <InvoicePaymentAccountInfo>[];

            if (breakdownRaw != null && breakdownRaw.toString().isNotEmpty) {
              try {
                final decoded = breakdownRaw is String ? jsonDecode(breakdownRaw) : breakdownRaw;
                if (decoded is List) {
                  for (final item in decoded) {
                    if (item is Map<String, dynamic>) {
                      list.add(InvoicePaymentAccountInfo.fromJson(item));
                    }
                  }
                }
              } catch (_) {}
            }

            if (list.isEmpty && paymentAccountRaw is Map<String, dynamic>) {
              list.add(InvoicePaymentAccountInfo.fromJson(paymentAccountRaw));
            }

            if (list.isNotEmpty) {
              paymentAccountsInfo = list;
            }
          }

          final invoiceData = InvoiceData(
            invoiceId: _sale['id'],
            savedInvoiceNumber: _sale['invoiceNumber']?.toString(),
            paymentMethod: _sale['paymentMethod'] ?? '',
            subtotal: double.tryParse(_sale['subtotal']?.toString() ?? '0') ?? 0.0,
            discount: double.tryParse(_sale['discount']?.toString() ?? '0') ?? 0.0,
            taxAmount: double.tryParse(_sale['taxAmount']?.toString() ?? '0') ?? 0.0,
            taxRate: double.tryParse(_sale['taxRate']?.toString() ?? '0') ?? 0.0,
            total: double.tryParse(_sale['total']?.toString() ?? '0') ?? 0.0,
            amountPaid: double.tryParse(_sale['amountPaid']?.toString() ?? '0') ?? 0.0,
            balanceDue: total > paid ? total - paid : 0.0,
            change: paid > total ? paid - total : 0.0,
            customerName: _sale['customerName']?.toString(),
            cashierName: _sale['staff']?['name']?.toString(),
            items: items,
            date: DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now(),
            paymentAccountsInfo: paymentAccountsInfo,
          );

          final pdfDoc = await PdfInvoiceGenerator.generate(invoiceData, _salon, false);
          return pdfDoc.save();
        },
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
      ),
    );
  }
}
