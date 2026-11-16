import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';
import '../../widgets/common.dart';
import '../favorites_screen.dart';
import '../orders/orders_screen.dart';
import 'addresses_screen.dart';
import 'contact_screen.dart';
import 'delete_account_screen.dart';
import 'edit_profile_screen.dart';
import 'legal_screen.dart';
import 'notifications_screen.dart';
import 'statement_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final settings = context.watch<AppSettings>();
    final user = session.user;
    final t = Theme.of(context);
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('nav.account'))),
      body: ListView(children: [
        if (user == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [AlasColors.primary, AlasColors.logoGreen],
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const LeafLogo(size: 52, background: AlasColors.cream, foreground: AlasColors.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.tr('acc.guest_title'), style: t.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(context.tr('acc.guest_body'), style: t.textTheme.bodyMedium?.copyWith(color: AlasColors.cream)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AlasColors.cream, foregroundColor: AlasColors.primary),
                  onPressed: () => requireLogin(context),
                  icon: const Icon(Icons.login_rounded),
                  label: Text(context.tr('auth.login')),
                ),
              ]),
            ),
          )
        else
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            leading: CircleAvatar(
              radius: 26,
              backgroundColor: t.colorScheme.primaryContainer,
              child: Text(user.fullName.isNotEmpty ? user.fullName.characters.first : '?',
                  style: t.textTheme.titleLarge?.copyWith(color: t.colorScheme.primary)),
            ),
            title: Text(user.fullName.isNotEmpty ? user.fullName : user.phone, style: t.textTheme.titleMedium),
            subtitle: Text([
              if (user.businessName.isNotEmpty) user.businessName,
              if (user.businessType.isNotEmpty) context.tr('biz.${user.businessType}'),
              if (user.phone.isNotEmpty) '‎${user.phone}',
            ].join(' · ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => open(const EditProfileScreen()),
          ),
        if (user != null) ...[
          _Group(title: context.tr('acc.profile'), tiles: [
            _Tile(Icons.receipt_long_outlined, context.tr('acc.orders'), () => open(const OrdersScreen())),
            if (user.showStatement)
              _Tile(Icons.account_balance_wallet_outlined, context.tr('ledger.title'), () => open(const StatementScreen())),
            _Tile(Icons.place_outlined, context.tr('acc.addresses'), () => open(const AddressesScreen())),
            _Tile(Icons.favorite_border, context.tr('acc.favorites'), () => open(const FavoritesScreen())),
            _Tile(Icons.notifications_none, context.tr('acc.notifications'), () => open(const NotificationsScreen())),
          ]),
        ],
        _Group(title: context.tr('acc.settings'), tiles: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(context.tr('app.language')),
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'ar', label: Text('ع')), ButtonSegment(value: 'en', label: Text('EN'))],
              selected: {settings.lang},
              onSelectionChanged: (s) => settings.setLang(s.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(context.tr('app.appearance')),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(value: ThemeMode.system, child: Text(context.tr('app.theme_system'))),
                DropdownMenuItem(value: ThemeMode.light, child: Text(context.tr('app.theme_light'))),
                DropdownMenuItem(value: ThemeMode.dark, child: Text(context.tr('app.theme_dark'))),
              ],
              onChanged: (m) => m == null ? null : settings.setThemeMode(m),
            ),
          ),
        ]),
        _Group(title: context.tr('acc.support'), tiles: [
          _Tile(Icons.support_agent_outlined, context.tr('acc.contact'), () => open(const ContactScreen())),
          _Tile(Icons.info_outline, context.tr('acc.about'), () => open(const AboutScreen())),
          _Tile(Icons.privacy_tip_outlined, context.tr('acc.privacy'), () => open(const LegalScreen(slug: 'privacy'))),
          _Tile(Icons.gavel_outlined, context.tr('acc.terms'), () => open(const LegalScreen(slug: 'terms'))),
          _Tile(Icons.assignment_return_outlined, context.tr('acc.returns'), () => open(const LegalScreen(slug: 'returns'))),
        ]),
        if (user != null)
          _Group(title: '', tiles: [
            _Tile(Icons.logout, context.tr('app.logout'), () async {
              if (!await confirmDialog(context, title: context.tr('acc.logout_confirm'))) return;
              if (!context.mounted) return;
              await context.read<Session>().logout(deviceToken: context.read<PushService>().token);
            }),
            _Tile(Icons.delete_forever_outlined, context.tr('acc.delete'), () => open(const DeleteAccountScreen()), danger: true),
          ]),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
              child: Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          Card(
            child: Column(children: [
              for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const Divider(indent: 56), tiles[i]],
            ]),
          ),
        ]),
      );
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.title, this.onTap, {this.danger = false});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AlasColors.destructive : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
