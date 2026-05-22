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
  static const int _maxGuestsPerDevice = 5;
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  String? get _deviceId => context.read<ConnectionProvider>().activeDeviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _token() => context.read<AuthProvider>().getIdToken();

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  int get _guestCount =>
      _users.where((u) => (u['role'] ?? 'viewer') != 'owner').length;

  bool _canManageUsers() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return false;
    if (user.role == 'admin') return true;
    if (user.role == 'owner') return true;
    return _users.any((u) => u['userId'] == user.id && u['role'] == 'owner');
  }

  Future<void> _load() async {
    final id = _deviceId;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final token = await _token();
      final res = await http.get(
        Uri.parse('${ApiConstants.cloudApi}/devices/$id/users'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': token
        },
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(json.decode(res.body));
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
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
    final email = (result['email'] ?? '').trim().toLowerCase();
    if (!_isValidEmail(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a valid email address')));
      }
      return;
    }
    try {
      final token = await _token();
      final res = await http.post(
        Uri.parse('${ApiConstants.cloudApi}/devices/$id/invite'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': token
        },
        body: json.encode({'email': email}),
      );
      final body = json.decode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res.statusCode == 200
                ? 'Invited $email'
                : body['error'] ?? 'Failed')));
        if (res.statusCode == 200) _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _remove(String userId) async {
    final id = _deviceId;
    if (id == null) return;
    try {
      final token = await _token();
      final res = await http.delete(
        Uri.parse('${ApiConstants.cloudApi}/devices/$id/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': token
        },
      );
      final body = res.body.isNotEmpty ? json.decode(res.body) : {};
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res.statusCode == 200
                ? 'User removed'
                : body['error'] ?? 'Failed')));
      }
      if (res.statusCode == 200) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<Map<String, String>?> _showInviteDialog() {
    final emailCtrl = TextEditingController();
    return showDialog<Map<String, String>>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Invite User'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                    onSubmitted: (value) =>
                        Navigator.pop(context, {'email': value})),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, {'email': emailCtrl.text}),
                    child: const Text('Invite')),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final canInvite = _canManageUsers();
    final limitReached = _guestCount >= _maxGuestsPerDevice;
    return Scaffold(
      appBar: AppBar(title: const Text('Shared Users')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _deviceId == null
              ? const Center(
                  child: Text('No active device',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('Guests $_guestCount/$_maxGuestsPerDevice',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey))),
                    if (_users.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child: Text('No shared users',
                                  style: TextStyle(color: Colors.grey)))),
                    ..._users.map((u) {
                      final role = u['role'] ?? 'viewer';
                      return ListTile(
                        leading: Icon(
                            role == 'owner'
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: role == 'owner' ? Colors.orange : null),
                        title:
                            Text(u['name'] ?? u['email'] ?? u['userId'] ?? ''),
                        subtitle: Text([
                          if (u['email'] != null) u['email'],
                          role
                        ].join(' • ')),
                        trailing: role != 'owner' && canInvite
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle,
                                    color: Colors.red),
                                onPressed: () => _remove(u['userId'] ?? ''))
                            : null,
                      );
                    }),
                  ])),
      floatingActionButton: _deviceId != null
          ? FloatingActionButton(
              onPressed: canInvite && !limitReached ? _invite : null,
              tooltip: !canInvite
                  ? 'Only admins or owners can invite'
                  : limitReached
                      ? 'Guest limit reached'
                      : 'Invite user',
              child: const Icon(Icons.person_add))
          : null,
    );
  }
}
