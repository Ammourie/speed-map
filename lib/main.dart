import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'generated/l10n.dart';

void main() => runApp(const SpeedMapApp());

class SpeedMapApp extends StatelessWidget {
  const SpeedMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (_) => S.current.appTitle,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const SpeedMapPage(),
    );
  }
}

class SpeedMapPage extends StatefulWidget {
  const SpeedMapPage({super.key});

  @override
  State<SpeedMapPage> createState() => _SpeedMapPageState();
}

class _SpeedMapPageState extends State<SpeedMapPage> {
  final MapController _map = MapController();
  StreamSubscription<Position>? _sub;
  bool _mapReady = false;
  LatLng? _pos;
  double _speedKmh = 0;
  double _heading = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _sub?.cancel();
    setState(() => _error = null);

    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _error = S.current.locationServicesDisabled);
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      setState(() => _error = S.current.permissionDenied);
      return;
    }
    if (perm == LocationPermission.deniedForever) {
      setState(() => _error = S.current.permissionDeniedForever);
      return;
    }

    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      ),
    ).listen(_onPosition, onError: (e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  void _onPosition(Position p) {
    final ll = LatLng(p.latitude, p.longitude);
    setState(() {
      _pos = ll;
      _speedKmh = math.max(0, p.speed) * 3.6; // m/s -> km/h
      if (p.speed > 0.5) _heading = p.heading;
    });
    if (_mapReady) {
      _map.move(ll, math.max(_map.camera.zoom, 16));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _pos;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: pos ?? const LatLng(33.5138, 36.2765),
              initialZoom: 16,
              onMapReady: () {
                _mapReady = true;
                if (_pos != null) _map.move(_pos!, 16);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.speed_map',
              ),
              if (pos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: pos,
                    width: 48,
                    height: 48,
                    child: Transform.rotate(
                      angle: _heading * math.pi / 180,
                      child: const Icon(Icons.navigation,
                          size: 44, color: Colors.blue),
                    ),
                  ),
                ]),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: SafeArea(child: _speedCard(context)),
          ),
        ],
      ),
    );
  }

  Widget _speedCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FilledButton(onPressed: _start, child: Text(S.current.retry)),
              ])
            : _pos == null
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(S.current.waitingForGps),
                  ])
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(_speedKmh.round().toString(),
                          style: t.displayLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text(S.current.speedUnit, style: t.titleLarge),
                    ],
                  ),
      ),
    );
  }
}
