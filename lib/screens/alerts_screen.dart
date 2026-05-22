import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/device_provider.dart';

String _alarmDesc(Map<String, dynamic> a) {
  final sensor = a['sensor'] ?? '';
  final field = a['field'] ?? '';
  final bound = a['bound'] ?? '';
  final value = a['value'];
  final threshold = a['threshold'];
  final isLow = bound == 'min';
  switch ('$sensor.$field') {
    case 'mppt.V': return isLow ? 'Battery voltage dropped to ${value}V, below ${threshold}V minimum' : 'Battery voltage reached ${value}V, exceeding ${threshold}V limit';
    case 'mppt.I': return 'Battery current at ${value}A, ${isLow ? "below" : "above"} ${threshold}A threshold';
    case 'mppt.VPV': return isLow ? 'Solar panel voltage low at ${value}V' : 'Solar panel voltage high at ${value}V';
    case 'mppt.PPV': return isLow ? 'Solar output only ${value}W' : 'Solar output ${value}W';
    case 'bme280.temperature': return isLow ? 'Temperature dropped to ${value}°C' : 'Temperature reached ${value}°C';
    case 'bme280.humidity': return 'Humidity at ${value}%';
    case 'bme280.pressure': return 'Pressure at ${value}hPa';
    case 'gps.hspeed': return 'Device moving at ${value}m/s, exceeding ${threshold}m/s';
    default: return '${sensor.toUpperCase()} $field: $value (threshold: $threshold)';
  }
}

String _alarmTitle(Map<String, dynamic> a) {
  final sensor = a['sensor'] ?? '';
  final field = a['field'] ?? '';
  final bound = a['bound'] ?? '';
  final isLow = bound == 'min';
  switch ('$sensor.$field') {
    case 'mppt.V': return isLow ? '⚡ Low Battery Voltage' : '⚡ High Battery Voltage';
    case 'mppt.VPV': return '☀️ Panel Voltage ${isLow ? "Low" : "High"}';
    case 'mppt.PPV': return '☀️ Panel Power ${isLow ? "Low" : "High"}';
    case 'bme280.temperature': return isLow ? '🌡️ Low Temperature' : '🌡️ High Temperature';
    case 'gps.hspeed': return '📍 Speed Alert';
    default: return '⚠️ ${sensor.toUpperCase()} Alert';
  }
}

IconData _alarmIcon(Map<String, dynamic> a) {
  switch (a['sensor'] ?? '') {
    case 'mppt': return (a['field'] == 'V' || a['field'] == 'I') ? Icons.battery_alert : Icons.solar_power;
    case 'bme280': return a['field'] == 'temperature' ? Icons.thermostat : Icons.water_drop;
    case 'gps': return Icons.speed;
    default: return Icons.warning;
  }
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final List<Map<String, dynamic>> _alarms = [];
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _pageSize = 20;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAlarms());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_loading && _hasMore) {
      _loadAlarms();
    }
  }

  String? _getSbcUrl() {
    return null; // No longer used — alarms fetched via P2P DataChannel
  }

  Future<void> _loadAlarms({bool refresh = false}) async {
    if (_loading) return;
    if (refresh) { _offset = 0; _hasMore = true; _alarms.clear(); }
    setState(() => _loading = true);
    final base = _getSbcUrl();
    if (base != null) {
      try {
        final res = await http.get(Uri.parse('$base/alarms?unread=1&limit=$_pageSize&offset=$_offset'));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final data = (body['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
          setState(() {
            _alarms.addAll(data);
            _offset += data.length;
            _hasMore = data.length >= _pageSize;
          });
        }
      } catch (e) {
        debugPrint('[Alerts] Load failed: $e');
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _markRead(int id, int index) async {
    final base = _getSbcUrl();
    if (base != null) {
      try {
        await http.put(Uri.parse('$base/alarms/$id/read'));
        setState(() => _alarms.removeAt(index));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for alarm_new push
    final conn = context.watch<ConnectionProvider>();
    for (final c in conn.connections.values) {
      if (c.hasNewAlarms) {
        c.hasNewAlarms = false;
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadAlarms(refresh: true));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: _alarms.isEmpty && !_loading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.notifications_none, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text('No alerts', style: TextStyle(color: Colors.grey)),
            ]))
          : RefreshIndicator(
              onRefresh: () => _loadAlarms(refresh: true),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _alarms.length + (_hasMore ? 1 : 0),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (_, i) {
                  if (i >= _alarms.length) {
                    return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                  }
                  final a = _alarms[i];
                  final isLow = (a['bound'] ?? '') == 'min';
                  final color = isLow ? Colors.orange : Colors.red;
                  final ts = _formatTs(a['ts']);

                  return Dismissible(
                    key: ValueKey(a['id']),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red.withOpacity(0.2),
                      child: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    onDismissed: (_) => _markRead(a['id'] as int, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: color.withOpacity(0.15),
                          child: Icon(_alarmIcon(a), size: 18, color: color),
                        ),
                        title: Text(_alarmTitle(a), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(ts, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        children: [
                          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_alarmDesc(a), style: const TextStyle(fontSize: 14, height: 1.4)),
                              const SizedBox(height: 8),
                              Row(children: [
                                Icon(_alarmIcon(a), size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text('${a['sensor']}.${a['field']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                const Spacer(),
                                Text('${a['value']} / ${a['threshold']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ]),
                            ],
                          )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _formatTs(dynamic ts) {
    if (ts is String) {
      final dt = DateTime.tryParse(ts);
      if (dt != null) {
        final diff = DateTime.now().toUtc().difference(dt);
        if (diff.inSeconds < 60) return 'Just now';
        if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
        if (diff.inHours < 24) return '${diff.inHours}h ago';
        return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }
    return '$ts';
  }
}
