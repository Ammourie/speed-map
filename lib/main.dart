import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:android_intent_plus/android_intent.dart' show AndroidIntent;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart'
    show FlutterOverlayWindow, OverlayPosition;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'generated/l10n.dart';

void main() => runApp(const SpeedMapApp());

const _seed = Color(0xFF2563EB);
const _gaugeMaxKmh = 200.0;

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
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const SpeedMapPage(),
    );
  }
}

class SpeedMapPage extends StatefulWidget {
  const SpeedMapPage({super.key});

  @override
  State<SpeedMapPage> createState() => _SpeedMapPageState();
}

class _SpeedMapPageState extends State<SpeedMapPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _map = MapController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  StreamSubscription<Position>? _sub;
  bool _mapReady = false;
  bool _follow = true;
  LatLng? _pos;
  Position? _last;
  double _speedKmh = 0;
  double _maxKmh = 0;
  double _tripMeters = 0;
  double _heading = 0;
  double _accuracy = 0;
  String? _error;
  bool _overlayOn = false;
  DateTime? _overlayShownAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start({bool service = false}) async {
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
        // Foreground service keeps GPS alive while Google Maps is on screen.
        foregroundNotificationConfig: service
            ? ForegroundNotificationConfig(
                notificationTitle: S.current.appTitle,
                notificationText: S.current.trackingNotification,
                enableWakeLock: true,
              )
            : null,
      ),
    ).listen(_onPosition, onError: (e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  void _onPosition(Position p) {
    final ll = LatLng(p.latitude, p.longitude);
    final kmh = math.max(0.0, p.speed) * 3.6; // m/s -> km/h
    final prev = _last;
    if (prev != null && p.accuracy <= 30 && p.speed > 0.5) {
      _tripMeters += Geolocator.distanceBetween(
          prev.latitude, prev.longitude, p.latitude, p.longitude);
    }
    _last = p;
    if (_overlayOn) _pushToOverlay(kmh);
    setState(() {
      _pos = ll;
      _speedKmh = kmh;
      _maxKmh = math.max(_maxKmh, kmh);
      _accuracy = p.accuracy;
      if (p.heading >= 0 && p.speed > 0.8) _heading = p.heading;
    });
    if (_mapReady && _follow) {
      _map.move(ll, math.max(_map.camera.zoom, 16));
    }
  }

  void _recenter() {
    setState(() => _follow = true);
    final p = _pos;
    if (p != null && _mapReady) _map.move(p, math.max(_map.camera.zoom, 16));
  }

  void _resetTrip() => setState(() {
        _tripMeters = 0;
        _maxKmh = 0;
      });

  // ---- Google Maps + floating speedometer ----

  Future<void> _openGoogleMaps() async {
    final messenger = ScaffoldMessenger.of(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final screenH = MediaQuery.of(context).size.height;

    var granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      messenger.showSnackBar(
          SnackBar(content: Text(S.current.overlayPermissionNeeded)));
      granted = await FlutterOverlayWindow.requestPermission() ?? false;
      if (!granted) return;
    }

    await _start(service: true);
    if (!await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.showOverlay(
        // Size is read in pixels (not dp) by this plugin version.
        height: (80 * dpr).round(),
        width: (280 * dpr).round(),
        enableDrag: true,
        overlayTitle: S.current.appTitle,
        overlayContent: S.current.overlayActive,
      );
    }
    _overlayOn = true;
    _overlayShownAt = DateTime.now();

    final p = _pos;
    final uri = p == null
        ? 'geo:0,0?q='
        : 'geo:${p.latitude},${p.longitude}?z=17';
    try {
      await AndroidIntent(
        action: 'action_view',
        data: uri,
        package: 'com.google.android.apps.maps',
      ).launch();
      _placeOverlayAtBottom(screenH);
    } catch (_) {
      _overlayOn = false;
      await FlutterOverlayWindow.closeOverlay();
      messenger.showSnackBar(
          SnackBar(content: Text(S.current.mapsUnavailable)));
    }
  }

  Future<void> _pushToOverlay(double kmh) async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData(kmh);
      } else if (DateTime.now()
              .difference(_overlayShownAt ?? DateTime(2000)) >
          const Duration(seconds: 6)) {
        // Not active any more (user tapped the close icon).
        await _overlayClosed();
      }
    } catch (_) {}
  }

  /// The overlay window starts centred; move it down so it sits near the
  /// bottom edge. Retries because the overlay service starts asynchronously.
  Future<void> _placeOverlayAtBottom(double screenHeightDp) async {
    final y = (screenHeightDp / 2 - 40 - 120).round();
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        if (await FlutterOverlayWindow.moveOverlay(
                OverlayPosition(0, y.toDouble())) ==
            true) {
          return;
        }
      } catch (_) {}
    }
  }

  /// The user closed the floating speedometer: drop the foreground service.
  Future<void> _overlayClosed() async {
    if (!_overlayOn) return;
    _overlayOn = false;
    if (mounted) await _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _overlayOn) {
      FlutterOverlayWindow.isActive().then((active) {
        if (!active) _overlayClosed();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _follow) setState(() => _follow = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.speed_map',
              ),
              if (pos != null)
                CircleLayer(circles: [
                  CircleMarker(
                    point: pos,
                    radius: _accuracy.clamp(5.0, 150.0).toDouble(),
                    useRadiusInMeter: true,
                    color: _seed.withValues(alpha: 0.10),
                    borderColor: _seed.withValues(alpha: 0.35),
                    borderStrokeWidth: 1,
                  ),
                ]),
              if (pos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: pos,
                    width: 84,
                    height: 84,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Transform.rotate(
                        angle: _heading * math.pi / 180,
                        child: CustomPaint(
                          painter: _MarkerPainter(_pulse.value, _seed),
                        ),
                      ),
                    ),
                  ),
                ]),
            ],
          ),
          if (pos != null)
            Positioned(
              top: 0,
              left: 12,
              child: SafeArea(child: _gpsChip(cs)),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!_follow && pos != null) ...[
                      FloatingActionButton.small(
                        onPressed: _recenter,
                        tooltip: S.current.recenter,
                        child: const Icon(Icons.my_location),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _dashboard(cs),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gpsChip(ColorScheme cs) {
    final good = _accuracy <= 15;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.gps_fixed,
            size: 16, color: good ? Colors.green : Colors.orange),
        const SizedBox(width: 6),
        Text(
          '${S.current.gpsLabel} ±${_accuracy.round()} ${S.current.meterUnit}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ]),
    );
  }

  Widget _dashboard(ColorScheme cs) {
    return Material(
      elevation: 10,
      color: cs.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        child: SizedBox(
          width: double.infinity,
          child: _error != null
              ? _errorView()
              : _pos == null
                  ? _waitingView()
                  : _dataView(cs),
        ),
      ),
    );
  }

  Widget _errorView() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.location_off, size: 32),
        const SizedBox(height: 8),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: _start, child: Text(S.current.retry)),
      ]);

  Widget _waitingView() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(S.current.waitingForGps),
        ]),
      );

  Widget _dataView(ColorScheme cs) {
    final t = Theme.of(context).textTheme;
    final fraction = (_speedKmh / _gaugeMaxKmh).clamp(0.0, 1.0).toDouble();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: fraction),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOut,
          builder: (context, f, _) => SizedBox(
            width: 230,
            height: 190,
            child: CustomPaint(
              painter: _GaugePainter(f, cs.onSurface.withValues(alpha: 0.10)),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _speedKmh.round().toString(),
                      style: t.displayLarge?.copyWith(
                        fontSize: 68,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(S.current.speedUnit,
                        style: t.titleMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.65))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: _stat(S.current.maxLabel,
              '${_maxKmh.round()} ${S.current.speedUnit}'),
        ),
        Expanded(
          child: _stat(S.current.tripLabel,
              '${(_tripMeters / 1000).toStringAsFixed(2)} ${S.current.distanceUnit}'),
        ),
        IconButton(
          onPressed: _resetTrip,
          tooltip: S.current.resetTrip,
          icon: const Icon(Icons.restart_alt),
        ),
      ]),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _openGoogleMaps,
            icon: const Icon(Icons.map_outlined),
            label: Text(S.current.openGoogleMaps),
          ),
        ),
      ),
    ]);
  }

  Widget _stat(String label, String value) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Text(label,
          style: t.labelMedium
              ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
      const SizedBox(height: 2),
      Text(value,
          style: t.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
    ]);
  }
}

