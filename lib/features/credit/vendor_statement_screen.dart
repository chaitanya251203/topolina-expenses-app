import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../expenses/expense_repository.dart';
import 'vendor_statement.dart';

class VendorStatementScreen extends StatefulWidget {
  const VendorStatementScreen({super.key, required this.statement});
  final VendorStatement statement;
  @override
  State<VendorStatementScreen> createState() => _VendorStatementScreenState();
}

class _VendorStatementScreenState extends State<VendorStatementScreen> {
  late final Future<Uint8List> pdf;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    pdf = buildVendorStatement(widget.statement);
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final location = await FilePicker.saveFile(
        fileName: widget.statement.filename,
        bytes: await pdf,
        mimeType: 'application/pdf',
      );
      if (location != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vendor statement saved.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save this statement. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Vendor statement'),
      actions: [
        IconButton(
          tooltip: 'Save PDF',
          onPressed: saving ? null : save,
          icon: const Icon(Icons.download_outlined),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.statement.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Prepared ${eventTimeLabel(widget.statement.data['server_time'])}',
              ),
              const SizedBox(height: 6),
              const Text(
                'Use the share button below to choose WhatsApp, email or another app.',
              ),
            ],
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: (_) => pdf,
            pdfFileName: widget.statement.filename,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: true,
            allowSharing: true,
            onError: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Text(
                  'Unable to preview this statement. Go back and generate it again.',
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
