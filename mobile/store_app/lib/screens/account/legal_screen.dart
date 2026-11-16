import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/store_api.dart';

/// Privacy policy, terms, return policy — text managed from the admin app.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    final lang = context.lang;
    return AsyncView<LegalPage>(
      load: () => api.legal(slug),
      builder: (context, page, reload) => Scaffold(
        appBar: AppBar(title: Text(page.title(lang))),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(context.tr('legal.updated', {'d': formatDate(page.updatedAt, lang)}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          SimpleRichText(page.body(lang)),
        ]),
      ),
    );
  }
}
