import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';

class DeviceLogsScreen extends StatefulWidget {
  const DeviceLogsScreen({super.key});
  @override
  State<DeviceLogsScreen> createState() => _DeviceLogsScreenState();
}

class _DeviceLogsScreenState extends State<DeviceLogsScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ConnectionProvider>().api;
    if (!api.isConnected) { setState(() => _loading = false); return; }
    try {
      final logs = await api.getLogs(limit: 100);
      if (mounted) setState(() { _logs = logs.reversed.toList(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _iconFor(String action) {
    if (action.contains('relay')) return Icons.power;
    if (action.contains('alarm')) return Icons.warning;
    if (action.contains('connect')) return Icons.wifi;
    if (action.contains('config')) return Icons.settings;
    if (action.contains('boot')) return Icons.power_settings_new;
    return Icons.article;
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.read<ConnectionProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Device Logs')),
      body: !conn.connected
          ? const Center(child: Text('Not connected', style: TextStyle(color: Colors.grey)))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? const Center(child: Text('No logs', style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final l = _logs[i];
                        final action = l['action'] ?? '';
                        final ts = (l['timestamp'] ?? '').toString();
                        final time = ts.length >= 19 ? ts.substring(11, 19) : ts;
                        return ListTile(
                          dense: true,
                          leading: Icon(_iconFor(action), size: 20),
                          title: Text(action, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: l['detail'] != null && l['detail'].toString().isNotEmpty ? Text(l['detail'].toString(), style: const TextStyle(fontSize: 12)) : null,
                          trailing: Text(time, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        );
                      },
                    )),
    );
  }
}
