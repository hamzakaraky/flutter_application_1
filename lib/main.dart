import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const RadarApp());
}

class RadarApp extends StatelessWidget {
  const RadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: const RadarScreen(),
    );
  }
}

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with TickerProviderStateMixin {
  // ─── Streams & Controllers ───────────────────────────────────────────────
  StreamSubscription<RangingResult>? _streamRanging;
  late final AnimationController _pulseController;
  late final AnimationController _sweepController;

  // ─── State ───────────────────────────────────────────────────────────────
  bool _isInside = false;
  double _distance = 0.0;
  int _rssi = -100;
  String _status = "Initializing Radar...";

  // ─── BLE Region ──────────────────────────────────────────────────────────
  final _region = Region(
    identifier: 'SmartRoom',
    proximityUUID: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
  );

  // ─── Computed Colors ─────────────────────────────────────────────────────
  Color get _activeColor =>
      _isInside ? Colors.cyanAccent : const Color(0xFF4FC3F7);

  // ─── Lifecycle ───────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _initPermissions();
  }

  @override
  void dispose() {
    _streamRanging?.cancel();
    _pulseController.dispose();
    _sweepController.dispose();
    super.dispose();
  }

  // ─── Permissions ─────────────────────────────────────────────────────────
  Future<void> _initPermissions() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (statuses[Permission.locationWhenInUse]!.isGranted) {
      _startRadar();
    } else {
      setState(() => _status = "Permission Denied");
    }
  }

  // ─── BLE Scanning ────────────────────────────────────────────────────────
  void _startRadar() async {
    setState(() => _status = "Scanning for Room...");

    try {
      await flutterBeacon.initializeScanning;

      _streamRanging = flutterBeacon.ranging([_region]).listen((result) {
        if (!mounted) return; // ✅ FIX: guard against disposed widget

        if (result.beacons.isNotEmpty) {
          final beacon = result.beacons.first;
          final newDistance = _calculateDistance(
            beacon.txPower ?? -59,
            beacon.rssi,
          );
          final wasInside = _isInside;

          setState(() {
            _rssi = beacon.rssi;
            _distance = newDistance;
            _isInside = newDistance > 0 && newDistance < 1.5;
            _status = _isInside
                ? "ROOM DETECTED • AUTO-SILENT ON"
                : "Scanning for Room...";
            // ✅ FIX: update duration BEFORE calling repeat()
            _pulseController.duration = _isInside
                ? const Duration(milliseconds: 600)
                : const Duration(seconds: 2);
          });

          // ✅ FIX: haptic only fires once on transition, not inside setState
          if (!wasInside && _isInside) {
            HapticFeedback.heavyImpact();
          }

          // ✅ FIX: restart after duration change, outside setState
          _pulseController.repeat();
        } else {
          if (mounted) {
            setState(() {
              _isInside = false;
              _status = "Scanning for Room...";
            });
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _status = "Hardware Error: $e");
    }
  }

  // ✅ FIX: cleaner formula, no unnecessary cast
  double _calculateDistance(int txPower, int rssi) {
    if (rssi == 0) return -1.0;
    final ratio = rssi / txPower;
    return ratio < 1.0
        ? pow(ratio, 10).toDouble()
        : 0.89976 * pow(ratio, 7.7095) + 0.111;
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea( // ✅ FIX: added SafeArea to avoid notch/status bar overlap
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildRadarSection()),
            _buildDataSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "SMART RADAR",
                style: TextStyle(
                  color: _activeColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              Text(
                "BLE PROXIMITY SYSTEM",
                style: TextStyle(
                  color: _activeColor.withOpacity(0.5),
                  fontSize: 10,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          _buildStatusBadge(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _activeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _activeColor.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _activeColor,
              boxShadow: _isInside
                  ? [BoxShadow(color: _activeColor, blurRadius: 6)]
                  : [],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isInside ? "ACTIVE" : "SCANNING",
            style: TextStyle(
              color: _activeColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Radar Section ───────────────────────────────────────────────────────
  Widget _buildRadarSection() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Staggered pulse rings (3 rings offset from each other)
          ...List.generate(3, _buildPulseRing),

          // Sweep line + gradient
          AnimatedBuilder(
            animation: _sweepController,
            builder: (_, __) => CustomPaint(
              size: const Size(280, 280),
              painter: _SweepPainter(_sweepController.value, _activeColor),
            ),
          ),

          // Static grid / crosshair
          CustomPaint(
            size: const Size(280, 280),
            painter: _GridPainter(_activeColor),
          ),

          // Center orb
          _buildCenterOrb(),
        ],
      ),
    );
  }

  Widget _buildPulseRing(int index) {
    final offset = index / 3.0;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final progress = (_pulseController.value + offset) % 1.0;
        return Container(
          width: 300 * progress,
          height: 300 * progress,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _activeColor.withOpacity((1 - progress) * 0.7),
              width: 1.5,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCenterOrb() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _activeColor.withOpacity(0.08),
        border: Border.all(color: _activeColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: _activeColor.withOpacity(0.4),
            blurRadius: 24,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: _activeColor.withOpacity(0.15),
            blurRadius: 48,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isInside ? Icons.lock_rounded : Icons.radar_rounded,
            size: 36,
            color: _activeColor,
          ),
          const SizedBox(height: 4),
          Text(
            _isInside ? "LOCKED" : "SEARCH",
            style: TextStyle(
              color: _activeColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Data Section ────────────────────────────────────────────────────────
  Widget _buildDataSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Status banner
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _activeColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _activeColor.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  color: _activeColor.withOpacity(0.7),
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  _status,
                  style: TextStyle(
                    color: _activeColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Metric tiles
          Row(
            children: [
              Expanded(
                child: _dataTile(
                  "DISTANCE",
                  _distance > 0 ? "${_distance.toStringAsFixed(2)}m" : "--",
                  Icons.straighten_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dataTile("SIGNAL", "${_rssi}dBm", Icons.wifi_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dataTile(
                  "STATUS",
                  _isInside ? "IN" : "OUT",
                  Icons.sensors_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dataTile(String label, String value, IconData icon) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: _activeColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _activeColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: _activeColor.withOpacity(0.6), size: 16),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: _activeColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: _activeColor.withOpacity(0.5),
              fontSize: 9,
              letterSpacing: 2,
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
    final radius = size.width / 2;
    final angle = progress * 2 * pi - pi / 2;

    // Trailing gradient arc
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle - pi / 2,
        endAngle: angle,
        colors: [Colors.transparent, color.withOpacity(0.25)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // Leading sweep line
    final linePaint = Paint()
      ..color = color.withOpacity(0.85)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(center.dx + cos(angle) * radius, center.dy + sin(angle) * radius),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.progress != progress;
}

// ─── Grid Painter ─────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  final Color color;

  const _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color.withOpacity(0.15)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Concentric range circles
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, paint);
    }

    // Cardinal lines
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);

    // Diagonal lines
    final d = radius * cos(pi / 4);
    canvas.drawLine(
      Offset(center.dx - d, center.dy - d),
      Offset(center.dx + d, center.dy + d),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + d, center.dy - d),
      Offset(center.dx - d, center.dy + d),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}