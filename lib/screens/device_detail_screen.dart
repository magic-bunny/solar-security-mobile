import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../services/weather_cache.dart';
import '../providers/connection_provider.dart';
import '../providers/device_provider.dart';
import '../providers/auth_provider.dart';
import '../models/device.dart';
import '../utils/solar_utils.dart';
import '../utils/constants.dart';
import '../services/api_service.dart';

class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;
  final String? initialTab;
  const DeviceDetailScreen(
      {super.key, required this.deviceId, this.initialTab});
  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final ConnectionProvider _conn;

  Map<String, dynamic>? _status;
  Map<String, dynamic>? _weather;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _loadingUsers = false;
  bool _inviting = false;

  final List<RTCVideoRenderer> _renderers = [];
  bool _renderersReady = false;
  bool _renderersIniting = false;
  bool _dataLoaded = false;
  bool _prevConnected = false;
  int _prevStreamCount = 0;
  static const int _maxGuestsPerDevice = 5;

  ApiService get _api =>
      _conn.getConnection(widget.deviceId)?.api ?? ApiService();

  static const _tabNames = ['home', 'live', 'users', 'logs'];

  @override
  void initState() {
    super.initState();
    final idx = _tabNames.indexOf(widget.initialTab ?? '');
    _tabs =
        TabController(length: 4, vsync: this, initialIndex: idx >= 0 ? idx : 0);
    _tabs.addListener(_onTabChanged);
    _conn = context.read<ConnectionProvider>();
    _conn.setActiveDevice(widget.deviceId);
    _conn.addListener(_onConnChanged);
    _conn.ensureConnected(
        context.read<AuthProvider>(), context.read<DeviceProvider>());
    _load();
    _loadWeather();
    if (_tabs.index == 3) _loadUsers();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _conn.removeListener(_onConnChanged);
    _tabs.dispose();
    for (final r in _renderers) {
      r.srcObject = null;
      r.dispose();
    }
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.index == 2 && _users.isEmpty && !_loadingUsers) _loadUsers();
    if (_tabs.index == 3) _refreshLogs();
  }

  void _onConnChanged() {
    if (!mounted) return;
    final dc = _conn.getConnection(widget.deviceId);
    final isConnected = dc?.connected ?? false;
    final streams = dc?.remoteStreams ?? [];
    if (streams.isNotEmpty && !_renderersReady && !_renderersIniting)
      _initRenderers(streams);
    if (isConnected && !_dataLoaded) {
      _dataLoaded = true;
      _load();
    }
    // Sync pushed telemetry to _status (skip relay update during switch operation)
    if (dc?.latestTelemetry != null) {
      final inProtection = _switchLoading != null ||
          (_switchProtectUntil != null &&
              DateTime.now().isBefore(_switchProtectUntil!));
      if (inProtection) {
        final pushed = Map<String, dynamic>.from(dc!.latestTelemetry!);
        pushed['relay'] = _status?['relay'];
        _status = pushed;
      } else {
        _status = dc!.latestTelemetry;
      }
    }
    _prevConnected = isConnected;
    _prevStreamCount = streams.length;
    if (mounted) setState(() {});
  }

  Future<void> _initRenderers(List<MediaStream> streams) async {
    try {
      for (var i = _renderers.length; i < streams.length; i++) {
        final r = RTCVideoRenderer();
        await r.initialize();
        _renderers.add(r);
      }
      for (var i = 0; i < streams.length && i < _renderers.length; i++)
        _renderers[i].srcObject = streams[i];
    } catch (e) {
      debugPrint('[Live] initRenderers error: $e');
    }
    _renderersIniting = false;
    _renderersReady = _renderers.isNotEmpty;
    if (mounted) setState(() {});
  }

  Future<void> _initRenderersForCount(int count) async {
    try {
      for (var i = _renderers.length; i < count; i++) {
        final r = RTCVideoRenderer();
        await r.initialize();
        _renderers.add(r);
      }
    } catch (e) {
      debugPrint('[Live] initRenderers error: $e');
    }
    _renderersIniting = false;
    _renderersReady = _renderers.isNotEmpty;
    if (mounted) setState(() {});
  }

  Future<void> _loadWeather() async {
    final device = context.read<DeviceProvider>().getDevice(widget.deviceId);
    try {
      final w =
          await WeatherCache().get(device?.lat ?? 22.54, device?.lng ?? 114.06);
      if (mounted && w != null) setState(() => _weather = w);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.getDeviceStatus().catchError((_) => <String, dynamic>{}),
        _api.getHistory(limit: 50).catchError((_) => <Map<String, dynamic>>[]),
        _api.getLogs(limit: 200).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (mounted)
        setState(() {
          _status = results[0] as Map<String, dynamic>;
          _history = results[1] as List<Map<String, dynamic>>;
          _logs = (results[2] as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final token = await context.read<AuthProvider>().getIdToken();
      final res = await http.get(
        Uri.parse('${ApiConstants.cloudApi}/devices/${widget.deviceId}/users'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': token
        },
      );
      if (res.statusCode == 200 && mounted)
        setState(() =>
            _users = List<Map<String, dynamic>>.from(json.decode(res.body)));
    } catch (_) {}
    if (mounted) setState(() => _loadingUsers = false);
  }

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

  Future<void> _invite(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid email address')));
      return;
    }
    setState(() => _inviting = true);
    try {
      final token = await context.read<AuthProvider>().getIdToken();
      final res = await http.post(
        Uri.parse('${ApiConstants.cloudApi}/devices/${widget.deviceId}/invite'),
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
        if (res.statusCode == 200) _loadUsers();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Invite failed: $e')));
    }
    if (mounted) setState(() => _inviting = false);
  }

  Future<void> _removeUser(String userId) async {
    if (userId.isEmpty) return;
    try {
      final token = await context.read<AuthProvider>().getIdToken();
      final res = await http.delete(
        Uri.parse(
            '${ApiConstants.cloudApi}/devices/${widget.deviceId}/users/$userId'),
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
      if (res.statusCode == 200) _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Remove failed: $e')));
      }
    }
  }

  double _d(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final device = context.read<DeviceProvider>().getDevice(widget.deviceId);
    return Scaffold(
      appBar: AppBar(
        title: Text(device?.name ?? widget.deviceId),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          tabs: const [
            Tab(text: 'Home'),
            Tab(text: 'Live'),
            Tab(text: 'Users'),
            Tab(text: 'Logs')
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_dashboardTab(), _liveTab(), _usersTab(), _logsTab()]),
    );
  }

  // ── Dashboard Tab ──
  Widget _dashboardTab() {
    final mppt = _status?['mppt'] as Map<String, dynamic>? ?? {};
    final battV = _d(mppt['V']);
    final battI = _d(mppt['I']);
    final battPct = batteryPercentage(battV, systemVoltage: 12).toDouble();
    final panelW = _d(mppt['PPV']);
    final panelV = _d(mppt['VPV']);
    final loadW = (battV * battI.abs());
    final yieldToday = _d(mppt['H20']);
    final dev = context.read<DeviceProvider>().getDevice(widget.deviceId);
    final switches =
        dev?.subDevices.where((s) => s.type == 'RELAY').toList() ?? [];
    final relay =
        (_status?['relay'] as List?)?.map((e) => e == true).toList() ??
            List.filled(switches.length, false);
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_weather != null)
            _weatherCard()
          else
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Weather: loading...'))),
          const SizedBox(height: 12),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Battery',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _metric(
                                  '${battV.toStringAsFixed(1)}V', 'Voltage'),
                              _metric('${battPct.toStringAsFixed(0)}%', 'SOC'),
                              _metric('${panelW.toStringAsFixed(0)}W', 'Panel'),
                              _metric('${loadW.toStringAsFixed(1)}W', 'Load'),
                            ]),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                            value: (battPct / 100).clamp(0, 1),
                            color: battPct > 50
                                ? Colors.green
                                : battPct > 20
                                    ? Colors.orange
                                    : Colors.red,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4)),
                        const SizedBox(height: 4),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Panel: ${panelV.toStringAsFixed(1)}V',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text(
                                  'Yield: ${yieldToday.toStringAsFixed(2)} kWh',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ]),
                      ]))),
          const SizedBox(height: 12),
          _sbcPerformanceCard(),
          const SizedBox(height: 12),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Device Control',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        ...List.generate(switches.length, (i) {
                          final sw = switches[i];
                          final isOn = relay.length > i ? relay[i] : false;
                          return SwitchListTile(
                              secondary: _switchLoading == i
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Icon(Icons.power_settings_new,
                                      color: isOn ? Colors.green : Colors.grey),
                              title: Text(sw.name),
                              value: isOn,
                              onChanged: _switchLoading != null
                                  ? null
                                  : (v) => _confirmSwitch(i, sw.name, v));
                        }),
                        if (switches.isEmpty)
                          const Text('No devices configured',
                              style: TextStyle(color: Colors.grey)),
                      ]))),
        ]));
  }

  int? _switchLoading;
  DateTime? _switchProtectUntil;

  Future<void> _refreshLogs() async {
    try {
      final res = await _api.getLogs(limit: 200);
      if (mounted)
        setState(() =>
            _logs = (res is List) ? res.cast<Map<String, dynamic>>() : []);
    } catch (_) {}
  }

  Future<void> _confirmSwitch(int index, String name, bool newState) async {
    final action = newState ? 'turn ON' : 'turn OFF';
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('$action $name?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(action)),
              ],
            ));
    if (confirmed != true) return;
    setState(() => _switchLoading = index);
    try {
      await _api.setRelay(index + 1, newState);
      if (mounted)
        setState(() {
          if (_status?['relay'] is List &&
              (_status!['relay'] as List).length > index)
            (_status!['relay'] as List)[index] = newState;
          _switchProtectUntil = DateTime.now().add(const Duration(seconds: 6));
        });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _switchLoading = null);
    }
  }

  Widget _weatherCard() {
    final hourly = _weather!['hourly'] as Map<String, dynamic>? ?? {};
    final times = (hourly['time'] as List?)?.cast<String>() ?? [];
    final now = DateTime.now().toIso8601String().substring(0, 13);
    var idx = times.indexWhere((t) => t.startsWith(now));
    if (idx < 0) idx = 0;
    final temps = (hourly['temperature_2m'] as List?) ?? [];
    final humids = (hourly['relative_humidity_2m'] as List?) ?? [];
    final codes = (hourly['weather_code'] as List?) ?? [];
    final temp =
        idx < temps.length ? '${(temps[idx] as num).toStringAsFixed(1)}' : '--';
    final humid = idx < humids.length ? '${humids[idx]}%' : '--';
    final code = idx < codes.length ? (codes[idx] as num).toInt() : 0;
    final icon = code == 0
        ? Icons.wb_sunny
        : code <= 3
            ? Icons.cloud
            : code <= 49
                ? Icons.foggy
                : code <= 69
                    ? Icons.grain
                    : code <= 79
                        ? Icons.ac_unit
                        : code <= 99
                            ? Icons.thunderstorm
                            : Icons.cloud;
    final label = code == 0
        ? 'Clear'
        : code <= 3
            ? 'Partly cloudy'
            : code <= 49
                ? 'Fog'
                : code <= 59
                    ? 'Drizzle'
                    : code <= 69
                        ? 'Rain'
                        : code <= 79
                            ? 'Snow'
                            : code <= 99
                                ? 'Thunderstorm'
                                : 'Unknown';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(icon, size: 32, color: Colors.orange),
              const SizedBox(width: 12),
              Text('$temp°',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 12)),
                    Text('Humidity: $humid',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
              const Spacer(),
              Text(DateFormat('EEE, MMM d').format(DateTime.now()),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ])));
  }

  Widget _metric(String value, String label) => Column(children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]);

  Map<String, dynamic>? _sbcStatsForHome() {
    final stats = _conn.getConnection(widget.deviceId)?.sbcStats;
    if (stats == null || stats.isEmpty) return null;
    if (stats['cpu'] is Map) return Map<String, dynamic>.from(stats);
    final device = context.read<DeviceProvider>().getDevice(widget.deviceId);
    final keys = <String>[
      ...?device?.config?.sbcCameras.keys.where((k) => k.isNotEmpty),
      'sbc',
      'sbc-0',
    ];
    for (final key in keys) {
      final value = stats[key];
      if (value is Map && value['cpu'] is Map) {
        return Map<String, dynamic>.from(value);
      }
    }
    for (final value in stats.values) {
      if (value is Map && value['cpu'] is Map) {
        return Map<String, dynamic>.from(value);
      }
    }
    return null;
  }

  Widget _sbcPerformanceCard() {
    final stats = _sbcStatsForHome();
    Map<String, dynamic> statMap(String key) =>
        stats?[key] is Map ? Map<String, dynamic>.from(stats![key]) : {};
    final cpu = statMap('cpu');
    final npu = statMap('npu');
    final mem = statMap('mem');
    final disk = statMap('disk');
    final temp = statMap('temp');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('SBC Performance',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Icon(stats == null ? Icons.sync_problem : Icons.memory,
                    size: 18,
                    color: stats == null ? Colors.orange : Colors.cyan),
              ]),
              const SizedBox(height: 12),
              if (stats == null)
                const Text('Waiting for SBC stats...',
                    style: TextStyle(color: Colors.grey, fontSize: 12))
              else ...[
                _statBar('CPU', cpu['usage'] ?? 0,
                    '${cpu['usage'] ?? 0}% (${cpu['cores'] ?? 0} cores)'),
                _statBar('NPU', npu['load'] ?? 0,
                    '${npu['load'] ?? 0}% @ ${npu['freq_mhz'] ?? 0}MHz'),
                _statBar('Memory', mem['usage'] ?? 0,
                    '${mem['used_mb'] ?? 0}/${mem['total_mb'] ?? 0} MB'),
                _statBar('Disk', disk['usage'] ?? 0,
                    '${disk['used_gb'] ?? 0}/${disk['total_gb'] ?? 0} GB'),
                if (temp.isNotEmpty)
                  _statBar('Temp', _d(temp['max']), '${temp['max'] ?? '--'}°C'),
              ],
            ])));
  }

  Widget _statBar(String label, num value, String detail) {
    final pct = value.toDouble().clamp(0, 100) / 100;
    final color = pct > 0.8
        ? Colors.red
        : pct > 0.5
            ? Colors.orange
            : Colors.cyan;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
              width: 48,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey))),
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                      color: color,
                      minHeight: 8))),
          const SizedBox(width: 8),
          SizedBox(
              width: 120,
              child: Text(detail,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.right)),
        ]));
  }

  // ── Live Tab ──
  Widget _liveTab() {
    final dc = _conn.getConnection(widget.deviceId);
    final device = context.read<DeviceProvider>().getDevice(widget.deviceId);
    final cams = device?.cameras ?? [];
    final streamMap = dc?.sbcWebrtc?.remoteStreams ?? {};

    if (cams.isEmpty) {
      return const Center(
          child: Text('No cameras configured',
              style: TextStyle(color: Colors.grey)));
    }

    // Always layout based on config camera count
    final count = cams.length;
    final cols = count <= 3
        ? 1
        : count <= 4
            ? 2
            : count <= 9
                ? 3
                : 4;
    final rows = (count / cols).ceil();

    // Ensure enough renderers for all config cameras
    if (_renderers.length < count && !_renderersIniting) {
      _renderersIniting = true;
      _initRenderersForCount(count);
    }

    // Bind streams to renderers where available
    // Group cameras by SBC, build session keys matching connection_provider
    final sbcGroups = <String, List<SubDevice>>{};
    for (final cam in cams) {
      sbcGroups.putIfAbsent(cam.parentId ?? '', () => []).add(cam);
    }
    final camKeys = <String>[];
    for (final entry in sbcGroups.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final camId = entry.value[i].id;
        camKeys.add(entry.key.isNotEmpty ? '${entry.key}:$camId' : camId);
      }
    }
    for (var i = 0; i < camKeys.length && i < _renderers.length; i++) {
      final stream = streamMap[camKeys[i]];
      if (stream != null && _renderers[i].srcObject != stream)
        _renderers[i].srcObject = stream;
    }

    final aiEvents = dc?.aiEvents ?? [];
    return Column(children: [
      Expanded(
          flex: 3,
          child: Column(
              children: List.generate(
                  rows,
                  (row) => Expanded(
                          child: Row(
                              children: List.generate(cols, (col) {
                        final idx = row * cols + col;
                        if (idx >= count)
                          return const Expanded(child: SizedBox());
                        final camKey =
                            idx < camKeys.length ? camKeys[idx] : 'cam$idx';
                        final label = cams[idx].name;
                        final camId = cams[idx].id;
                        final hasStream = streamMap.containsKey(camKey);
                        final isDisconnected = hasStream &&
                            (dc?.sbcWebrtc?.cameraDisconnected(camKey) ??
                                false);
                        return Expanded(
                            child: Container(
                                margin: const EdgeInsets.all(1),
                                color: Colors.black,
                                child: Stack(fit: StackFit.expand, children: [
                                  // Video or placeholder
                                  if (hasStream && idx < _renderers.length)
                                    RTCVideoView(_renderers[idx],
                                        objectFit: RTCVideoViewObjectFit
                                            .RTCVideoViewObjectFitContain)
                                  else
                                    const Center(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                          SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.grey)),
                                          SizedBox(height: 6),
                                          Text('Connecting...',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11)),
                                        ])),
                                  // Disconnected overlay (below controls)
                                  if (isDisconnected)
                                    Positioned.fill(
                                        child: Container(
                                            color: Colors.black54,
                                            child: const Center(
                                                child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                  Icon(Icons.signal_wifi_off,
                                                      color: Colors.orange,
                                                      size: 32),
                                                  SizedBox(height: 4),
                                                  Text('Reconnecting...',
                                                      style: TextStyle(
                                                          color: Colors.orange,
                                                          fontSize: 12)),
                                                ])))),
                                  // Camera name (always on top)
                                  Positioned(
                                      left: 4,
                                      top: 4,
                                      child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(4)),
                                          child: Text(label,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10)))),
                                  // Recordings button (always on top)
                                  Positioned(
                                      right: 4,
                                      top: 4,
                                      child: GestureDetector(
                                        onTap: () => context.push(
                                            '/recordings?camera=$camId&name=${Uri.encodeComponent(label)}'),
                                        child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius:
                                                    BorderRadius.circular(4)),
                                            child: const Icon(
                                                Icons.video_library,
                                                color: Colors.white70,
                                                size: 16)),
                                      )),
                                ])));
                      })))))),
      if (aiEvents.isNotEmpty)
        Expanded(
            flex: 1,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text('AI Detections',
                      style: Theme.of(context).textTheme.titleSmall)),
              Expanded(
                  child: ListView.builder(
                itemCount: aiEvents.length,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemBuilder: (_, i) {
                  final e = aiEvents[i];
                  final cls = e['class_name'] ?? e['label'] ?? 'unknown';
                  final conf =
                      ((e['confidence'] ?? 0) * 100).toStringAsFixed(0);
                  final cam = e['camera_id'] ?? '';
                  final ts = e['timestamp'];
                  final time = ts is num
                      ? DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt())
                          .toString()
                          .substring(11, 19)
                      : '$ts';
                  final icon = cls.contains('person')
                      ? Icons.person
                      : cls.contains('vehicle') || cls.contains('car')
                          ? Icons.directions_car
                          : Icons.smart_toy;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(icon, size: 20, color: Colors.amber),
                    title: Text('$cls ($conf%)',
                        style: const TextStyle(fontSize: 13)),
                    subtitle: cam.isNotEmpty
                        ? Text(cam, style: const TextStyle(fontSize: 11))
                        : null,
                    trailing: Text(time,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
                  );
                },
              )),
            ])),
    ]);
  }

  // ── Device Tab ──
  Widget _deviceTab() {
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Sub-Devices', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._buildSubDeviceList(),
        ]));
  }

  List<Widget> _buildSubDeviceList() {
    final device = context.read<DeviceProvider>().getDevice(widget.deviceId);
    if (device == null || device.subDevices.isEmpty)
      return [const Text('No sub-devices')];
    return device.subDevices.map((sd) {
      final icon = sd.isSolar
          ? Icons.solar_power
          : sd.isCamera
              ? Icons.videocam
              : sd.isGPS
                  ? Icons.gps_fixed
                  : sd.isBME280
                      ? Icons.thermostat
                      : sd.isSBC
                          ? Icons.memory
                          : Icons.power;
      final color = sd.isSolar
          ? Colors.orange
          : sd.isCamera
              ? Colors.blue
              : sd.isGPS
                  ? Colors.green
                  : sd.isBME280
                      ? Colors.cyan
                      : sd.isSBC
                          ? Colors.purple
                          : Colors.grey;
      return Card(
          child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(sd.name),
        subtitle: Text([
          sd.type,
          if (sd.relayChannel != null) 'CH${sd.relayChannel}'
        ].join(' · ')),
        children: [
          ..._subDeviceDetail(sd),
        ],
      ));
    }).toList();
  }

  List<Widget> _subDeviceDetail(SubDevice sd) {
    final widgets = <Widget>[];
    if (sd.isSolar) {
      final m = _status?['mppt'] as Map<String, dynamic>?;
      if (m != null) {
        widgets.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _metric('${m['V']}V', 'Battery'),
                _metric('${m['I']}A', 'Current'),
                _metric('${m['PPV']}W', 'Panel'),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _metric('${m['VPV']}V', 'Panel V'),
                _metric('CS ${m['CS']}', 'State'),
                _metric('${m['H20'] ?? '--'}kWh', 'Today'),
              ]),
            ])));
      }
      widgets.add(ListTile(
          dense: true,
          title: const Text('View Charts'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => _MpptDetailPage(history: _history)))));
    } else if (sd.isBME280) {
      final b = _status?['bme280'] as Map<String, dynamic>?;
      if (b != null) {
        widgets.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metric('${b['temperature'] ?? '--'}°C', 'Temp'),
                  _metric('${b['humidity'] ?? '--'}%', 'Humidity'),
                  _metric('${b['pressure'] ?? '--'}hPa', 'Pressure'),
                ])));
      }
    } else if (sd.isGPS) {
      final g = _status?['gps'] as Map<String, dynamic>?;
      if (g != null) {
        widgets.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metric('${(g['lat'] as num?)?.toStringAsFixed(4) ?? '--'}',
                      'Lat'),
                  _metric('${(g['lon'] as num?)?.toStringAsFixed(4) ?? '--'}',
                      'Lon'),
                  _metric('${g['fix'] ?? '--'}', 'Fix'),
                ])));
      }
    } else if (sd.isSBC) {
      final conn = _conn.getConnection(widget.deviceId);
      final stats = conn?.sbcStats;
      // Find this SBC's stats by id
      final sbcData = stats?[sd.id] as Map<String, dynamic>? ??
          stats?.values.firstOrNull as Map<String, dynamic>?;
      if (sbcData != null) {
        final cpu = sbcData['cpu'] as Map<String, dynamic>? ?? {};
        final mem = sbcData['mem'] as Map<String, dynamic>? ?? {};
        final disk = sbcData['disk'] as Map<String, dynamic>? ?? {};
        final temp = sbcData['temp'] as Map<String, dynamic>? ?? {};
        final net = sbcData['net'] as Map<String, dynamic>? ?? {};
        final vpu = sbcData['vpu'] as Map<String, dynamic>? ?? {};
        final npu = sbcData['npu'] as Map<String, dynamic>? ?? {};
        final gpu = sbcData['gpu'] as Map<String, dynamic>? ?? {};
        widgets.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _statBar('CPU', cpu['usage'] ?? 0,
                  '${cpu['usage'] ?? 0}% (${cpu['cores'] ?? 0} cores)'),
              _statBar('Memory', mem['usage'] ?? 0,
                  '${mem['used_mb'] ?? 0}/${mem['total_mb'] ?? 0} MB'),
              _statBar('Disk', disk['usage'] ?? 0,
                  '${disk['used_gb'] ?? 0}/${disk['total_gb'] ?? 0} GB'),
              _statBar('VPU', (vpu['load'] ?? 0).toDouble(),
                  '${vpu['load'] ?? 0}% @ ${vpu['freq_mhz'] ?? 0}MHz'),
              _statBar('NPU', (npu['load'] ?? 0).toDouble(),
                  '${npu['load'] ?? 0}% @ ${npu['freq_mhz'] ?? 0}MHz'),
              _statBar('GPU', (gpu['load'] ?? 0).toDouble(),
                  '${gpu['load'] ?? 0}% @ ${gpu['freq_mhz'] ?? 0}MHz'),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _metric('${temp['max'] ?? '--'}°C', 'Temp'),
                _metric('${net['rx_kbps'] ?? 0} KB/s', 'Net RX'),
                _metric('${net['tx_kbps'] ?? 0} KB/s', 'Net TX'),
              ]),
            ])));
      } else {
        widgets.add(const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Waiting for stats...',
                style: TextStyle(color: Colors.grey, fontSize: 12))));
      }
    } else if (sd.isCamera) {
      final device = context.read<DeviceProvider>().getDevice(widget.deviceId);
      final camCfg = device?.config?.sbcCameras.values
          .expand((c) => c)
          .firstWhere((c) => c['id'] == sd.id || c['name'] == sd.name,
              orElse: () => {});
      if (camCfg != null && camCfg.isNotEmpty) {
        final tc = camCfg['transcode'] as Map<String, dynamic>? ?? {};
        final rec = camCfg['recording'] as Map<String, dynamic>? ?? {};
        final live = camCfg['live'] as Map<String, dynamic>? ?? {};
        widgets.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RTSP: ${camCfg['rtsp'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                Chip(
                    label: Text(
                        rec['enabled'] == true
                            ? 'Recording ON'
                            : 'Recording OFF',
                        style: const TextStyle(fontSize: 11)),
                    avatar: Icon(
                        rec['enabled'] == true
                            ? Icons.fiber_manual_record
                            : Icons.stop,
                        size: 14,
                        color:
                            rec['enabled'] == true ? Colors.red : Colors.grey),
                    visualDensity: VisualDensity.compact),
                Chip(
                    label: Text(
                        tc['enabled'] == true
                            ? 'Transcode ${tc['width']}×${tc['height']}'
                            : 'No Transcode',
                        style: const TextStyle(fontSize: 11)),
                    avatar: Icon(Icons.transform,
                        size: 14,
                        color:
                            tc['enabled'] == true ? Colors.cyan : Colors.grey),
                    visualDensity: VisualDensity.compact),
                if (live['enabled'] == true)
                  Chip(
                      label: Text(
                          '${((live['bitrate'] ?? 0) / 1000000).toStringAsFixed(1)} Mbps',
                          style: const TextStyle(fontSize: 11)),
                      avatar: const Icon(Icons.speed,
                          size: 14, color: Colors.green),
                      visualDensity: VisualDensity.compact),
              ]),
            ])));
      }
    } else if (sd.type == 'RELAY_8CH' || sd.name.contains('Relay')) {
      final relay = _status?['relay'] as List?;
      if (relay != null) {
        widgets.add(Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                  relay.length,
                  (i) => Chip(
                        avatar: Icon(
                            relay[i] == true ? Icons.power : Icons.power_off,
                            size: 16,
                            color:
                                relay[i] == true ? Colors.green : Colors.grey),
                        label: Text('CH${i + 1}',
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: relay[i] == true
                            ? Colors.green.withOpacity(0.15)
                            : null,
                      )),
            )));
      }
    }
    if (widgets.isEmpty) {
      widgets.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('No data yet',
              style: TextStyle(color: Colors.grey, fontSize: 12))));
    }
    return widgets;
  }

  // ── Users Tab ──
  Widget _usersTab() {
    final canInvite = _canManageUsers();
    final limitReached = _guestCount >= _maxGuestsPerDevice;
    return RefreshIndicator(
        onRefresh: _loadUsers,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Text('Device Users',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text('Guests $_guestCount/$_maxGuestsPerDevice',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            IconButton(
                icon: const Icon(Icons.person_add),
                tooltip: !canInvite
                    ? 'Only admins or owners can invite'
                    : limitReached
                        ? 'Guest limit reached'
                        : 'Invite user',
                onPressed: canInvite && !limitReached && !_inviting
                    ? _showInviteDialog
                    : null),
          ]),
          const SizedBox(height: 8),
          if (_loadingUsers)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator())),
          if (!_loadingUsers && _users.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No users',
                        style: TextStyle(color: Colors.grey)))),
          ..._users.map((u) => Card(
                  child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(u['name'] ?? u['email'] ?? ''),
                subtitle: Text(u['email'] ?? ''),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(u['role'] ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if ((u['role'] ?? 'viewer') != 'owner' && canInvite)
                    IconButton(
                        icon:
                            const Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _removeUser(u['userId'] ?? '')),
                ]),
              ))),
        ]));
  }

  void _showInviteDialog() {
    final emailCtl = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Invite User'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: emailCtl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                    onSubmitted: (value) {
                      Navigator.pop(ctx);
                      _invite(value);
                    }),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: _inviting
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _invite(emailCtl.text);
                          },
                    child: const Text('Invite')),
              ],
            ));
  }

  // ── Logs Tab ──
  Widget _logsTab() {
    final dc = _conn.getConnection(widget.deviceId);
    final logs = dc?.logs ?? [];
    if (logs.isEmpty)
      return const Center(
          child: Text('Waiting for logs...',
              style: TextStyle(color: Colors.grey)));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : const Color(0xFFF5F5F5);
    final tsColor = isDark ? const Color(0xFF858585) : const Color(0xFF999999);
    final infoColor =
        isDark ? const Color(0xFF4EC9B0) : const Color(0xFF008060);
    final errorColor = isDark ? Colors.red : const Color(0xFFD32F2F);
    final warnColor = isDark ? Colors.orange : const Color(0xFFE65100);
    final debugColor =
        isDark ? const Color(0xFF666666) : const Color(0xFFBBBBBB);

    return Container(
      color: bg,
      padding: const EdgeInsets.all(8),
      child: ListView.builder(
        reverse: true,
        itemCount: logs.length,
        itemBuilder: (_, i) {
          final log = logs[logs.length - 1 - i];
          final level = (log['level'] as String?) ?? 'INFO';
          final ts = (log['ts'] as String?) ?? '';
          final msg = (log['msg'] ?? log['message'] ?? '') as String;
          final timeStr = ts.length > 19 ? ts.substring(11, 19) : ts;
          final color = level.toUpperCase() == 'ERROR'
              ? errorColor
              : level.toUpperCase() == 'WARNING' ||
                      level.toUpperCase() == 'WARN'
                  ? warnColor
                  : level.toUpperCase() == 'DEBUG'
                      ? debugColor
                      : infoColor;
          return Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$timeStr ',
                  style: TextStyle(
                      color: tsColor, fontFamily: 'Courier', fontSize: 11)),
              TextSpan(
                  text: '[$level] ',
                  style: TextStyle(
                      color: color,
                      fontFamily: 'Courier',
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              TextSpan(
                  text: msg,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.85),
                      fontFamily: 'Courier',
                      fontSize: 11)),
            ])),
          );
        },
      ),
    );
  }
}

