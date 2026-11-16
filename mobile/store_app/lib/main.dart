import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/account/statement_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/product/product_list_screen.dart';
import 'screens/shell.dart';
import 'services/store_api.dart';
import 'state/cart.dart';
import 'state/favorites.dart';
import 'state/session.dart';
import 'strings.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  L10n.register(sharedStrings);
  L10n.register(storeStrings);
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings(prefs);
  final client = ApiClient(tokens: TokenStore('store'));
  final api = StoreApi(client);
  final session = Session(client);
  client.onSessionExpired = session.expired;
  await session.restore();
  final cart = Cart(prefs, api);
  final favorites = Favorites(api, session);

  final push = PushService(
    registerToken: (t) => api.registerDevice(t, settings.lang),
    onOpen: openFromNotification,
  );
  await push.init();
  // Re-register the token whenever the user or language changes, so the server
  // links it to the right account and sends notifications in the right language.
  session.addListener(push.requestAndRegister);
  settings.addListener(push.requestAndRegister);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: cart),
      ChangeNotifierProvider.value(value: favorites),
      Provider.value(value: api),
      Provider.value(value: push),
    ],
    child: const StoreApp(),
  ));
  push.markReady();
}

void openFromNotification(Map<String, dynamic> data) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  final orderId = int.tryParse('${data['order_id'] ?? ''}');
  final productId = data['product_id']?.toString();
  final categoryId = int.tryParse('${data['category_id'] ?? ''}');
  if (data['screen'] == 'statement') {
    nav.push(MaterialPageRoute(builder: (_) => const StatementScreen()));
  } else if (orderId != null) {
    nav.push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)));
  } else if (productId != null && productId.isNotEmpty) {
    nav.push(MaterialPageRoute(builder: (_) => ProductDetailScreen(productKey: productId)));
  } else if (categoryId != null) {
    nav.push(MaterialPageRoute(builder: (_) => ProductListScreen(query: ProductQuery(categoryId: categoryId))));
  }
}

class StoreApp extends StatelessWidget {
  const StoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final onboarded = settings.prefs.getBool('onboarded') ?? false;
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Alas Foodstuff',
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
      home: onboarded ? const Shell() : const OnboardingScreen(),
    );
  }
}
