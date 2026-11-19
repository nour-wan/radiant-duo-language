import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';
import 'theme.dart';

export 'package:latlong2/latlong.dart' show LatLng;

/// Central Damascus: where the map opens when there is no pin yet.
const damascus = LatLng(33.5138, 36.2765);

/// OpenStreetMap tiles (free, no account) with the attribution OSM asks for.
List<Widget> mapBaseLayers() => [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.alasfoodstuff.app',
        maxZoom: 19,
      ),
      const SimpleAttributionWidget(source: Text('OpenStreetMap')),
    ];

/// The phone's position, asking for permission if needed. Shows a message and returns null if
/// location is off or not allowed.
Future<LatLng?> currentLocation(BuildContext context) async {
  void say(String key) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  if (!await Geolocator.isLocationServiceEnabled()) {
    say('map.location_off');
    return null;
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    say('map.permission_denied');
    return null;
  }
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return LatLng(last.latitude, last.longitude);
    say('map.location_off');
    return null;
  }
}

/// Opens Google Maps (or the phone's maps app) with driving directions from here to [to].
Future<void> openDirections(LatLng to) async {
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${to.latitude},${to.longitude}&travelmode=driving');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The green pin used for the customer's place.
class PlacePin extends StatelessWidget {
  const PlacePin({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => Icon(Icons.location_on, size: size, color: AlasColors.primary, shadows: const [
        Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2)),
      ]);
}

/// The driver's marker: a round badge with a truck.
class DriverPin extends StatelessWidget {
  const DriverPin({super.key});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE0A458),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: const Icon(Icons.local_shipping, color: Colors.white, size: 20),
      );
}

/// Full-screen map with a fixed pin in the middle: the customer moves the map under it.
/// Pops with the chosen [LatLng].
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial});

  final LatLng? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  late LatLng _center = widget.initial ?? damascus;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // No pin yet: try to start from where the phone is (only if permission was already given)
    if (widget.initial == null) {
      Geolocator.checkPermission().then((p) {
        if (p == LocationPermission.always || p == LocationPermission.whileInUse) _goToMe();
      });
    }
  }

  Future<void> _goToMe() async {
    setState(() => _locating = true);
    final me = await currentLocation(context);
    if (!mounted) return;
    setState(() => _locating = false);
    if (me != null) _map.move(me, 17);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('map.pick_title'))),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: widget.initial == null ? 13 : 17,
            minZoom: 5,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onPositionChanged: (camera, _) => _center = camera.center,
          ),
          children: mapBaseLayers(),
        ),
        // The pin's tip sits on the map centre
        const IgnorePointer(child: Center(child: Padding(padding: EdgeInsets.only(bottom: 44), child: PlacePin(size: 48)))),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(context.tr('map.hint'), textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
            ),
          ),
        ),
        PositionedDirectional(
          end: 16,
          bottom: 96,
          child: FloatingActionButton.small(
            heroTag: 'me',
            tooltip: context.tr('map.my_location'),
            onPressed: _locating ? null : _goToMe,
            child: _locating
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, _center),
            icon: const Icon(Icons.check),
            label: Text(context.tr('map.confirm')),
          ),
        ),
      ),
    );
  }
}

/// A small map showing the customer's place and, while delivering, the driver.
class DeliveryMap extends StatefulWidget {
  const DeliveryMap({super.key, this.destination, this.driver, this.height = 200, this.onTap});

  final LatLng? destination, driver;
  final double height;
  final VoidCallback? onTap;

  @override
  State<DeliveryMap> createState() => _DeliveryMapState();
}

class _DeliveryMapState extends State<DeliveryMap> {
  final _map = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(DeliveryMap old) {
    super.didUpdateWidget(old);
    if (_ready && (old.driver != widget.driver || old.destination != widget.destination)) _fit();
  }

  List<LatLng> get _points => [?widget.destination, ?widget.driver];

  /// Both points in view (not closer than street level), or the one point.
  CameraFit? get _cameraFit {
    final points = _points;
    if (points.length < 2 || const Distance().as(LengthUnit.Meter, points[0], points[1]) < 150) return null;
    return CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 17);
  }

  LatLng get _center {
    final p = _points;
    if (p.isEmpty) return damascus;
    return LatLng(p.map((e) => e.latitude).reduce((a, b) => a + b) / p.length, p.map((e) => e.longitude).reduce((a, b) => a + b) / p.length);
  }

  void _fit() {
    final fit = _cameraFit;
    if (fit != null) {
      _map.fitCamera(fit);
    } else if (_points.isNotEmpty) {
      _map.move(_center, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            // The first view is set up front; later moves (the driver driving) go through the controller
            initialCenter: _center,
            initialZoom: 16,
            initialCameraFit: _cameraFit,
            onMapReady: () => _ready = true,
            onTap: widget.onTap == null ? null : (_, _) => widget.onTap!(),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom),
          ),
          children: [
            ...mapBaseLayers(),
            MarkerLayer(markers: [
              if (widget.destination != null)
                Marker(point: widget.destination!, width: 44, height: 44, alignment: Alignment.topCenter, child: const PlacePin()),
              if (widget.driver != null) Marker(point: widget.driver!, width: 40, height: 40, child: const DriverPin()),
            ]),
          ],
        ),
      ),
    );
  }
}

/// One marker on [MultiPointMap].
class MapPoint {
  const MapPoint(this.position, this.marker, {this.size = 40, this.alignment = Alignment.center, this.onTap});

  final LatLng position;
  final Widget marker;
  final double size;
  final Alignment alignment;
  final VoidCallback? onTap;
}

/// A map showing several points at once (e.g. every driver on the road), zoomed to fit them all.
class MultiPointMap extends StatefulWidget {
  const MultiPointMap({super.key, required this.points, this.height});

  final List<MapPoint> points;

  /// null = fill the space it is given.
  final double? height;

  @override
  State<MultiPointMap> createState() => _MultiPointMapState();
}

class _MultiPointMapState extends State<MultiPointMap> {
  final _map = MapController();
  bool _fitted = false;

  CameraFit? get _fit {
    final p = widget.points.map((e) => e.position).toList();
    if (p.length < 2) return null;
    return CameraFit.coordinates(coordinates: p, padding: const EdgeInsets.all(56), maxZoom: 16);
  }

  @override
  void didUpdateWidget(MultiPointMap old) {
    super.didUpdateWidget(old);
    // Fit once when the first positions arrive; after that the user's own zoom/pan is kept
    if (!_fitted && widget.points.isNotEmpty) {
      final fit = _fit;
      if (fit != null) {
        _map.fitCamera(fit);
      } else {
        _map.move(widget.points.first.position, 15);
      }
      _fitted = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.points.isEmpty ? damascus : widget.points.first.position;
    _fitted = _fitted || widget.points.isNotEmpty;
    final map = FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: first,
        initialZoom: widget.points.isEmpty ? 12 : 15,
        initialCameraFit: _fit,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        ...mapBaseLayers(),
        MarkerLayer(markers: [
          for (final p in widget.points)
            Marker(
              point: p.position,
              width: p.size,
              height: p.size,
              alignment: p.alignment,
              child: GestureDetector(onTap: p.onTap, child: p.marker),
            ),
        ]),
      ],
    );
    return widget.height == null ? map : SizedBox(height: widget.height, child: map);
  }
}
