import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(SmartRoomApp());

class SmartRoomApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: BeaconScannerScreen(),
    );
  }
}

class BeaconScannerScreen extends StatefulWidget {
  @override
  _BeaconScannerScreenState createState() => _BeaconScannerScreenState();
}

class _BeaconScannerScreenState extends State<BeaconScannerScreen> {
  StreamSubscription<RangingResult>? _streamRanging;
  final _region = Region(
    identifier: 'SmartRoom',
    proximityUUID: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825', // تأكد أن هذا نفس الـ UUID في اللابتوب
  );

  String _status = "بانتظار الأذونات...";
  int _rssi = -100;

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStart();
  }

  // دالة طلب الأذونات وتشغيل البلوتوث
  Future<void> _checkPermissionsAndStart() async {
    // 1. طلب إذن الموقع
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (statuses[Permission.location]!.isGranted) {
      _startScanning();
    } else {
      setState(() {
        _status = "يجب الموافقة على إذن الموقع ليعمل الرادار";
      });
    }
  }

  void _startScanning() async {
    try {
      await flutterBeacon.initializeScanning;
      
      _streamRanging = flutterBeacon.ranging([_region]).listen((RangingResult result) {
        if (result.beacons.isNotEmpty) {
          final firstBeacon = result.beacons.first;
          setState(() {
            _rssi = firstBeacon.rssi;
            _status = _rssi > -65 ? "أنت داخل الغرفة الذكية (الوضع صامت)" : "أنت خارج الغرفة";
          });
        } else {
          setState(() {
            _rssi = -100;
            _status = "تبحث عن إشارة...";
          });
        }
      });
    } catch (e) {
      print("Error: $e");
    }
  }

  @override
  void dispose() {
    _streamRanging?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("رادار الغرفة الذكية")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _rssi > -65 ? Icons.location_on : Icons.location_off,
              size: 100,
              color: _rssi > -65 ? Colors.green : Colors.red,
            ),
            SizedBox(height: 20),
            Text(_status, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text("قوة الإشارة: $_rssi", style: TextStyle(fontSize: 18)),
            if (_rssi > -65)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text("🔈 جاري تحويل الهاتف للوضع الصامت...", style: TextStyle(color: Colors.blue)),
              ),
          ],
        ),
      ),
    );
  }
}