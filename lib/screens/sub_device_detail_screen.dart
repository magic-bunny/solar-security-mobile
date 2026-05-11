import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../widgets/gauge_widget.dart';

class SubDeviceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> info;
  const SubDeviceDetailScreen({super.key, required this.info});
  @override
  State<SubDeviceDetailScreen> createState() => _SubDeviceDetailScreenState();
}

class _SubDeviceDetailScreenState extends State<SubDeviceDetailScreen> {
  Map<String, dynamic>? _data;
  Timer? _timer;

  String get _type => widget.info['subDeviceType'] ?? widget.info['type'] ?? '';

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _fetch() async {
    final api = context.read<ConnectionProvider>().api;
    if (!api.isConnected) return;
    try {
      final action = _type == 'MPPT' ? 'get_mppt'
          : _type == 'BME280' ? 'get_bme280'
          : _type == 'GPS' ? 'get_gps' : null;
      if (action != null) {
        final res = await api.getDeviceStatus();
        if (mounted) setState(() => _data = res);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final color = _type == 'MPPT' ? Colors.orange
        : _type == 'BME280' ? Colors.blue
        : _type == 'GPS' ? Colors.green
        : _type == 'SBC' ? Colors.purple : Colors.grey;
    final icon = _type == 'MPPT' ? Icons.solar_power
        : _type == 'BME280' ? Icons.thermostat
        : _type == 'GPS' ? Icons.gps_fixed
        : _type == 'SBC' ? Icons.memory : Icons.device_hub;

    return Scaffold(
      appBar: AppBar(title: Text(widget.info['label'] ?? widget.info['name'] ?? _type)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: CircleAvatar(radius: 36, backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, size: 36, color: color))),
        const SizedBox(height: 16),
        _row('Type', _type),
        if (widget.info['channel'] != null) _row('Relay Channel', '${widget.info['channel']}'),
        const Divider(height: 24),
        if (_data == null) const Center(child: CircularProgressIndicator())
        else ..._buildLiveData(),
      ]),
    );
  }

  List<Widget> _buildLiveData() {
    if (_type == 'MPPT') {
      final m = _data?['mppt'] ?? {};
      return [
        _row('Battery Voltage', '${_v(m['V'])} V'),
        _row('Battery Current', '${_v(m['I'])} A'),
        _row('Panel Voltage', '${_v(m['VPV'])} V'),
        _row('Panel Power', '${_v(m['PPV'])} W'),
        _row('Charge State', _csLabel(m['CS'])),
        _row('Yield Today', '${_v(m['H20'])} kWh'),
        _row('Yield Total', '${_v(m['H19'])} kWh'),
      ];
    }
    if (_type == 'BME280') {
      final b = _data?['bme280'] ?? {};
      return [
        GaugeWidget(label: 'Temperature', value: _n(b['temperature']), max: 60, unit: '°C'),
        const SizedBox(height: 12),
        GaugeWidget(label: 'Humidity', value: _n(b['humidity']), max: 100, unit: '%'),
        const SizedBox(height: 12),
        GaugeWidget(label: 'Pressure', value: _n(b['pressure']), max: 1060, unit: 'hPa'),
      ];
    }
    if (_type == 'GPS') {
      final g = _data?['gps'] ?? {};
      return [
        _row('Latitude', '${_v(g['lat'])}'),
        _row('Longitude', '${_v(g['lon'])}'),
        _row('Altitude', '${_v(g['alt'])} m'),
        _row('Speed', '${_v(g['hspeed'])} m/s'),
        _row('Heading', '${_v(g['track'])}°'),
        if (g['gpsts'] != null) _row('GPS Time', '${g['gpsts']}'),
      ];
    }
    if (_type == 'SBC') {
      final online = _data?['sbc_online'] == true;
      return [
        _row('Status', online ? 'Online' : 'Offline'),
      ];
    }
    return [const Text('No data available')];
  }

  String _v(dynamic v) => v is num ? v.toStringAsFixed(2) : '—';
  double _n(dynamic v) => v is num ? v.toDouble() : 0;
  String _csLabel(dynamic cs) => switch (cs) { 0 => 'Off', 2 => 'Bulk', 3 => 'Absorption', 4 => 'Float', _ => '—' };

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
    ]),
  );
}
