import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() => runApp(const MaterialApp(home: SmartRoomApp()));

class SmartRoomApp extends StatefulWidget {
  const SmartRoomApp({super.key});
  @override
  State<SmartRoomApp> createState() => _SmartRoomAppState();
}

class _SmartRoomAppState extends State<SmartRoomApp> {
  final _ble = FlutterReactiveBle();
  StreamSubscription? _scanner;
  String _status = "ابحث عن غرفتك...";
  int _rssi = -100;

  // الـ UUID الخاص بك الذي أرسلته
  final String myRoomUUID = "AA8C0EC5-2CFE-43A3-88C8-A132B78752C1";

  void startScanning() async {
    // طلب الصلاحيات
    await [Permission.location, Permission.bluetoothScan, Permission.bluetoothConnect].request();

    setState(() => _status = "جاري المسح...");

    _scanner = _ble.scanForDevices(withServices: []).listen((device) {
      // فحص إذا كان الجهاز المكتشف هو الـ Beacon الخاص بك
      if (device.serviceUuids.any((uuid) => uuid.toString().toUpperCase() == myRoomUUID.toUpperCase()) || 
          device.id.contains("AA8C")) { 
        
        setState(() {
          _rssi = device.rssi;
          if (_rssi > -60) {
            _status = "أنت داخل الغرفة ✅ (تفعيل الصامت)";
          } else {
            _status = "أنت بعيد عن الغرفة ❌ (الوضع العادي)";
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("نظام الغرفة الذكية")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.room, size: 80, color: _rssi > -60 ? Colors.green : Colors.grey),
            const SizedBox(height: 20),
            Text(_status, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text("قوة الإشارة: $_rssi dBm"),
            const SizedBox(height: 30),
            ElevatedButton(onPressed: startScanning, child: const Text("ابدأ الرادار")),
          ],
        ),
      ),
    );
  }
}