/// 270° speedometer arc, green -> amber -> red.
class _GaugePainter extends CustomPainter {
  _GaugePainter(this.fraction, this.trackColor, {this.stroke = 16});
  final double fraction;
  final Color trackColor;
  final double stroke;

  static const _start = 0.75 * math.pi;
  static const _sweep = 1.5 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: c, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, _start, _sweep, false, track);

    if (fraction <= 0) return;
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: _sweep,
        colors: [Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFFEF4444)],
        transform: GradientRotation(_start),
      ).createShader(rect);
    canvas.drawArc(rect, _start, _sweep * fraction, false, progress);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.trackColor != trackColor ||
      old.stroke != stroke;
}

/// Pulsing position dot with a heading cone (points "up" before rotation).
class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);

    // pulse ring
    canvas.drawCircle(
      c,
      14 + 26 * t,
      Paint()..color = color.withValues(alpha: 0.30 * (1 - t)),
    );

    // heading cone
    final cone = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx - 17, c.dy - 36)
      ..quadraticBezierTo(c.dx, c.dy - 46, c.dx + 17, c.dy - 36)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCenter(center: c, width: 40, height: 90)),
    );

    // dot with white ring + soft shadow
    canvas.drawCircle(c, 13, Paint()..color = Colors.black26);
    canvas.drawCircle(c.translate(0, -1), 12, Paint()..color = Colors.white);
    canvas.drawCircle(c.translate(0, -1), 8.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// Floating speedometer shown over Google Maps (runs in its own Flutter engine).
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void overlayMain() => runApp(const _OverlayApp());

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const _OverlaySpeedometer(),
    );
  }
}

class _OverlaySpeedometer extends StatefulWidget {
  const _OverlaySpeedometer();

  @override
  State<_OverlaySpeedometer> createState() => _OverlaySpeedometerState();
}

class _OverlaySpeedometerState extends State<_OverlaySpeedometer> {
  StreamSubscription<dynamic>? _sub;
  double _speed = 0;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is num && mounted) setState(() => _speed = data.toDouble());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction = (_speed / _gaugeMaxKmh).clamp(0.0, 1.0).toDouble();
    final color = _speed < 60
        ? const Color(0xFF22C55E)
        : _speed < 100
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: 260,
          height: 62,
          decoration: BoxDecoration(
            color: const Color(0xF2101828),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black54)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _speed.round().toString(),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          S.current.speedUnit,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xB3FFFFFF)),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOut,
                    height: 4,
                    width: 260 * fraction,
                    color: color,
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => FlutterOverlayWindow.closeOverlay(),
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.close,
                          size: 16, color: Color(0xB3FFFFFF)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
