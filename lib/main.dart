import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const RadarApp());
}

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

enum RadarState {
  initializing,
  permissionDenied,
  permissionPartial,
  bluetoothOff,
  scanning,
  detected,
  error,
}

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with TickerProviderStateMixin {

  static const _channel = MethodChannel('com.smartroom/focus');

  late final AnimationController _pulseController;
  late final AnimationController _sweepController;
  late final AnimationController _fadeController;
  late final AnimationController _detectedGlowController;

  StreamSubscription<RangingResult>? _streamRanging;
  final _region = Region(
    identifier: 'SmartRoom',
    proximityUUID: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
  );

  RadarState _state = RadarState.initializing;
  double _distance = 0.0;
  int _rssi = -100;
  int _txPower = -59;
  int _beaconCount = 0;
  String _errorMessage = '';
  bool _backgroundMonitoringActive = false;

  bool get _isDetected => _state == RadarState.detected;

  Color get _primaryColor =>
      _isDetected ? const Color(0xFF00FFCC) : const Color(0xFF4FC3F7);

  Color get _accentColor =>
      _isDetected ? const Color(0xFF00CC99) : const Color(0xFF0288D1);

  String get _statusText {
    switch (_state) {
      case RadarState.initializing:      return 'INITIALIZING...';
      case RadarState.permissionDenied:  return 'PERMISSION DENIED';
      case RadarState.permissionPartial: return 'NEED "ALWAYS" LOCATION';
      case RadarState.bluetoothOff:      return 'BLUETOOTH OFF';
      case RadarState.scanning:          return 'SCANNING FOR ROOM';
      case RadarState.detected:          return 'ROOM DETECTED • SILENT ON';
      case RadarState.error:             return 'ERROR: $_errorMessage';
    }
  }

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

    _detectedGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _channel.setMethodCallHandler(_handleNativeCall);
    _initPermissions();
  }

  @override
  void dispose() {
    _streamRanging?.cancel();
    _pulseController.dispose();
    _sweepController.dispose();
    _fadeController.dispose();
    _detectedGlowController.dispose();
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (!mounted) return null;

    switch (call.method) {
      case 'onRoomEntered':
        setState(() {
          _state = RadarState.detected;
          _beaconCount = max(_beaconCount, 1);
          _backgroundMonitoringActive = true;
        });
        _setPulseSpeed(fast: true);
        HapticFeedback.heavyImpact();
        break;

      case 'onRoomExited':
        setState(() {
          _state = RadarState.scanning;
          _beaconCount = 0;
          _distance = 0.0;
          _backgroundMonitoringActive = true;
        });
        _setPulseSpeed(fast: false);
        HapticFeedback.mediumImpact();
        break;

      case 'onPermissionChanged':
        final status = call.arguments as String? ?? '';
        if (status == 'denied' || status == 'restricted') {
          setState(() => _state = RadarState.permissionDenied);
        } else if (status == 'always') {
          setState(() => _backgroundMonitoringActive = true);
        }
        break;

      case 'onError':
        final error = call.arguments as String? ?? 'Unknown native error';
        if (_state != RadarState.detected) {
          setState(() {
            _errorMessage = error;
            _state = RadarState.error;
          });
        }
        break;
    }
    return null;
  }

  Future<void> _initPermissions() async {
    if (!mounted) return;

    await Permission.notification.request();

    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    var locationStatus = await Permission.locationWhenInUse.request();

    if (!mounted) return;

    if (locationStatus.isGranted) {
      await Future.delayed(const Duration(milliseconds: 500));
      final alwaysStatus = await Permission.locationAlways.request();

      if (!mounted) return;

      if (alwaysStatus.isGranted) {
        await _startNativeMonitoring();
        _startForegroundRanging();
      } else {
        setState(() => _state = RadarState.permissionPartial);
        await _startNativeMonitoring();
        _startForegroundRanging();
        _showAlwaysPermissionDialog();
      }
    } else {
      setState(() => _state = RadarState.permissionDenied);
    }
  }

  Future<void> _startNativeMonitoring() async {
    try {
      await _channel.invokeMethod('startMonitoring');
      if (mounted && _state == RadarState.initializing) {
        setState(() => _state = RadarState.scanning);
      }
    } catch (e) {
      if (mounted) setState(() => _state = RadarState.scanning);
    }
  }

  void _startForegroundRanging() async {
    try {
      await flutterBeacon.initializeAndCheckScanning;

      _streamRanging = flutterBeacon.ranging([_region]).listen(
        (result) {
          if (!mounted) return;

          if (result.beacons.isNotEmpty) {
            final beacon = result.beacons.first;
            final dist = _calcDistance(beacon.txPower ?? -59, beacon.rssi);

            setState(() {
              _rssi        = beacon.rssi;
              _txPower     = beacon.txPower ?? -59;
              _distance    = dist;
              _beaconCount = result.beacons.length;

              if (_state == RadarState.scanning && dist > 0 && dist < 1.5) {
                _state = RadarState.detected;
                _setPulseSpeed(fast: true);
                HapticFeedback.heavyImpact();
              } else if (_state == RadarState.detected && dist > 2.0) {
                _state = RadarState.scanning;
                _setPulseSpeed(fast: false);
              }
            });
          } else if (_state != RadarState.detected) {
            setState(() {
              _beaconCount = 0;
              if (_state == RadarState.scanning) _distance = 0.0;
            });
          }
        },
        onError: (dynamic e) {
          debugPrint('ranging error (non-fatal): $e');
        },
      );
    } on PlatformException catch (e) {
      if (e.code == 'BLUETOOTH_STATE' && mounted) {
        setState(() => _state = RadarState.bluetoothOff);
      }
    } catch (_) {}
  }

  void _setPulseSpeed({required bool fast}) {
    _pulseController.duration = fast
        ? const Duration(milliseconds: 500)
        : const Duration(seconds: 2);
    _pulseController.repeat();
  }

  double _calcDistance(int txPower, int rssi) {
    if (rssi == 0) return -1.0;
    final ratio = rssi / txPower;
    return ratio < 1.0
        ? pow(ratio, 10).toDouble()
        : 0.89976 * pow(ratio, 7.7095) + 0.111;
  }

  void _showAlwaysPermissionDialog() {
    if (!mounted) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '⚠️ Background Monitoring',
            style: TextStyle(color: Color(0xFF4FC3F7), fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'For automatic silent mode when the app is closed:\n\n'
            '1. Tap "Open Settings"\n'
            '2. Go to Location → Select "Always"\n\n'
            'Without this, monitoring only works when the app is open.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later', style: TextStyle(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text('Open Settings', style: TextStyle(color: Color(0xFF4FC3F7))),
            ),
          ],
        ),
      );
    });
  }

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
              if (_state == RadarState.permissionPartial) _buildWarningBanner(),
              Expanded(child: _buildRadar()),
              _buildStatusBanner(),
              const SizedBox(height: 14),
              _buildMetrics(),
              const SizedBox(height: 14),
              _buildSetupGuideButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Set Location to "Always" for background monitoring',
              style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: openAppSettings,
            child: const Text('Fix', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

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
                child: Text(_backgroundMonitoringActive
                    ? 'BLE PROXIMITY • BACKGROUND ACTIVE'
                    : 'BLE PROXIMITY SYSTEM v3'),
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
            child: Text(_isDetected ? 'LOCKED' : 'LIVE'),
          ),
        ],
      ),
    );
  }

  Widget _buildRadar() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _detectedGlowController,
            builder: (_, __) => AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _primaryColor.withOpacity(
                      _isDetected ? 0.06 + 0.05 * _detectedGlowController.value : 0.02,
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          ...List.generate(3, _buildPulseRing),
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

  Widget _buildMetrics() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(child: _metricTile(
            icon: Icons.straighten_rounded,
            label: 'DISTANCE',
            value: _distance > 0 ? '${_distance.toStringAsFixed(2)}m' : '--',
          )),
          const SizedBox(width: 10),
          Expanded(child: _metricTile(
            icon: Icons.wifi_rounded,
            label: 'SIGNAL',
            value: '${_rssi}dBm',
          )),
          const SizedBox(width: 10),
          Expanded(child: _metricTile(
            icon: Icons.bluetooth_rounded,
            label: 'TX PWR',
            value: '${_txPower}dBm',
          )),
          const SizedBox(width: 10),
          Expanded(child: _metricTile(
            icon: Icons.sensors_rounded,
            label: 'BEACONS',
            value: '$_beaconCount',
          )),
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
              fontSize: 15,
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

  Widget _buildSetupGuideButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _showSetupGuide,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_accentColor.withOpacity(0.15), _primaryColor.withOpacity(0.08)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _primaryColor.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_fix_high_rounded, color: _primaryColor, size: 16),
              const SizedBox(width: 10),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
                child: const Text('SETUP AUTO-SILENT GUIDE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSetupGuide() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SetupGuideSheet(
        primaryColor: _primaryColor,
        onOpenShortcuts: () async {
          Navigator.pop(ctx);
          try {
            await _channel.invokeMethod('openShortcuts');
          } catch (_) {}
        },
      ),
    );
  }
}

