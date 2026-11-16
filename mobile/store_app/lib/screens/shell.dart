import 'package:alas_shared/alas_shared.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import 'account/account_screen.dart';
import 'cart_screen.dart';
import 'categories_screen.dart';
import 'favorites_screen.dart';
import 'home_screen.dart';

/// Lets any screen switch the bottom tab (e.g. "Browse products" from the empty cart).
class ShellController extends InheritedWidget {
  const ShellController({super.key, required this.select, required super.child});

  final void Function(int index) select;

  static ShellController? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellController>();

  @override
  bool updateShouldNotify(ShellController old) => false;
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  final _keys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PushService>().requestAndRegister();
      context.read<Cart>().refreshQuote();
    });
  }

  void _select(int i) {
    if (i == _index) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<Cart, int>((c) => c.count);
    const tabs = [HomeScreen(), CategoriesScreen(), CartScreen(), FavoritesScreen(), AccountScreen()];
    return ShellController(
      select: _select,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = _keys[_index].currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
          } else if (_index != 0) {
            setState(() => _index = 0);
          } else {
            await SystemNavigator.pop();
          }
        },
        child: Scaffold(
          body: Column(children: [
            const OfflineBanner(),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Navigator(key: _keys[i], onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => tabs[i])),
                ],
              ),
            ),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: context.tr('nav.home')),
              NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: context.tr('nav.categories')),
              NavigationDestination(
                icon: Badge(isLabelVisible: cartCount > 0, label: Text('$cartCount'), child: const Icon(Icons.shopping_bag_outlined)),
                selectedIcon: Badge(isLabelVisible: cartCount > 0, label: Text('$cartCount'), child: const Icon(Icons.shopping_bag_rounded)),
                label: context.tr('nav.cart'),
              ),
              NavigationDestination(icon: const Icon(Icons.favorite_border), selectedIcon: const Icon(Icons.favorite), label: context.tr('nav.favorites')),
              NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.tr('nav.account')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin red bar shown while the device is offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ConnectivityResult>>(
        stream: Connectivity().onConnectivityChanged,
        builder: (context, snap) {
          final offline = snap.hasData && snap.data!.every((r) => r == ConnectivityResult.none);
          return AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: offline
                ? Container(
                    width: double.infinity,
                    color: AlasColors.destructive,
                    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 4, bottom: 6, left: 16, right: 16),
                    child: Row(children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(context.tr('app.offline'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                  )
                : const SizedBox.shrink(),
          );
        },
      );
}
