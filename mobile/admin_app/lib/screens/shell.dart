import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';
import '../state/delivery_tracker.dart';

import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'more_screen.dart';
import 'orders_screen.dart';
import 'products_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (context.read<AdminSession>().isDriver) _resumeDeliveries();
  }

  /// A driver opening the app: keep sharing the location for every order still out for delivery.
  Future<void> _resumeDeliveries() async {
    final api = context.read<AdminApi>();
    final tracker = context.read<DeliveryTracker>();
    try {
      final page = await api.orders(status: 'shipped');
      for (final o in page.items.where((o) => !o.isPickup)) {
        if (!tracker.orders.contains(o.id)) await tracker.start(o.id);
      }
    } catch (_) {
      // Offline: the order screen starts it when opened
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.watch<AdminSession>().isDriver) {
      return Scaffold(
        body: IndexedStack(index: _index.clamp(0, 1), children: [
          OrdersScreen(title: context.tr('drv.my_deliveries')),
          const MoreScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index.clamp(0, 1),
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.local_shipping_outlined), selectedIcon: const Icon(Icons.local_shipping), label: context.tr('drv.my_deliveries')),
            NavigationDestination(icon: const Icon(Icons.menu), label: context.tr('nav.more')),
          ],
        ),
      );
    }
    return Scaffold(
        body: IndexedStack(index: _index, children: [
          DashboardScreen(onOpenOrders: () => setState(() => _index = 1)),
          const OrdersScreen(),
          const ProductsScreen(),
          const CustomersScreen(),
          const MoreScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: context.tr('nav.dashboard')),
            NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: context.tr('nav.orders')),
            NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2), label: context.tr('nav.products')),
            NavigationDestination(icon: const Icon(Icons.people_outline), selectedIcon: const Icon(Icons.people), label: context.tr('nav.customers')),
            NavigationDestination(icon: const Icon(Icons.menu), label: context.tr('nav.more')),
          ],
        ),
      );
  }
}
