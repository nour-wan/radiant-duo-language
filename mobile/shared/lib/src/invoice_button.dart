import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'l10n.dart';
import 'widgets.dart';

/// Downloads an order's PDF invoice: opens it in the phone's PDF viewer, or shares it.
class InvoiceButton extends StatefulWidget {
  const InvoiceButton({super.key, required this.load, required this.number});

  /// Fetches the PDF bytes in the given language ('ar' or 'en').
  final Future<List<int>> Function(String lang) load;
  final String number;

  @override
  State<InvoiceButton> createState() => _InvoiceButtonState();
}

class _InvoiceButtonState extends State<InvoiceButton> {
  bool _busy = false;

  Future<File> _file() async {
    final bytes = await widget.load(context.lang);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/invoice-${widget.number}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _run({required bool share}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _file();
      if (!mounted) return;
      if (!share) {
        final result = await OpenFilex.open(file.path, type: 'application/pdf');
        // No PDF viewer on the phone: fall back to the share sheet
        if (result.type == ResultType.done) return;
      }
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], subject: widget.number));
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(share: false),
          icon: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(context.tr('invoice.download')),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.outlined(
        tooltip: context.tr('invoice.share'),
        onPressed: _busy ? null : () => _run(share: true),
        icon: const Icon(Icons.share_outlined),
      ),
    ]);
  }
}
