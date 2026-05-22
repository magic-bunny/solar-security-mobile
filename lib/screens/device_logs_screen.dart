import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  void initState() { super.initState(); _loadWithRetry(); }

  Future<void> _loadWithRetry() async {
    for (var i = 0; i < 10; i++) {
      final api = context.read<ConnectionProvider>().api;
      if (api.isConnected) { await _load(); return; }
      await Future.delayed(const Duration(seconds: 1));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _load() async {
    final api = context.read<ConnectionProvider>().api;
    debugPrint('[Logs] isConnected=${api.isConnected}');
    if (!api.isConnected) { setState(() => _loading = false); return; }
    try {
      final res = await api.getLogs(limit: 200);
      debugPrint('[Logs] got ${res.length} entries');
      if (mounted) setState(() { _logs = res; _loading = false; });
    } catch (e) {
      debugPrint('[Logs] error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR': return Colors.red;
      case 'WARNING': case 'WARN': return Colors.orange;
      case 'DEBUG': return Colors.grey;
      default: return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SBC Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              final text = _logs.map((l) => '${l['ts']} [${l['level']}] ${l['msg']}').join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('No logs', style: TextStyle(color: Colors.grey)))
              : Container(
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    reverse: true,
                    itemCount: _logs.length,
                    itemBuilder: (_, i) {
                      final log = _logs[_logs.length - 1 - i];
                      final level = (log['level'] as String?) ?? 'INFO';
                      final ts = (log['ts'] as String?) ?? '';
                      final msg = (log['msg'] as String?) ?? '';
                      final color = _levelColor(level);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${ts.length > 19 ? ts.substring(11, 19) : ts} ', style: const TextStyle(color: Colors.grey, fontFamily: 'Courier', fontSize: 11)),
                          TextSpan(text: '[$level] ', style: TextStyle(color: color, fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.bold)),
                          TextSpan(text: msg, style: TextStyle(color: color, fontFamily: 'Courier', fontSize: 11)),
                        ])),
                      );
                    },
                  ),
                ),
    );
  }
}
