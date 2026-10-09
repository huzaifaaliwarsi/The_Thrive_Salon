import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'invoice_number.dart';

class InvoiceItemData {
  final String name;
  final String arabicName;
  final int quantity;
  final double price;
  final double? savedTax;
  final double? savedDiscount;
  InvoiceItemData(
      {required this.name,
      this.arabicName = '',
      required this.quantity,
      required this.price,
      this.savedTax,
      this.savedDiscount});
}

class InvoicePaymentAccountInfo {
  final String accountName;
  final String? accountTitle;
  final String? accountNumber;
  final String? iban;
  final double? amount;

  InvoicePaymentAccountInfo({
    required this.accountName,
    this.accountTitle,
    this.accountNumber,
    this.iban,
    this.amount,
  });

  factory InvoicePaymentAccountInfo.fromJson(Map<String, dynamic> json) {
    return InvoicePaymentAccountInfo(
      accountName: json['accountName']?.toString() ??
          json['name']?.toString() ??
          'Online Account',
      accountTitle: json['accountTitle']?.toString() ?? json['title']?.toString(),
      accountNumber: json['accountNumber']?.toString() ?? json['number']?.toString(),
      iban: json['iban']?.toString(),
      amount: double.tryParse(json['amount']?.toString() ?? ''),
    );
  }
}

class InvoiceData {
  final String invoiceId;
  final String? savedInvoiceNumber;
  final List<InvoiceItemData> items;
  final double subtotal,
      taxAmount,
      taxRate,
      discount,
      total,
      amountPaid,
      balanceDue,
      change;
  final String paymentMethod;
  final DateTime date;
  final String? customerName, cashierName;
  final List<InvoicePaymentAccountInfo>? paymentAccountsInfo;
  InvoiceData(
      {required this.invoiceId,
      this.savedInvoiceNumber,
      required this.items,
      required this.subtotal,
      required this.taxAmount,
      required this.taxRate,
      required this.discount,
      required this.total,
      required this.amountPaid,
      required this.balanceDue,
      required this.change,
      required this.paymentMethod,
      required this.date,
      this.customerName,
      this.cashierName,
      this.paymentAccountsInfo});
}

