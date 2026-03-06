import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SmartRoomApp());
}

class SmartRoomApp extends StatelessWidget {
  const SmartRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // لون كحلي غامق احترافي
        fontFamily: 'Courier', // خط برمجي/رادار
      ),
      home: const AdvancedRadarScreen(),
    );
  }
}

class AdvancedRadarScreen extends StatefulWidget {
  const AdvancedRadarScreen({super.key});

  @override
  State<AdvancedRadarScreen> createState() => _AdvancedRadarScreenState();
}

class _AdvancedRadarScreenState extends State<AdvancedRadarScreen> with SingleTickerProviderStateMixin {
  StreamSubscription<RangingResult>? _streamRanging;
  late AnimationController _animationController;
  
  final _region = Region(
    identifier: 'SmartRoom',
    proximityUUID: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
  );

  bool _isInsideRoom = false;
  int _rssi = -100;
  double _distanceInMeters = 0.0;
  String _statusText = "جاري تهيئة الرادار...";

  @override
  void initState() {
    super.initState();
    // إعداد أنيميشن النبضات (الرادار)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _requestPermissionsAndStart();
  }

  Future<void> _requestPermissionsAndStart() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (statuses[Permission.locationWhenInUse]!.isGranted) {
      _startAdvancedScanning();
    } else {
      setState(() {
        _statusText = "الرادار معطل: نحتاج صلاحية الموقع!";
      });
    }
  }

  void _startAdvancedScanning() async {
    try {
      await flutterBeacon.initializeScanning;
      
      _streamRanging = flutterBeacon.ranging([_region]).listen((RangingResult result) {
        if (result.beacons.isNotEmpty) {
          final beacon = result.beacons.first;
          
          setState(() {
            _rssi = beacon.rssi;
            // حساب المسافة التقريبية بالأمتار
            _distanceInMeters = _calculateDistance(beacon.txPower ?? -59, _rssi);
            
            // إذا كانت المسافة أقل من 2 متر، نعتبره داخل الغرفة
            if (_distanceInMeters < 2.0 && _distanceInMeters > 0) {
              if (!_isInsideRoom) {
                HapticFeedback.heavyImpact(); // اهتزاز قوي عند دخول الغرفة
              }
              _isInsideRoom = true;
              _statusText = "تم الدخول: تفعيل الوضع الصامت للغرفة 🔕";
              _animationController.duration = const Duration(milliseconds: 500); // تسريع الرادار
              _animationController.repeat();
            } else {
              _isInsideRoom = false;
              _statusText = "يبحث عن الغرفة الذكية...";
              _animationController.duration = const Duration(seconds: 2); // تبطيء الرادار
              _animationController.repeat();
            }
          });
        } else {
          setState(() {
            _rssi = -100;
            _distanceInMeters = 0.0;
            _isInsideRoom = false;
            _statusText = "لا توجد إشارة...";
          });
        }
      });
    } catch (e) {
      setState(() {
        _statusText = "خطأ في البلوتوث: $e";
      });
    }
  }

  // دالة رياضية لحساب المسافة بناءً على قوة الإشارة
  double _calculateDistance(int txPower, int rssi) {
    if (rssi == 0) return -1.0; 
    double ratio = rssi * 1.0 / txPower;
    if (ratio < 1.0) {
      return pow(ratio, 10).toDouble();
    } else {
      return (0.89976 * pow(ratio, 7.7095) + 0.111);
    }
  }

  @override
  void dispose() {
    _streamRanging?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _isInsideRoom ? Colors.greenAccent : Colors.redAccent;

    return Scaffold(
      appBar: AppBar(
        title: const Text("SMART ROOM RADAR", style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // تصميم الرادار النبضي
            Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Container(
                      width: 250 * _animationController.value,
                      height: 250 * _animationController.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withOpacity(1 - _animationController.value),
                      ),
                    );
                  },
                ),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.2),
                    border: Border.all(color: color, width: 2),
                    boxShadow: [
                      BoxShadow(color: color.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)
                    ],
                  ),
                  child: Icon(
                    _isInsideRoom ? Icons.meeting_room : Icons.radar,
                    color: color,
                    size: 50,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 50),
            
            // لوحة البيانات (Dashboard)
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.bold),
                  ),
                  const Divider(color: Colors.white24, height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoColumn("المسافة", _distanceInMeters > 0 ? "${_distanceInMeters.toStringAsFixed(2)}m" : "--"),
                      _buildInfoColumn("قوة الإشارة", "$_rssi dBm"),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String title, String value) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }
}