class _MpptDetailPage extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _MpptDetailPage({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty)
      return Scaffold(
          appBar: AppBar(title: const Text('MPPT Solar')),
          body: const Center(child: Text('No solar data')));
    final sorted = List<Map<String, dynamic>>.from(history)
      ..sort((a, b) => a['ts'].toString().compareTo(b['ts'].toString()));
    final times = sorted
        .map((r) => DateTime.tryParse(r['ts'].toString()) ?? DateTime.now())
        .toList();
    double v(Map<String, dynamic> r, String k) =>
        (r[k] as num?)?.toDouble() ?? 0;

    LineChartBarData line(double Function(Map<String, dynamic>) fn, Color c) {
      final spots = <FlSpot>[];
      for (var i = 0; i < sorted.length; i++)
        spots.add(
            FlSpot(times[i].millisecondsSinceEpoch.toDouble(), fn(sorted[i])));
      return LineChartBarData(
          spots: spots,
          isCurved: true,
          color: c,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData:
              BarAreaData(show: true, color: c.withValues(alpha: 0.1)));
    }

    Widget chart(String title, List<LineChartBarData> lines) {
      final fmt = DateFormat('HH:mm');
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    SizedBox(
                        height: 180,
                        child: LineChart(LineChartData(
                          lineBarsData: lines,
                          gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (_) => FlLine(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                  strokeWidth: 0.5)),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 28,
                                    interval: times.length > 1
                                        ? (times.last.millisecondsSinceEpoch -
                                                times.first
                                                    .millisecondsSinceEpoch) /
                                            4
                                        : null,
                                    getTitlesWidget: (val, _) => Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child:
                                            Text(fmt.format(DateTime.fromMillisecondsSinceEpoch(val.toInt())),
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey))))),
                            leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    getTitlesWidget: (val, _) => Text(
                                        val.toStringAsFixed(1),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey)))),
                          ),
                          borderData: FlBorderData(show: false),
                          lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                  getTooltipItems: (spots) => spots
                                      .map((s) => LineTooltipItem(
                                          '${s.y.toStringAsFixed(2)}',
                                          TextStyle(
                                              color: s.bar.color,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)))
                                      .toList())),
                        ))),
                  ])));
    }

    return Scaffold(
        appBar: AppBar(title: const Text('MPPT Solar')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          chart('Battery Voltage & Current', [
            line((r) => v(r, 'V'), Colors.blue),
            line((r) => v(r, 'I'), Colors.orange)
          ]),
          const SizedBox(height: 16),
          chart('Panel Voltage & Power', [
            line((r) => v(r, 'VPV'), Colors.purple),
            line((r) => v(r, 'PPV'), Colors.green)
          ]),
          const SizedBox(height: 16),
          chart('Battery Power',
              [line((r) => v(r, 'V') * v(r, 'I').abs(), Colors.red)]),
          const SizedBox(height: 16),
          chart('Temperature & Humidity', [
            line((r) => v(r, 'temperature'), Colors.red),
            line((r) => v(r, 'humidity'), Colors.cyan)
          ]),
        ]));
  }
}
