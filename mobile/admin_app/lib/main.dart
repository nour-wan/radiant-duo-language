import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/login_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/shell.dart';
import 'services/admin_api.dart';
import 'state/admin_session.dart';
import 'strings.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  L10n.register(sharedStrings);
  L10n.register(adminStrings);
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings(prefs);
  final client = ApiClient(tokens: TokenStore('admin'), language: () => settings.lang);
  final api = AdminApi(client);
  final session = AdminSession(client);
  client.onSessionExpired = session.expired;
  await session.restore();

  final push = PushService(
    registerToken: (t) => api.registerDevice(t, settings.lang),
    onOpen: (data) {
      final link = data['whatsapp_link'];
      if (link is String && link.startsWith('https://wa.me/')) {
        launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
        return;
      }
      final id = int.tryParse('${data['order_id'] ?? ''}');
      if (id != null) navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => AdminOrderScreen(orderId: id)));
    },
  );
  await push.init();
  void registerIfLoggedIn() {
    if (session.loggedIn) push.requestAndRegister();
  }

  session.addListener(registerIfLoggedIn);
  settings.addListener(registerIfLoggedIn);
  registerIfLoggedIn();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: session),
      Provider.value(value: api),
      Provider.value(value: push),
    ],
    child: const AdminApp(),
  ));
  push.markReady();
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final loggedIn = context.watch<AdminSession>().loggedIn;
    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: keepAboveSystemBar,
      title: 'Alas Admin',
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: settings.themeMode,
      theme: buildAlasTheme(brightness: Brightness.light, languageCode: settings.lang),
      darkTheme: buildAlasTheme(brightness: Brightness.dark, languageCode: settings.lang),
      home: loggedIn ? const AdminShell() : const AdminLoginScreen(),
    );
  }
}
