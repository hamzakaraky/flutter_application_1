// ═══════════════════════════════════════════════════════════════════════════════
//  Smart Radar — BLE Proximity System
//  main.dart  |  Production-ready, zero-error build
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:permission_handler/permission_handler.dart';

// ─── Entry Point ──────────────────────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const RadarApp());
}

// ─── App Root ─────────────────────────────────────────────────────────────────
class RadarApp extends StatelessWidget {
  const RadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Radar',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF020A18),
      ),
      home: const RadarScreen(),
    );
  }
}

// ─── Enums ────────────────────────────────────────────────────────────────────
enum RadarState { initializing, permissionDenied, bluetoothOff, scanning, detected, error }

// ─── Screen ───────────────────────────────────────────────────────────────────
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with TickerProviderStateMixin {

  // Controllers
  late final AnimationController _pulseController;
  late final AnimationController _sweepController;
  late final AnimationController _fadeController;

  // BLE
  StreamSubscription<RangingResult>? _streamRanging;
  final _region = Region(
    identifier: 'SmartRoom',
    proximityUUID: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
  );

  // State
  RadarState _state = RadarState.initializing;
  double _distance = 0.0;
  int _rssi = -100;
  int _txPower = -59;
  int _beaconCount = 0;
  String _errorMessage = '';

  // ─── Helpers ────────────────────────────────────────────────────────────
  bool get _isDetected => _state == RadarState.detected;

  Color get _primaryColor =>
      _isDetected ? const Color(0xFF00FFCC) : const Color(0xFF4FC3F7);

  Color get _secondaryColor =>
      _isDetected ? const Color(0xFF00CC99) : const Color(0xFF0288D1);

  String get _statusText {
    switch (_state) {
      case RadarState.initializing:    return 'INITIALIZING...';
      case RadarState.permissionDenied: return 'PERMISSION DENIED';
      case RadarState.bluetoothOff:    return 'BLUETOOTH OFF';
      case RadarState.scanning:        return 'SCANNING FOR ROOM';
      case RadarState.detected:        return 'ROOM DETECTED • SILENT ON';
      case RadarState.error:           return 'ERROR: $_errorMessage';
    }
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _initPermissions();
  }

  @override
  void dispose() {
    _streamRanging?.cancel();
    _pulseController.dispose();
    _sweepController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ─── Permissions ────────────────────────────────────────────────────────
  Future<void> _initPermissions() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (!mounted) return;

    if (statuses[Permission.locationWhenInUse]!.isGranted) {
      _startRadar();
    } else {
      setState(() => _state = RadarState.permissionDenied);
    }
  }

  // ─── BLE Logic ──────────────────────────────────────────────────────────
  void _startRadar() async {
    if (!mounted) return;
    setState(() => _state = RadarState.scanning);

    try {
      // initializeAndCheckScanning validates BT state before scanning
      await flutterBeacon.initializeAndCheckScanning;

      _streamRanging = flutterBeacon.ranging([_region]).listen(
        (result) {
          if (!mounted) return;

          final wasDetected = _isDetected;

          if (result.beacons.isNotEmpty) {
            final beacon = result.beacons.first;
            final dist = _calcDistance(beacon.txPower ?? -59, beacon.rssi);

            setState(() {
              _rssi        = beacon.rssi;
              _txPower     = beacon.txPower ?? -59;
              _distance    = dist;
              _beaconCount = result.beacons.length;
              _state       = (dist > 0 && dist < 1.5)
                  ? RadarState.detected
                  : RadarState.scanning;

              // Speed up pulse when detected
              _pulseController.duration = _isDetected
                  ? const Duration(milliseconds: 500)
                  : const Duration(seconds: 2);
            });

            // Haptic only on transition in
            if (!wasDetected && _isDetected) {
              HapticFeedback.heavyImpact();
            }
            // Restart after duration change
            _pulseController.repeat();

          } else {
            setState(() {
              _beaconCount = 0;
              _state       = RadarState.scanning;
              _pulseController.duration = const Duration(seconds: 2);
            });
            _pulseController.repeat();
          }
        },
        onError: (dynamic e) {
          if (!mounted) return;
          setState(() {
            _errorMessage = e.toString();
            _state = RadarState.error;
          });
        },
      );

    } on PlatformException catch (e) {
      // flutter_beacon throws PlatformException for BT-off / uninitialized
      if (mounted) setState(() {
        _errorMessage = e.message ?? e.code;
        _state = e.code == 'BLUETOOTH_STATE'
            ? RadarState.bluetoothOff
            : RadarState.error;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _state = RadarState.error;
        });
      }
    }
  }

  // ─── Distance Formula ───────────────────────────────────────────────────
  double _calcDistance(int txPower, int rssi) {
    if (rssi == 0) return -1.0;
    final ratio = rssi / txPower;
    return ratio < 1.0
        ? pow(ratio, 10).toDouble()
        : 0.89976 * pow(ratio, 7.7095) + 0.111;
  }

  // ─── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020A18),
      body: FadeTransition(
        opacity: _fadeController,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildRadar()),
              _buildStatusBanner(),
              const SizedBox(height: 16),
              _buildMetrics(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 5,
                ),
                child: const Text('SMART RADAR'),
              ),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                style: TextStyle(
                  color: _primaryColor.withOpacity(0.45),
                  fontSize: 10,
                  letterSpacing: 3,
                ),
                child: const Text('BLE PROXIMITY SYSTEM v2'),
              ),
            ],
          ),
          _buildLiveBadge(),
        ],
      ),
    );
  }

  Widget _buildLiveBadge() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _primaryColor.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryColor,
                boxShadow: _isDetected
                    ? [BoxShadow(color: _primaryColor, blurRadius: 6 * _pulseController.value)]
                    : [],
              ),
            ),
          ),
          const SizedBox(width: 7),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 400),
            style: TextStyle(
              color: _primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
            child: Text(_isDetected ? 'ACTIVE' : 'LIVE'),
          ),
        ],
      ),
    );
  }

  // ─── Radar ───────────────────────────────────────────────────────────────
  Widget _buildRadar() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow background
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _primaryColor.withOpacity(_isDetected ? 0.08 : 0.03),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // 3 staggered pulse rings
          ...List.generate(3, _buildPulseRing),

          // Sweep + grid layer
          AnimatedBuilder(
            animation: _sweepController,
            builder: (_, __) => CustomPaint(
              size: const Size(290, 290),
              painter: _SweepPainter(_sweepController.value, _primaryColor),
            ),
          ),
          CustomPaint(
            size: const Size(290, 290),
            painter: _GridPainter(_primaryColor),
          ),

          // Center orb
          _buildCenterOrb(),
        ],
      ),
    );
  }

  Widget _buildPulseRing(int i) {
    final offset = i / 3.0;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final t = (_pulseController.value + offset) % 1.0;
        return Container(
          width: 290 * t,
          height: 290 * t,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _primaryColor.withOpacity((1 - t) * 0.6),
              width: 1.2,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCenterOrb() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _primaryColor.withOpacity(0.07),
        border: Border.all(color: _primaryColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.35),
            blurRadius: 28,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: _primaryColor.withOpacity(0.12),
            blurRadius: 60,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Icon(
              key: ValueKey(_isDetected),
              _isDetected ? Icons.lock_rounded : Icons.radar_rounded,
              size: 40,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 400),
            style: TextStyle(
              color: _primaryColor,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
            child: Text(_isDetected ? 'LOCKED' : 'SEARCH'),
          ),
        ],
      ),
    );
  }

  // ─── Status Banner ───────────────────────────────────────────────────────
  Widget _buildStatusBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          color: _primaryColor.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _primaryColor.withOpacity(0.22), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isDetected ? Icons.check_circle_outline : Icons.track_changes,
              color: _primaryColor.withOpacity(0.7),
              size: 15,
            ),
            const SizedBox(width: 10),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 400),
              style: TextStyle(
                color: _primaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
              child: Text(_statusText),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Metrics ─────────────────────────────────────────────────────────────
  Widget _buildMetrics() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _metricTile(
              icon: Icons.straighten_rounded,
              label: 'DISTANCE',
              value: _distance > 0 ? '${_distance.toStringAsFixed(2)}m' : '--',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _metricTile(
              icon: Icons.wifi_rounded,
              label: 'SIGNAL',
              value: '${_rssi}dBm',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _metricTile(
              icon: Icons.bluetooth_rounded,
              label: 'TX POWER',
              value: '${_txPower}dBm',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _metricTile(
              icon: Icons.sensors_rounded,
              label: 'BEACONS',
              value: '$_beaconCount',
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryColor.withOpacity(0.18), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: _primaryColor.withOpacity(0.55), size: 15),
          const SizedBox(height: 8),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              color: _primaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
            child: Text(value, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryColor.withOpacity(0.45),
              fontSize: 8,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sweep Painter ────────────────────────────────────────────────────────────
class _SweepPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _SweepPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius  = size.width / 2;
    final angle   = progress * 2 * pi - pi / 2;

    // Gradient arc trailing the sweep line
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle - pi / 1.5,
        endAngle:   angle,
        colors: [Colors.transparent, color.withOpacity(0.18)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, sweepPaint);

    // Sweep line
    final linePaint = Paint()
      ..color      = color.withOpacity(0.9)
      ..strokeWidth = 2
      ..strokeCap  = StrokeCap.round;
    canvas.drawLine(
      center,
      Offset(center.dx + cos(angle) * radius, center.dy + sin(angle) * radius),
      linePaint,
    );

    // Bright dot at tip
    canvas.drawCircle(
      Offset(center.dx + cos(angle) * radius, center.dy + sin(angle) * radius),
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.progress != progress || old.color != color;
}

// ─── Grid Painter ─────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  final Color color;

  const _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius  = size.width / 2;

    final paint = Paint()
      ..color      = color.withOpacity(0.13)
      ..strokeWidth = 1
      ..style      = PaintingStyle.stroke;

    // 3 concentric range rings
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, paint);
    }

    // Cardinal axes
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);

    // Diagonal axes
    final d = radius * cos(pi / 4);
    canvas.drawLine(Offset(center.dx - d, center.dy - d), Offset(center.dx + d, center.dy + d), paint);
    canvas.drawLine(Offset(center.dx + d, center.dy - d), Offset(center.dx - d, center.dy + d), paint);

    // Range labels on X axis
    final textStyle = TextStyle(
      color: color.withOpacity(0.35),
      fontSize: 9,
    );
    for (int i = 1; i <= 3; i++) {
      final label = '${i * 5}m';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx + radius * i / 3 + 3, center.dy + 4));
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}