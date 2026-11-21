import 'dart:async';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';
import 'orders_screen.dart';

/// Every order out for delivery right now on one map: where each driver is, and the customers'
/// places. Refreshes every 15 seconds. The owner sees all; a distributor their own; employees the store's.
class LiveDeliveriesScreen extends StatefulWidget {
  const LiveDeliveriesScreen({super.key});

  @override
  State<LiveDeliveriesScreen> createState() => _LiveDeliveriesScreenState();
}

class _LiveDeliveriesScreenState extends State<LiveDeliveriesScreen> {
  List<Map<String, dynamic>>? _rows;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await context.read<AdminApi>().liveDeliveries();
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _rows == null) setState(() => _error = e);
    }
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminOrderScreen(orderId: id)));
    _load();
  }

  static LatLng? _driverAt(Map<String, dynamic> r) {
    final t = r['tracking'];
    return t is Map ? toPoint(t['latitude'], t['longitude']) : null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final owner = context.watch<AdminSession>().isOwner;
    final rows = _rows;
    final points = <MapPoint>[
      for (final r in rows ?? <Map<String, dynamic>>[]) ...[
        if (toPoint(r['latitude'], r['longitude']) case final pin?)
          MapPoint(pin, const PlacePin(size: 34), size: 34, alignment: Alignment.topCenter, onTap: () => _open(r['id'] as int)),
        if (_driverAt(r) case final at?) MapPoint(at, _DriverBadge(name: '${r['driver_name'] ?? ''}'), size: 64, onTap: () => _open(r['id'] as int)),
      ],
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('live.title')),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : rows == null
              ? const LoadingView()
              : Column(children: [
                  Expanded(
                    flex: 3,
                    child: MultiPointMap(points: points, routes: [
                      for (final r in rows)
                        [
                          for (final p in (r['route'] as List? ?? []))
                            if (p is List && p.length == 2) ?toPoint(p[0], p[1]),
                        ],
                    ]),
                  ),
                  Expanded(
                    flex: 2,
                    child: rows.isEmpty
                        ? EmptyView(icon: Icons.local_shipping_outlined, title: context.tr('live.empty'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final r = rows[i];
                              final tr = r['tracking'] as Map?;
                              final eta = tr?['eta_minutes'];
                              return Card(
                                child: ListTile(
                                  leading: Icon(Icons.local_shipping, color: tr == null ? t.colorScheme.onSurfaceVariant : AlasColors.primary),
                                  title: Text('${r['number']} · ${r['customer']}'),
                                  subtitle: Text([
                                    r['driver_name'] == null ? context.tr('drv.no_driver') : context.tr('drv.driver', {'n': r['driver_name']}),
                                    if ((r['area'] as String?)?.isNotEmpty == true) r['area'],
                                    if (owner && r['distributor_name'] != null) context.tr('dist.via', {'n': r['distributor_name']}),
                                    if (tr == null) context.tr('track.waiting') else if (eta != null) context.tr('track.eta', {'n': eta}),
                                    if (tr != null && tr['updated_at'] != null) _ago(context, toDate(tr['updated_at'])),
                                  ].join(' · ')),
                                  trailing: const Icon(Icons.chevron_left),
                                  onTap: () => _open(r['id'] as int),
                                ),
                              );
                            },
                          ),
                  ),
                ]),
    );
  }
}

class _DriverBadge extends StatelessWidget {
  const _DriverBadge({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox.square(dimension: 36, child: DriverPin()),
        if (name.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
          ),
      ]);
}


String _ago(BuildContext context, DateTime at) {
  final mins = DateTime.now().difference(at).inMinutes;
  return mins < 1 ? context.tr('live.seen_now') : context.tr('live.seen_ago', {'n': mins});
}