class PdfInvoiceGenerator {
  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static Future<pw.ImageProvider?> _logo(dynamic salon) async {
    final value = _text(salon?['logo']);
    if (value.isEmpty) return null;
    try {
      if (value.startsWith('data:image/')) {
        return pw.MemoryImage(
            base64Decode(value.substring(value.indexOf(',') + 1)));
      }
      final uri = Uri.tryParse(value);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        return await networkImage(value);
      }
      return pw.MemoryImage(base64Decode(value));
    } catch (_) {
      return null;
    }
  }

  static Future<pw.Document> generate(
      InvoiceData state, dynamic salon, bool both) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final bold = await PdfGoogleFonts.cairoBold();
    final logo = await _logo(salon);
    final name = _text(salon?['name']);
    final address = _text(salon?['address']);
    final vat = _text(salon?['vatNumber']);
    final ntn = _text(salon?['ntnNumber']);
    final style = pw.TextStyle(font: font, fontSize: 7.5);
    final heading = pw.TextStyle(font: bold, fontSize: 7.5);
    final tableStyle = pw.TextStyle(font: font, fontSize: 6.5);
    final tableHeading = pw.TextStyle(font: bold, fontSize: 6.5);
    final totalStyle = pw.TextStyle(font: bold, fontSize: 10);

    pw.Widget summary(String label, double amount, {bool emphasis = false}) =>
        pw.Container(
            margin: pw.EdgeInsets.symmetric(vertical: emphasis ? 4 : 0),
            padding: pw.EdgeInsets.symmetric(vertical: emphasis ? 6 : 2),
            decoration: emphasis
                ? const pw.BoxDecoration(
                    border: pw.Border(
                        top: pw.BorderSide(width: 0.7),
                        bottom: pw.BorderSide(width: 0.7)))
                : null,
            child:
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text(label, style: emphasis ? totalStyle : style),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                  width: 55,
                  child: pw.Text(amount.toStringAsFixed(2),
                      textAlign: pw.TextAlign.right,
                      style: emphasis ? totalStyle : style)),
            ]));

    final rows = <List<String>>[];
    for (var index = 0; index < state.items.length; index++) {
      final item = state.items[index];
      final gross = item.price * item.quantity;
      // Preserve the POS calculation when saved item amounts are unavailable.
      final discount = item.savedDiscount ??
          (state.subtotal > 0 ? gross * state.discount / state.subtotal : 0.0);
      final tax = item.savedTax ?? (gross - discount) * state.taxRate / 100;
      rows.add([
        '${index + 1}',
        [item.name, item.arabicName]
            .where((value) => value.trim().isNotEmpty)
            .join('\n'),
        item.price.toStringAsFixed(2),
        '${state.taxRate.toStringAsFixed(2)}%',
        '${item.quantity}',
        tax.toStringAsFixed(2),
        (gross - discount + tax).toStringAsFixed(2),
      ]);
    }

    for (var copy = 0; copy < (both ? 2 : 1); copy++) {
      pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(4),
          theme: pw.ThemeData.withFont(base: font, bold: bold),
          build: (context) => pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
              child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Center(
                        child: pw.SizedBox(
                            width: 52,
                            height: 52,
                            child: logo == null
                                ? pw.SizedBox()
                                : pw.Image(logo, fit: pw.BoxFit.contain))),
                    pw.SizedBox(height: 10),
                    if (name.isNotEmpty)
                      pw.Center(
                          child: pw.Text(name,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: bold, fontSize: 12))),
                    if (address.isNotEmpty)
                      pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 5),
                          child: pw.Center(
                              child: pw.Text(address,
                                  textAlign: pw.TextAlign.center,
                                  style: style))),
                    if (vat.isNotEmpty)
                      pw.Center(child: pw.Text('STRN/VAT: $vat', style: style)),
                    if (ntn.isNotEmpty)
                      pw.Center(child: pw.Text('NTN: $ntn', style: style)),
                    pw.SizedBox(height: 10),
                    pw.Divider(thickness: 0.5, height: 8),
                    pw.Center(
                        child: pw.Text('SALES RECEIPT',
                            style: pw.TextStyle(
                                font: bold, fontSize: 8, letterSpacing: 1))),
                    pw.SizedBox(height: 3),
                    pw.Center(
                        child: pw.Text('Invoice # ${invoiceNumber(state.invoiceId, savedNumber: state.savedInvoiceNumber)}',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: font, fontSize: 6.5))),
                    pw.SizedBox(height: 3),
                    pw.Center(
                        child: pw.Text(
                            DateFormat('dd/MM/yyyy  hh:mm:ss a')
                                .format(state.date),
                            style: style)),
                    if (copy == 1)
                      pw.Center(
                          child: pw.Text('MERCHANT COPY', style: heading)),
                    pw.Divider(thickness: 0.5, height: 14),
                    if (_text(state.cashierName).isNotEmpty)
                      pw.Text('Cashier: ${state.cashierName}', style: style),
                    if (state.paymentMethod.isNotEmpty)
                      pw.Text('Mode of Payment: ${state.paymentMethod}',
                          style: style),
                    if (state.paymentAccountsInfo != null &&
                        state.paymentAccountsInfo!.isNotEmpty) ...[
                      ...state.paymentAccountsInfo!.map((acc) {
                        final amtStr = (acc.amount != null &&
                                acc.amount! > 0 &&
                                state.paymentAccountsInfo!.length > 1)
                            ? ' (${acc.amount!.toStringAsFixed(2)})'
                            : '';
                        return pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Bank/Account: ${acc.accountName}$amtStr',
                                style: style),
                            if (_text(acc.accountTitle).isNotEmpty)
                              pw.Text('Account Title: ${_text(acc.accountTitle)}',
                                  style: style),
                            if (_text(acc.accountNumber).isNotEmpty)
                              pw.Text('Account No: ${_text(acc.accountNumber)}',
                                  style: style),
                          ],
                        );
                      }),
                    ],
                    if (_text(state.customerName).isNotEmpty)
                      pw.Text('Customer: ${state.customerName}', style: style),
                    pw.SizedBox(height: 8),
                    pw.TableHelper.fromTextArray(
                        headers: [
                          '#',
                          'Description',
                          'Price',
                          'GST Rate',
                          'Qty',
                          'GST',
                          'Total'
                        ],
                        data: rows,
                        border: null,
                        headerStyle: tableHeading,
                        cellStyle: tableStyle,
                        headerDecoration: const pw.BoxDecoration(
                            border: pw.Border(
                                top: pw.BorderSide(width: 0.5),
                                bottom: pw.BorderSide(width: 0.5))),
                        cellPadding: const pw.EdgeInsets.symmetric(
                            horizontal: 1, vertical: 5),
                        columnWidths: {
                          0: const pw.FixedColumnWidth(10),
                          1: const pw.FlexColumnWidth(2.5),
                          2: const pw.FlexColumnWidth(1.3),
                          3: const pw.FlexColumnWidth(1.3),
                          4: const pw.FixedColumnWidth(13),
                          5: const pw.FlexColumnWidth(1.2),
                          6: const pw.FlexColumnWidth(1.5)
                        },
                        cellAlignments: {
                          0: pw.Alignment.center,
                          1: pw.Alignment.centerLeft,
                          2: pw.Alignment.centerRight,
                          3: pw.Alignment.centerRight,
                          4: pw.Alignment.center,
                          5: pw.Alignment.centerRight,
                          6: pw.Alignment.centerRight
                        }),
                    pw.Divider(thickness: 0.5, height: 10),
                    summary('Total Amount:', state.subtotal),
                    summary('Sales Tax:', state.taxAmount),
                    if (state.discount != 0)
                      summary('Discount:', state.discount),
                    summary('Payable:', state.total, emphasis: true),
                    summary('Received:', state.amountPaid),
                    if (state.balanceDue > 0)
                      summary('Balance Due:', state.balanceDue),
                    if (state.change > 0) summary('Change:', state.change),
                    pw.SizedBox(height: 12),
                    pw.Text('Powered by Isysware software solutions',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            font: bold, fontSize: 6.5, letterSpacing: 0.4)),
                  ]))));
    }
    return pdf;
  }
}
