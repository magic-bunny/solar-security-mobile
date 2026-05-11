import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';

class RelayControlScreen extends StatefulWidget {
  final String deviceId;
  const RelayControlScreen({super.key, required this.deviceId});
  @override
  State<RelayControlScreen> createState() => _RelayControlScreenState();
}

class _RelayControlScreenState extends State<RelayControlScreen> {
  List<bool> _states = List.filled(8, false);
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ConnectionProvider>().api;
    if (!api.isConnected) { setState(() => _loading = false); return; }
    try {
      final res = await api.getRelayStatus();
      final states = (res['states'] as List?)?.cast<bool>() ?? List.filled(8, false);
      if (mounted) setState(() { _states = states; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(int ch) async {
    final newState = !_states[ch];
    setState(() => _states[ch] = newState);
    try {
      await context.read<ConnectionProvider>().api.setRelay(ch + 1, newState);
    } catch (_) {
      setState(() => _states[ch] = !newState);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relay Control')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: 8,
              itemBuilder: (_, i) => SwitchListTile(
                title: Text('Channel ${i + 1}'),
                subtitle: Text(_states[i] ? 'ON' : 'OFF'),
                value: _states[i],
                onChanged: (_) => _toggle(i),
              ),
            ),
    );
  }
}
