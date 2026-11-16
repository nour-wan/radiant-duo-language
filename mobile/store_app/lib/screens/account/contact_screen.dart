import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/store_api.dart';

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('contact.title'))),
      body: AsyncView<StoreInfo>(
        load: api.settings,
        builder: (context, s, reload) {
          final wa = s.whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(context.tr('contact.sub'), style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            if (wa.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _open('https://wa.me/$wa'),
                icon: const Icon(Icons.chat),
                label: Text('${context.tr('contact.whatsapp')} · ${s.whatsapp}'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1F8F4E)),
              ),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                if (s.mobile.isNotEmpty) _row(Icons.smartphone, context.tr('contact.mobile'), s.mobile, 'tel:${s.mobile}'),
                if (s.phone.isNotEmpty) _row(Icons.phone, context.tr('contact.landline'), s.phone, 'tel:${s.phone}'),
                if (s.email.isNotEmpty) _row(Icons.mail_outline, context.tr('contact.email'), s.email, 'mailto:${s.email}'),
                if (s.website.isNotEmpty) _row(Icons.public, context.tr('contact.website'), s.website, s.website),
                if (s.address(lang).isNotEmpty) _row(Icons.place_outlined, context.tr('contact.address'), s.address(lang), null),
                if (s.hours(lang).isNotEmpty) _row(Icons.schedule, context.tr('contact.hours'), s.hours(lang), null),
              ]),
            ),
            if (s.facebook.isNotEmpty || s.instagram.isNotEmpty || s.telegram.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(context.tr('contact.social'), style: t.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if (s.facebook.isNotEmpty) ActionChip(avatar: const Icon(Icons.facebook, size: 18), label: const Text('Facebook'), onPressed: () => _open(s.facebook)),
                if (s.instagram.isNotEmpty) ActionChip(avatar: const Icon(Icons.camera_alt_outlined, size: 18), label: const Text('Instagram'), onPressed: () => _open(s.instagram)),
                if (s.telegram.isNotEmpty) ActionChip(avatar: const Icon(Icons.send, size: 18), label: const Text('Telegram'), onPressed: () => _open(s.telegram)),
              ]),
            ],
          ]);
        },
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, String? url) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value, textDirection: url != null && url.startsWith('tel:') ? TextDirection.ltr : null),
        trailing: url == null ? null : const Icon(Icons.open_in_new, size: 18),
        onTap: url == null ? null : () => _open(url),
      );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('about.title'))),
      body: AsyncView<StoreInfo>(
        load: api.settings,
        builder: (context, s, reload) => ListView(padding: const EdgeInsets.all(24), children: [
          const Center(child: LeafLogo(size: 84)),
          const SizedBox(height: 16),
          Text(s.name(lang), style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(s.about(lang), style: t.textTheme.bodyLarge),
          const SizedBox(height: 32),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (_, snap) => Text(
              snap.hasData ? '${context.tr('app.version')} ${snap.data!.version} (${snap.data!.buildNumber})' : '',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
        ]),
      ),
    );
  }
}
