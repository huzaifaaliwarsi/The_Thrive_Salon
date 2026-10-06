import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../providers/currency_provider.dart';
import '../../../utils/format_helper.dart';

const _kDark = Color(0xFF1E293B);

class ReceivablesTabWidget extends ConsumerStatefulWidget {
  final List<dynamic> salesList;
  final String? salonId;

  const ReceivablesTabWidget({
    super.key,
    required this.salesList,
    required this.salonId,
  });

  @override
  ConsumerState<ReceivablesTabWidget> createState() => _ReceivablesTabWidgetState();
}

class _ReceivablesTabWidgetState extends ConsumerState<ReceivablesTabWidget> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final salesList = widget.salesList;

    final receivableSales = salesList.where((sale) {
      if (sale['status'] == 'VOID') return false;
      final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
      final method = sale['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
      final rawPaid = double.tryParse(sale['amountPaid']?.toString() ?? '');
      final paid = rawPaid ?? (method == 'CREDIT' ? 0.0 : total);
      final pending = total - paid;
      return pending > 0.01 || method == 'CREDIT';
    }).toList();

    double totalReceivable = 0;
    for (var sale in receivableSales) {
      final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
      final method = sale['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
      final rawPaid = double.tryParse(sale['amountPaid']?.toString() ?? '');
      final paid = rawPaid ?? (method == 'CREDIT' ? 0.0 : total);
      totalReceivable += (total - paid).clamp(0.0, double.infinity);
    }

    final isWide = MediaQuery.of(context).size.width > 900;

    final tableCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer Receivable Report', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          Text('Customers who took service or product but payment is still pending.', style: GoogleFonts.outfit(fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 20),
          Scrollbar(
            thumbVisibility: true,
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.grey.shade100),
                child: DataTable(
                  columnSpacing: 24,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  headingRowHeight: 40,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 52,
                  columns: [
                    DataColumn(label: Text('CUSTOMER', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('INVOICE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('REASON', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                    DataColumn(label: Text('TOTAL BILL', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    DataColumn(label: Text('RECEIVED', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    DataColumn(label: Text('PENDING', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)), numeric: true),
                    DataColumn(label: Text('DUE DATE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
                  ],
                  rows: [
                    ...List.generate(receivableSales.length, (idx) {
                      final sale = receivableSales[idx];
                      final client = sale['customerName'] ?? 'Walk-in';
                      final dateStr = sale['createdAt']?.toString() ?? '';
                      final date = DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now();
                      final formattedDate = DateFormat('dd MMM').format(date);

                      final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
                      final method = sale['paymentMethod']?.toString().toUpperCase() ?? 'CASH';
                      final rawPaid = double.tryParse(sale['amountPaid']?.toString() ?? '');
                      final paid = rawPaid ?? (method == 'CREDIT' ? 0.0 : total);
                      final pending = (total - paid).clamp(0.0, double.infinity);

                      final reason = paid > 0 ? 'Partial payment pending' : 'Regular client credit';
                      final String saleId = sale['id']?.toString() ?? '';
                      final String shortId = saleId.length > 8 ? saleId.substring(0, 8).toUpperCase() : saleId.toUpperCase();
                      final invNumber = 'INV-$shortId';

                      final cellStyle = GoogleFonts.outfit(fontSize: 13, color: _kDark);

                      return DataRow(
                        cells: [
                          DataCell(Text(client, style: cellStyle.copyWith(fontWeight: FontWeight.w600))),
                          DataCell(Text(invNumber, style: cellStyle)),
                          DataCell(Text(reason, style: cellStyle.copyWith(color: Colors.black54))),
                          DataCell(Text('$currency ${formatAmount(total)}', style: cellStyle.copyWith(fontWeight: FontWeight.bold))),
                          DataCell(Text('$currency ${formatAmount(paid)}', style: cellStyle)),
                          DataCell(Text('$currency ${formatAmount(pending)}', style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: Colors.orange.shade800))),
                          DataCell(Text(formattedDate, style: cellStyle)),
                        ],
                      );
                    }),
                    DataRow(
                      cells: [
                        DataCell(Text('Total Receivable', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kDark))),
                        const DataCell(SizedBox()),
                        const DataCell(SizedBox()),
                        const DataCell(SizedBox()),
                        const DataCell(SizedBox()),
                        DataCell(Text('$currency ${formatAmount(totalReceivable)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700))),
                        const DataCell(SizedBox()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final ruleCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Receivable Rule', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Text(
              'Receivable should increase sales, but it should not increase cash drawer or online drawer until payment is received. When customer pays later, only drawer balance increases.',
              style: GoogleFonts.outfit(fontSize: 11, color: Colors.black54, height: 1.4),
            ),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: tableCard),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: ruleCard),
            ],
          )
        else ...[
          tableCard,
          const SizedBox(height: 16),
          ruleCard,
        ],
      ],
    );
  }
}
