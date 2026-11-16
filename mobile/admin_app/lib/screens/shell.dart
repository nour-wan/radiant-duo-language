import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => Scaffold(
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
