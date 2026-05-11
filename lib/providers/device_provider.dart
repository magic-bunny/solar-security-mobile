import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/device.dart';
import '../utils/constants.dart';

class DeviceProvider extends ChangeNotifier {
  List<Device> _devices = [];
  bool _loading = false;
  String? _token;

  List<Device> get devices => _devices;
  bool get loading => _loading;

  void setToken(String token) => _token = token;

  Future<void> loadDevices() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await http.get(
        Uri.parse('${ApiConstants.cloudApi}/devices?limit=100'),
        headers: {
          'Content-Type': 'application/json',
          if (_token != null) 'Authorization': _token!,
        },
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final List<dynamic> data = decoded is List ? decoded : (decoded['items'] ?? []);
        _devices = data.map((j) => Device.fromJson(j)).toList();
      } else {
        debugPrint('[DeviceProvider] API error: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[DeviceProvider] loadDevices failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Device? getDevice(String id) => _devices.where((d) => d.id == id).firstOrNull;
}
