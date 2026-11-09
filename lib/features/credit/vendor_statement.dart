import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/accounting/money.dart';
import '../expenses/expense_repository.dart';
import '../staff/staff_repository.dart';

class VendorStatement {
  VendorStatement._(this.data, this.expenses);
  final JsonRow data;
  final List<JsonRow> expenses;
  JsonRow get vendor => JsonRow.from(data['vendor'] as Map);
  String get name => vendor['name'] as String;
  int get outstanding => jsonPaise(data['outstanding_paise']);
  String get filename =>
      'Topolina-${name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').substring(0, name.length > 50 ? 50 : name.length)}-${data['business_date']}.pdf';
  factory VendorStatement.fromJson(JsonRow data) {
    final expenses = rows(data['expenses']);
    BigInt total = BigInt.zero, paid = BigInt.zero, due = BigInt.zero;
    for (final e in expenses) {
      final amount = BigInt.from(jsonPaise(e['amount_paise'])),
          payment = BigInt.from(jsonPaise(e['paid_paise'])),
          balance = BigInt.from(jsonPaise(e['outstanding_paise']));
      final history = rows(e['payments']).fold(
        BigInt.zero,
        (sum, p) => sum + BigInt.from(jsonPaise(p['amount_paise'])),
      );
      if (amount <= BigInt.zero ||
          payment < BigInt.zero ||
          balance <= BigInt.zero ||
          amount - payment != balance ||
          history != payment) {
        throw const ExpenseValidationException(
          'The vendor balance changed. Refresh the ledger and try again.',
        );
      }
      total += amount;
      paid += payment;
      due += balance;
    }
    if (total != BigInt.from(jsonPaise(data['amount_paise'])) ||
        paid != BigInt.from(jsonPaise(data['paid_paise'])) ||
        due != BigInt.from(jsonPaise(data['outstanding_paise']))) {
      throw const ExpenseValidationException(
        'Unable to verify this statement’s totals. Refresh and try again.',
      );
    }
    return VendorStatement._(data, expenses);
  }
}

