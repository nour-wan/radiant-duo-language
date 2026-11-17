import 'dart:io';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Infinite-scroll list over a paginated admin endpoint.
class PagedList<T> extends StatefulWidget {
  const PagedList({super.key, required this.load, required this.itemBuilder, required this.empty, this.header});

  final Future<PageResult<T>> Function(int page) load;
  final Widget Function(BuildContext context, T item, VoidCallback reload) itemBuilder;
  final Widget empty;
  final Widget? header;

  @override
  State<PagedList<T>> createState() => PagedListState<T>();
}

class PagedListState<T> extends State<PagedList<T>> {
  final _items = <T>[];
  final _scroll = ScrollController();
  int _page = 1;
  bool _hasMore = true, _loading = false;
  Object? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _more();
    });
    reload();
  }

  @override
  void didUpdateWidget(PagedList<T> old) {
    super.didUpdateWidget(old);
    if (old.load != widget.load) reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    _items.clear();
    _page = 1;
    _hasMore = true;
    _error = null;
    await _more(force: true);
  }

  Future<void> _more({bool force = false}) async {
    if ((_loading && !force) || !_hasMore) return;
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final page = await widget.load(_page);
      if (seq != _seq || !mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _page++;
      });
    } catch (e) {
      if (seq == _seq && mounted) setState(() => _error = e);
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_items.isEmpty && _error != null) {
      body = ErrorView(error: _error!, onRetry: reload);
    } else if (_items.isEmpty && _loading) {
      body = const LoadingView();
    } else if (_items.isEmpty) {
      body = widget.empty;
    } else {
      body = RefreshIndicator(
        onRefresh: reload,
        child: ListView.separated(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          itemCount: _items.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => i >= _items.length ? const LoadingView() : widget.itemBuilder(context, _items[i], reload),
        ),
      );
    }
    return Column(children: [if (widget.header != null) widget.header!, Expanded(child: body)]);
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          textInputAction: TextInputAction.search,
          onSubmitted: onChanged,
          onChanged: (v) {
            if (v.isEmpty) onChanged(v);
          },
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: hint, isDense: true),
        ),
      );
}

class FormCard extends StatelessWidget {
  const FormCard({super.key, required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                if (trailing != null) trailing!,
              ]),
              const SizedBox(height: 12),
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
            ]),
          ),
        ),
      );
}

String? requiredField(BuildContext context, String? v) => (v == null || v.trim().isEmpty) ? context.tr('app.required') : null;

String? moneyField(BuildContext context, String? v, {bool optional = false}) {
  if (v == null || v.trim().isEmpty) return optional ? null : context.tr('app.required');
  return double.tryParse(v.trim()) == null ? context.tr('err.invalid') : null;
}

/// Saves CSV bytes to a temporary file and opens the share sheet (WhatsApp, email, Drive…).
Future<void> shareCsv(BuildContext context, List<int> bytes, String filename) async {
  // The server sends a real Excel file (dates as date cells, wide columns, right-to-left in Arabic)
  final name = filename.replaceAll(RegExp(r'\.csv$'), '.xlsx');
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')], subject: name));
}

class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.busy, required this.onPressed, this.label});

  final bool busy;
  final VoidCallback onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: busy ? null : onPressed,
            child: busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(label ?? context.tr('app.save')),
          ),
        ),
      );
}

double? parseAmount(String text) => double.tryParse(text.trim().replaceAll(',', '.').replaceAll('٫', '.'));

/// Ask for an amount (Syrian pounds) and a note. [signed] allows negative amounts; [noteRequired] for adjustments.
Future<({double amount, String note})?> askAmount(BuildContext context,
    {required String title, double? full, bool signed = false, bool noteRequired = false, String? hint}) async {
  final amount = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final value = parseAmount(amount.text);
        final valid = value != null && (signed ? value != 0 : value > 0) && (!noteRequired || note.text.trim().isNotEmpty);
        return AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: ctx.tr('pay.amount'),
                helperText: hint,
                helperMaxLines: 2,
                suffix: full != null && full > 0
                    ? TextButton(
                        onPressed: () => setState(() => amount.text = full.toStringAsFixed(2)),
                        child: Text(ctx.tr('pay.full')),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: ctx.tr(noteRequired ? 'pay.reason' : 'pay.note')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('app.cancel'))),
            FilledButton(onPressed: valid ? () => Navigator.pop(ctx, true) : null, child: Text(ctx.tr('app.confirm'))),
          ],
        );
      },
    ),
  );
  if (ok != true) return null;
  return (amount: parseAmount(amount.text)!, note: note.text.trim());
}
