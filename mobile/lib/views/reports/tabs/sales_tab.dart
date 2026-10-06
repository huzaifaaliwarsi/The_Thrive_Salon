import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/pdf_invoice_generator.dart';
import '../../../utils/invoice_number.dart';
import '../../../widgets/report_horizontal_scrollbars.dart';

const _kDark = Color(0xFF1E293B);
const _kPrimary = Color(0xFF6366F1);

class SalesTabWidget extends ConsumerStatefulWidget {
  final List<dynamic> sales;
  final String? salonId;
  final ValueChanged<String> onVoidConfirm;
  final VoidCallback onExport;

  const SalesTabWidget({
    super.key,
    required this.sales,
    required this.salonId,
    required this.onVoidConfirm,
    required this.onExport,
  });

  @override
  ConsumerState<SalesTabWidget> createState() => _SalesTabWidgetState();
}

class _SalesTabWidgetState extends ConsumerState<SalesTabWidget> {
  late ScrollController _scrollController;
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _printInvoiceReceipt(BuildContext context, WidgetRef ref, Map<String, dynamic> sale) async {
    final user = ref.read(authProvider);
    final viewerSalon = user?['salon'];
    final salon = sale['salon'] ??
        (viewerSalon != null && viewerSalon['id'] == sale['salonId'] ? viewerSalon : null);

    final List<dynamic> rawItems = sale['saleItems'] ?? sale['items'] ?? [];
    final List<InvoiceItemData> invoiceItems = rawItems.map((item) {
      final name = item['serviceName'] ?? item['service']?['name'] ?? item['product']?['name'] ?? '';
      final arabicName = item['service']?['arabicName'] ?? item['product']?['arabicName'] ?? '';
      final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
      final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      return InvoiceItemData(
        name: name,
        arabicName: arabicName,
        quantity: qty,
        price: price,
        savedTax: double.tryParse(item['taxAmount']?.toString() ?? ''),
        savedDiscount: double.tryParse(item['discountAmount']?.toString() ?? ''),
      );
    }).toList();

    final subtotal = double.tryParse(sale['subtotal']?.toString() ?? '0') ?? 0.0;
    final discount = double.tryParse(sale['discount']?.toString() ?? '0') ?? 0.0;
    final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
    final taxAmount = double.tryParse(sale['taxAmount']?.toString() ?? '0') ?? 0.0;
    final taxRate = double.tryParse(sale['taxRate']?.toString() ?? '0') ?? 0.0;

    final amountPaidRaw = sale['amountPaid'];
    final amountPaid = amountPaidRaw != null ? (double.tryParse(amountPaidRaw.toString()) ?? total) : total;
    final change = amountPaid > total ? amountPaid - total : 0.0;
    final balanceDue = total > amountPaid ? total - amountPaid : 0.0;

    final method = sale['paymentMethod']?.toString().toUpperCase() ?? '';
    final dateStr = sale['createdAt']?.toString() ?? '';
    final date = DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now();

    final saleIdStr = sale['id']?.toString() ?? '';
    final generatedInvoiceId = invoiceNumber(saleIdStr, savedNumber: sale['invoiceNumber']);

    final invoiceData = InvoiceData(
      invoiceId: saleIdStr,
      savedInvoiceNumber: sale['invoiceNumber']?.toString(),
      items: invoiceItems,
      subtotal: subtotal,
      taxAmount: taxAmount,
      taxRate: taxRate,
      discount: discount,
      total: total,
      amountPaid: amountPaid,
      balanceDue: balanceDue,
      change: change,
      paymentMethod: method,
      date: date,
      customerName: sale['customerName']?.toString(),
      cashierName: sale['staff']?['name']?.toString(),
    );

    final pdf = await PdfInvoiceGenerator.generate(invoiceData, salon, false);

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: '$generatedInvoiceId.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final user = ref.watch(authProvider);
    final isOwner = user?['role'] == 'OWNER' || user?['role'] == 'SUPER_ADMIN';

    final activeSales = widget.sales.where((s) => s['status']?.toString().toUpperCase() != 'VOID').toList();

    if (activeSales.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.folderOpen, size: 40, color: Colors.black12),
            const SizedBox(height: 12),
            Text('No active sales found', style: GoogleFonts.outfit(color: Colors.black38, fontSize: 13)),
          ],
        ),
      );
    }

    double totalGross = 0;
    double totalDisc = 0;
    double totalNet = 0;
    double totalVat = 0;
    double totalGrand = 0;

    for (var s in activeSales) {
      final sub = double.tryParse(s['subtotal']?.toString() ?? '0') ?? 0.0;
      final disc = double.tryParse(s['discount']?.toString() ?? '0') ?? 0.0;
      final vat = double.tryParse(s['taxAmount']?.toString() ?? '0') ?? 0.0;
      final tot = double.tryParse(s['total']?.toString() ?? '0') ?? 0.0;

      totalGross += sub;
      totalDisc += disc;
      totalNet += (sub - disc);
      totalVat += vat;
      totalGrand += tot;
    }

    Widget miniCard(String label, double amount, String currency, Color color, {bool isTotal = false}) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isTotal ? color : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: isTotal ? null : Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: isTotal ? Colors.white70 : color), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('$currency ${formatAmount(amount)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: isTotal ? Colors.white : color), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
    }

    return ReportHorizontalScrollbars(
      controller: _scrollController,
      child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thickness: const WidgetStatePropertyAll(7),
          radius: const Radius.circular(8),
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.dragged) || states.contains(WidgetState.hovered)
                  ? const Color(0xFFA5A6E8)
                  : const Color(0xFFC4C5EF)),
          trackColor: const WidgetStatePropertyAll(Color(0xFFF4F4FC)),
          trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
          crossAxisMargin: 3,
        ),
        child: Scrollbar(
          controller: _verticalScrollController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          scrollbarOrientation: ScrollbarOrientation.right,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.vertical && notification.depth == 0,
          child: SingleChildScrollView(
            controller: _verticalScrollController,
            padding: const EdgeInsets.only(right: 14),
            child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sales Report', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
                    Text('Complete POS billing report for services and products.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onExport,
                icon: const Icon(LucideIcons.download, size: 12, color: _kPrimary),
                label: Text('Export', style: GoogleFonts.outfit(fontSize: 12, color: _kPrimary, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              return GridView.count(
                crossAxisCount: isNarrow ? 2 : 5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: isNarrow ? 1.8 : 2.2,
                children: [
                  miniCard('Gross Sales', totalGross, currency, Colors.indigo),
                  miniCard('Discount', totalDisc, currency, Colors.orange),
                  miniCard('Net Sales', totalNet, currency, Colors.blue),
                  miniCard('Tax', totalVat, currency, Colors.teal),
                  miniCard('Total (Incl. Tax)', totalGrand, currency, const Color(0xFF6A11CB), isTotal: true),
                ],
              );
            }
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.grey.shade100),
                child: DataTable(
                  columnSpacing: 20,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  headingRowHeight: 40,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 56,
                  columns: [
                    DataColumn(label: Text('INVOICE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('CUSTOMER', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('ITEM TYPE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('SERVICE / PRODUCT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('STAFF', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('GROSS', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    DataColumn(label: Text('DISCOUNT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    DataColumn(label: Text('NET SALES', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    DataColumn(label: Text('TAX', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    DataColumn(label: Text('TOTAL', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    DataColumn(label: Text('PAYMENT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('DATE / TIME', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    if (isOwner)
                      DataColumn(label: Text('ACTION', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                  ],
                  rows: List.generate(activeSales.length, (idx) {
                    final sale = activeSales[idx];
                    final dateStr = sale['createdAt']?.toString() ?? '';
                    final date = DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now();
                    final formattedDate = DateFormat('dd MMM, hh:mm a').format(date);

                    final client = sale['customerName'] ?? 'Walk-in';
                    final method = sale['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
                    final subtotal = double.tryParse(sale['subtotal']?.toString() ?? '0') ?? 0.0;
                    final discount = double.tryParse(sale['discount']?.toString() ?? '0') ?? 0.0;
                    final vatAmount = double.tryParse(sale['taxAmount']?.toString() ?? '0') ?? 0.0;
                    final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
                    final netSalesVal = subtotal - discount;
                    final isVoid = sale['status'] == 'VOID';

                    final List<dynamic> items = sale['saleItems'] ?? sale['items'] ?? [];
                    
                    String staffName = 'Unassigned';
                    if (sale['staff'] != null && sale['staff']['name'] != null) {
                      staffName = sale['staff']['name'];
                    } else {
                      final itemStaffNames = items
                          .map((i) => i['staff']?['name'])
                          .where((name) => name != null && name.toString().trim().isNotEmpty)
                          .toSet()
                          .toList();
                      if (itemStaffNames.isNotEmpty) {
                        staffName = itemStaffNames.join(', ');
                      }
                    }
                    
                    String itemType = 'Service';
                    final hasServ = items.any((i) => i['productId'] == null && !(i['serviceId']?.toString() ?? '').startsWith('inv_'));
                    final hasProd = items.any((i) => i['productId'] != null || (i['serviceId']?.toString() ?? '').startsWith('inv_'));
                    if (hasServ && hasProd) {
                      itemType = 'Service + Product';
                    } else if (hasProd) {
                      itemType = 'Product';
                    }

                    final itemsText = items.map((i) => i['serviceName'] ?? i['service']?['name'] ?? i['product']?['name'] ?? 'Item').join(' + ');

                    final String saleId = sale['id']?.toString() ?? '';
                    final invNumber = invoiceNumber(saleId, savedNumber: sale['invoiceNumber']);
                    final amountPaidVal = double.tryParse(sale['amountPaid']?.toString() ?? '0') ?? 0.0;
                    final isOnlineMethod = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ'].contains(method);

                    Color chipBg = const Color(0xFFF1F5F9);
                    Color chipFg = const Color(0xFF475569);
                    String methodText = isOnlineMethod ? 'Online' : 'Cash';
                    String statusLabel = 'PAID ($methodText)';

                    if (amountPaidVal <= 0.01) {
                      chipBg = const Color(0xFFFEF2F2);
                      chipFg = const Color(0xFFDC2626);
                      statusLabel = 'UNPAID ($methodText)';
                    } else if (amountPaidVal < (total - 0.01)) {
                      chipBg = const Color(0xFFFFF7ED);
                      chipFg = const Color(0xFFEA580C);
                      statusLabel = 'PARTIAL (${formatAmount(amountPaidVal)} of ${formatAmount(total)})';
                    } else {
                      chipBg = isOnlineMethod ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4);
                      chipFg = isOnlineMethod ? const Color(0xFF2563EB) : const Color(0xFF16A34A);
                      statusLabel = 'PAID ($methodText)';
                    }

                    final cellStyle = GoogleFonts.outfit(
                      fontSize: 13,
                      decoration: isVoid ? TextDecoration.lineThrough : null,
                      color: isVoid ? Colors.black38 : _kDark,
                    );

                    return DataRow(
                      cells: [
                        DataCell(Text(invNumber, style: cellStyle.copyWith(fontWeight: FontWeight.bold))),
                        DataCell(Text(client, style: cellStyle)),
                        DataCell(Text(itemType, style: cellStyle.copyWith(color: isVoid ? Colors.black38 : Colors.grey.shade600))),
                        DataCell(Text(itemsText, style: cellStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        DataCell(Text(staffName, style: cellStyle)),
                        DataCell(Text('$currency ${formatAmount(subtotal)}', style: cellStyle)),
                        DataCell(Text('$currency ${formatAmount(discount)}', style: cellStyle.copyWith(color: Colors.orange.shade700))),
                        DataCell(Text('$currency ${formatAmount(netSalesVal)}', style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: isVoid ? Colors.black38 : _kDark))),
                        DataCell(Text('$currency ${formatAmount(vatAmount)}', style: cellStyle.copyWith(color: Colors.teal.shade700))),
                        DataCell(Text('$currency ${formatAmount(total)}', style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: isVoid ? Colors.black38 : Colors.green.shade700))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(12)),
                            child: Text(statusLabel, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: chipFg)),
                          ),
                        ),
                        DataCell(Text(formattedDate, style: cellStyle)),
                        if (isOwner)
                          DataCell(
                            isVoid
                                ? Text('Voided', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black26, fontWeight: FontWeight.bold))
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(LucideIcons.printer, color: _kPrimary, size: 14),
                                        onPressed: () => _printInvoiceReceipt(context, ref, Map<String, dynamic>.from(sale)),
                                        tooltip: 'Print Invoice',
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(LucideIcons.ban, color: Colors.redAccent, size: 14),
                                        onPressed: () => widget.onVoidConfirm(sale['id']),
                                        tooltip: 'Void Transaction',
                                      ),
                                    ],
                                  ),
                          ),
                      ],
                    );
                  }),
                ),
              ),
          ),
        ],
      ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