Future<Uint8List> buildVendorStatement(VendorStatement statement) async {
  final regular = await rootBundle.load('assets/fonts/roboto-regular.ttf');
  final bold = await rootBundle.load('assets/fonts/roboto-bold.ttf');
  final logo = (await rootBundle.load('assets/brand/topolina-logo.png')).buffer
      .asUint8List();
  final logoImage = pw.MemoryImage(logo);
  final document = pw.Document(
    title: '${statement.name} - Vendor payment statement',
    author: statement.data['cafe_name'],
    creator: 'Topolina',
  );
  final forest = PdfColor.fromHex('#193F35'),
      cream = PdfColor.fromHex('#F7F4EC'),
      muted = PdfColor.fromHex('#66736A');
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(regular),
    bold: pw.Font.ttf(bold),
  );
  String money(Object? value) => Money(jsonPaise(value)).formatted;
  pw.Widget moneyCell(Object? value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    child: pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: pw.Alignment.centerRight,
      child: pw.Text(money(value), style: const pw.TextStyle(fontSize: 10)),
    ),
  );
  pw.Widget textCell(String text, {bool header = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: header ? 9 : 10,
        fontWeight: header ? pw.FontWeight.bold : null,
        color: header ? PdfColors.white : null,
      ),
    ),
  );
  pw.TableRow heading(List<String> labels) => pw.TableRow(
    repeat: true,
    decoration: pw.BoxDecoration(color: forest),
    children: labels.map((s) => textCell(s, header: true)).toList(),
  );
  pw.Widget metric(String label, Object? value, {bool emphasis = false}) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: emphasis ? forest : cream,
            borderRadius: pw.BorderRadius.circular(9),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 9,
                  color: emphasis ? PdfColors.white : muted,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  money(value),
                  style: pw.TextStyle(
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                    color: emphasis ? PdfColors.white : forest,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      maxPages: 500,
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 15),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Image(logoImage, width: 48, height: 48, fit: pw.BoxFit.contain),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    statement.data['cafe_name'],
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: forest,
                    ),
                  ),
                  pw.Text(
                    'VENDOR PAYMENT STATEMENT',
                    style: pw.TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            pw.Text(
              statement.data['reference'],
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 15),
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Prepared ${eventTimeLabel(statement.data['server_time'])}',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.SizedBox(height: 9),
        pw.Text('Payable to', style: pw.TextStyle(fontSize: 10, color: muted)),
        pw.SizedBox(height: 4),
        pw.Text(
          statement.name,
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: forest,
          ),
        ),
        if ((statement.vendor['contact'] ?? '').toString().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              statement.vendor['contact'].toString(),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        if ((statement.vendor['address'] ?? '').toString().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              statement.vendor['address'].toString().substring(
                0,
                statement.vendor['address'].toString().length > 500
                    ? 500
                    : statement.vendor['address'].toString().length,
              ),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Balance payable by ${statement.data['cafe_name']} as of ${expenseDateLabel(statement.data['business_date'])}.',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            metric('Open purchases', statement.data['amount_paise']),
            pw.SizedBox(width: 8),
            metric(
              'Paid against these purchases',
              statement.data['paid_paise'],
            ),
            pw.SizedBox(width: 8),
            metric(
              'Remaining payable',
              statement.data['outstanding_paise'],
              emphasis: true,
            ),
          ],
        ),
        pw.SizedBox(height: 22),
        pw.Text(
          'Pending purchases',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: forest,
          ),
        ),
        pw.SizedBox(height: 8),
        if (statement.expenses.isEmpty)
          pw.Text(
            'No pending purchases with this vendor.',
            style: const pw.TextStyle(fontSize: 11),
          )
        else
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(1.05),
              1: pw.FlexColumnWidth(2.6),
              2: pw.FlexColumnWidth(1.35),
              3: pw.FlexColumnWidth(1.35),
              4: pw.FlexColumnWidth(1.35),
            },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColors.grey300,
                width: .5,
              ),
            ),
            children: [
              heading([
                'Purchase date',
                'Description',
                'Original (INR)',
                'Paid (INR)',
                'Pending (INR)',
              ]),
              for (final e in statement.expenses)
                pw.TableRow(
                  children: [
                    textCell(expenseDateLabel(e['business_date'])),
                    textCell(
                      '${e['description']}\n#${e['id'].toString().substring(0, 8)}',
                    ),
                    moneyCell(e['amount_paise']),
                    moneyCell(e['paid_paise']),
                    moneyCell(e['outstanding_paise']),
                  ],
                ),
            ],
          ),
        pw.SizedBox(height: 22),
        pw.Text(
          'Payments already recorded',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: forest,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Payment dates below relate to the pending purchases listed above.',
          style: pw.TextStyle(fontSize: 9, color: muted),
        ),
        pw.SizedBox(height: 8),
        if (statement.expenses.every((e) => rows(e['payments']).isEmpty))
          pw.Text(
            'No payments have been recorded against these purchases.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(2.8),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(1.4),
            },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColors.grey300,
                width: .5,
              ),
            ),
            children: [
              heading([
                'Payment date',
                'For purchase',
                'Payment mode',
                'Amount (INR)',
              ]),
              for (final e in statement.expenses)
                for (final p in rows(e['payments']))
                  pw.TableRow(
                    children: [
                      textCell(expenseDateLabel(p['business_date'])),
                      textCell(
                        '${expenseDateLabel(e['business_date'])} - ${e['description']}',
                      ),
                      textCell(paymentModeLabel(p['payment_mode'])),
                      moneyCell(p['amount_paise']),
                    ],
                  ),
            ],
          ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Amounts reflect the Topolina ledger at the preparation time shown below. Please quote the statement reference when reconciling. This statement covers pending purchases; settled purchases are excluded.',
          style: pw.TextStyle(fontSize: 9, color: muted),
        ),
      ],
    ),
  );
  return document.save();
}