class _SetupGuideSheet extends StatelessWidget {
  final Color primaryColor;
  final VoidCallback onOpenShortcuts;

  const _SetupGuideSheet({
    required this.primaryColor,
    required this.onOpenShortcuts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A1628),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF1A3050), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '🤖 Full Automation Setup',
            style: TextStyle(
              color: primaryColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Complete these steps once — then silent mode activates automatically forever.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          _buildStep(number: '1', title: 'Allow "Always" Location',
            description: 'Settings → Smart Radar → Location → Always',
            icon: Icons.location_on_rounded, color: primaryColor),
          _buildStep(number: '2', title: 'Open Shortcuts App',
            description: 'Tap the button below to open the Shortcuts app',
            icon: Icons.auto_awesome_rounded, color: primaryColor),
          _buildStep(number: '3', title: 'Create Personal Automation',
            description: 'Automation → + → App → SmartRadar → "Is Opened"',
            icon: Icons.play_circle_outline_rounded, color: primaryColor),
          _buildStep(number: '4', title: 'Add Focus Action',
            description: 'Add Action → "Set Focus" → Do Not Disturb → On\nDisable "Ask Before Running"',
            icon: Icons.do_not_disturb_on_rounded, color: primaryColor),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withOpacity(0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber, size: 16),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'After setup: iOS triggers silent mode automatically when beacon is detected.',
                    style: TextStyle(color: Colors.amber, fontSize: 11, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onOpenShortcuts,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open Shortcuts App',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: const Color(0xFF020A18),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Center(
              child: Text(number,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 14),
                    const SizedBox(width: 6),
                    Text(title,
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(description,
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _SweepPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final angle  = progress * 2 * pi - pi / 2;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle - pi / 1.5,
        endAngle:   angle,
        colors: [Colors.transparent, color.withOpacity(0.18)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, sweepPaint);

    final linePaint = Paint()
      ..color      = color.withOpacity(0.9)
      ..strokeWidth = 2
      ..strokeCap  = StrokeCap.round;
    canvas.drawLine(
      center,
      Offset(center.dx + cos(angle) * radius, center.dy + sin(angle) * radius),
      linePaint,
    );

    canvas.drawCircle(
      Offset(center.dx + cos(angle) * radius, center.dy + sin(angle) * radius),
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.progress != progress || old.color != color;
}

class _GridPainter extends CustomPainter {
  final Color color;

  const _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..color      = color.withOpacity(0.13)
      ..strokeWidth = 1
      ..style      = PaintingStyle.stroke;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, paint);
    }

    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);

    final d = radius * cos(pi / 4);
    canvas.drawLine(Offset(center.dx - d, center.dy - d),
        Offset(center.dx + d, center.dy + d), paint);
    canvas.drawLine(Offset(center.dx + d, center.dy - d),
        Offset(center.dx - d, center.dy + d), paint);

    final textStyle = TextStyle(color: color.withOpacity(0.35), fontSize: 9);
    for (int i = 1; i <= 3; i++) {
      final tp = TextPainter(
        text: TextSpan(text: '${i * 5}m', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx + radius * i / 3 + 3, center.dy + 4));
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}