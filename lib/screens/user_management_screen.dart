import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/connection_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/constants.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  String? get _deviceId => context.read<ConnectionProvider>().activeDeviceId;

  @override
  void initState() { super.initState(); _load(); }

  Future<String?> _token() => context.read<AuthProvider>().getIdToken();

  Future<void> _load() async {
    final id = _deviceId;
    if (id == null) { setState(() => _loading = false); return; }
    try {
      final token = await _token();
      final res = await http.get(
        Uri.parse('${ApiConstants.cloudApi}/devices/$id/users'),
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': token},
      );
      if (res.statusCode == 200 && mounted) {
        setState(() { _users = List<Map<String, dynamic>>.from(json.decode(res.body)); _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite() async {
    final id = _deviceId;
    if (id == null) return;
    final result = await _showInviteDialog();
    if (result == null) return;
    try {
      final token = await _token();
      final res = await http.post(
        Uri.parse('${ApiConstants.cloudApi}/devices/$id/invite'),
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': token},
        body: json.encode(result),
      );
      final body = json.decode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.statusCode == 200 ? 'Invited ${result['email']}' : body['error'] ?? 'Failed')));
        if (res.statusCode == 200) _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _remove(String userId) async {
    final id = _deviceId;
    if (id == null) return;
    try {
      final token = await _token();
      await http.delete(
        Uri.parse('${ApiConstants.cloudApi}/devices/$id/users/$userId'),
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': token},
      );
      _load();
    } catch (_) {}
  }

  Future<Map<String, String>?> _showInviteDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    return showDialog<Map<String, String>>(context: context, builder: (_) => AlertDialog(
      title: const Text('Invite User'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 8),
        TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, {'name': nameCtrl.text.trim(), 'email': emailCtrl.text.trim()}), child: const Text('Invite')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared Users')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _deviceId == null
              ? const Center(child: Text('No active device', style: TextStyle(color: Colors.grey)))
              : _users.isEmpty
                  ? const Center(child: Text('No shared users', style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        final role = u['role'] ?? 'viewer';
                        return ListTile(
                          leading: Icon(role == 'owner' ? Icons.admin_panel_settings : Icons.person, color: role == 'owner' ? Colors.orange : null),
                          title: Text(u['name'] ?? u['email'] ?? u['userId'] ?? ''),
                          subtitle: Text([if (u['email'] != null) u['email'], role].join(' • ')),
                          trailing: role != 'owner' ? IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => _remove(u['userId'] ?? '')) : null,
                        );
                      },
                    )),
      floatingActionButton: _deviceId != null ? FloatingActionButton(onPressed: _invite, child: const Icon(Icons.person_add)) : null,
    );
  }
}
