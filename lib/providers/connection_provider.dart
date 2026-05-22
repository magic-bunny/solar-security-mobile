import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/websocket_service.dart';
import '../services/webrtc_service.dart';
import '../models/device.dart';
import '../services/data_channel_service.dart';
import '../services/api_service.dart';
import '../providers/device_provider.dart';
import '../providers/auth_provider.dart';

/// Per-device P2P connection state.
class DeviceConnection {
  final String deviceId;
  final int cameraCount;
  // MCU data connection
  WebSocketService? ws;
  WebRTCService? webrtc;
  final dc = DataChannelService();
  final api = ApiService();
  StreamSubscription? dcSub;
  StreamSubscription? pushSub;
  // SBC video connection
  WebSocketService? sbcWs;
  WebRTCService? sbcWebrtc;
  final sbcDc = DataChannelService();
  StreamSubscription? streamSub;
  StreamSubscription? stateSub;
  bool connected = false;
  bool reconnecting = false;
  Timer? heartbeatTimer;
  // Live data
  final List<Map<String, dynamic>> alarms = [];
  final List<Map<String, dynamic>> aiEvents = [];
  final List<Map<String, dynamic>> logs = [];
  Map<String, dynamic>? latestTelemetry;
  Map<String, dynamic>? latestConfig;
  Map<String, dynamic>? sbcStats;
  bool hasNewAlarms = false;

  DeviceConnection({required this.deviceId, this.cameraCount = 4});

  List<MediaStream> get remoteStreams {
    final streams = sbcWebrtc?.remoteStreams ?? {};
    return streams.values.toList();
  }
}

enum ConnectionStatus { connecting, connected, reconnecting, disconnected }

class ConnectionProvider extends ChangeNotifier {
  final Map<String, DeviceConnection> _connections = {};
  String? _activeDeviceId;
  String? _token;
  AuthProvider? _authProvider;
  bool _notifyScheduled = false;
  bool _ensuring = false;
  VoidCallback? onConfigUpdated;
  DeviceProvider? _deviceProvider;

  void _safeNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  Map<String, DeviceConnection> get connections =>
      Map.unmodifiable(_connections);
  String? get activeDeviceId => _activeDeviceId;
  DeviceConnection? getConnection(String id) => _connections[id];
  ApiService get api => _connections[_activeDeviceId]?.api ?? ApiService();
  WebRTCService? get webrtc => _connections[_activeDeviceId]?.webrtc;
  bool get connected => _connections[_activeDeviceId]?.connected ?? false;

  ConnectionStatus statusOf(String id) {
    final c = _connections[id];
    if (c == null) return ConnectionStatus.disconnected;
    if (c.reconnecting) return ConnectionStatus.reconnecting;
    if (c.connected) return ConnectionStatus.connected;
    return ConnectionStatus.connecting;
  }

  void setActiveDevice(String id) => _activeDeviceId = id;

  /// Call from ANY page. Loads devices, gets token, connects all not-yet-connected.
  Future<void> ensureConnected(AuthProvider auth, DeviceProvider dp) async {
    if (_ensuring) return;
    _ensuring = true;
    try {
      _deviceProvider = dp;
      _authProvider = auth;
      if (dp.devices.isEmpty) await dp.loadDevices();
      _token = await auth.getIdToken() ?? 'dev-token';
      for (final d in dp.devices) {
        final existing = _connections[d.id];
        if (existing == null) {
          _connectDeviceInternal(
              token: _token!, deviceId: d.id, cameraCount: d.cameraCount);
        }
      }
    } finally {
      _ensuring = false;
    }
  }

  Future<void> connectDevice({
    required String token,
    required String deviceId,
    int cameraCount = 4,
  }) async {
    _token = token;
    await _connectDeviceInternal(
        token: token, deviceId: deviceId, cameraCount: cameraCount);
  }

  Future<void> _connectDeviceInternal({
    required String token,
    required String deviceId,
    int cameraCount = 4,
  }) async {
    await _disconnectDevice(deviceId);
    final conn = DeviceConnection(deviceId: deviceId, cameraCount: cameraCount);
    _connections[deviceId] = conn;
    _safeNotify();

    try {
      conn.ws = WebSocketService();
      conn.webrtc = WebRTCService(conn.ws!);

      // Handle Bridge-level messages (leave, id-taken)
      conn.ws!.messages.listen((msg) {
        debugPrint('[Conn] data WS msg: ${msg['action']} ${msg['type'] ?? ''}');
        final action = msg['action'];
        if (action == 'leave') {
          debugPrint('[Conn] Peer left $deviceId, scheduling reconnect');
          _onDisconnected(deviceId);
        } else if (action == 'id-taken') {
          debugPrint('[Conn] Session replaced for $deviceId, reconnecting');
          _onDisconnected(deviceId);
        }
      });

      conn.dcSub = conn.webrtc!.onDataChannel.listen((dc) {
        conn.dc.attach(dc);
        conn.api.attachDataChannel(conn.dc);
        conn.connected = true;
        conn.reconnecting = false;
        _startHeartbeat(conn);
        // Listen for push messages (telemetry, alarms)
        conn.pushSub = conn.dc.onPush.listen((msg) {
          final type = msg['type'];
          if (type == 'alarm') {
            conn.alarms.insert(0, msg);
            if (conn.alarms.length > 200) conn.alarms.removeLast();
            _safeNotify();
          } else if (type == 'alarm_new') {
            // MCU persisted alarm to SBC, notify UI to refresh
            conn.hasNewAlarms = true;
            _safeNotify();
          } else if (type == 'telemetry') {
            conn.latestTelemetry = msg;
            _safeNotify();
          } else if (type == 'logs') {
            final data = msg['data'] as List? ?? [];
            for (final l in data) {
              conn.logs.add(Map<String, dynamic>.from(l as Map));
            }
            if (conn.logs.length > 500) {
              conn.logs.removeRange(0, conn.logs.length - 500);
            }
            _safeNotify();
          } else if (type == 'config_updated') {
            debugPrint(
                '[Conn] Config updated for $deviceId, refreshing from Cloud API...');
            onConfigUpdated?.call();
            // Pull fresh device list from Cloud API
            () async {
              if (_deviceProvider != null) {
                await _deviceProvider!.loadDevices();
                final device = _deviceProvider!.devices
                    .where((d) => d.id == deviceId)
                    .firstOrNull;
                final newCameraCount = device?.cameraCount ?? conn.cameraCount;
                debugPrint(
                    '[Conn] New cameraCount=$newCameraCount for $deviceId');
                _safeNotify();
                Future.delayed(const Duration(seconds: 3), () async {
                  if (_connections.containsKey(deviceId)) {
                    if (_authProvider != null) {
                      _token = await _authProvider!.getIdToken() ?? _token;
                    }
                    _connectSbc(conn, _token!, deviceId, newCameraCount);
                  }
                });
              }
            }();
          } else if (type == 'sbc_stats') {
            conn.sbcStats = msg['data'] as Map<String, dynamic>?;
            _safeNotify();
          }
        });
        _safeNotify();
      });

      conn.streamSub = null;

      await conn.ws!.connect(token: token, deviceId: deviceId, purpose: 'data');
      debugPrint('[Conn] MCU WebSocket connected for $deviceId');
      await conn.webrtc!.connectData(deviceId);
      debugPrint('[Conn] MCU offer sent for $deviceId');

      // SBC video connection — non-blocking, don't hold up MCU
      _connectSbc(conn, token, deviceId, cameraCount);

      // A device is considered online only after the SBC data P2P channel opens.
      Future.delayed(const Duration(seconds: 12), () async {
        final c = _connections[deviceId];
        if (identical(c, conn) && !conn.connected) {
          debugPrint('[Conn] SBC DataChannel timeout for $deviceId');
          await _disconnectDevice(deviceId);
        }
      });
    } catch (e) {
      debugPrint('[Conn] Failed $deviceId: $e');
      _scheduleReconnect(deviceId);
    }
  }

  Future<void> _connectSbc(DeviceConnection conn, String token, String deviceId,
      int cameraCount) async {
    try {
      conn.sbcWs = WebSocketService();
      conn.sbcWebrtc = WebRTCService(conn.sbcWs!);
      conn.streamSub?.cancel();
      conn.streamSub =
          conn.sbcWebrtc!.onRemoteStreams.listen((_) => _safeNotify());
      conn.stateSub?.cancel();
      conn.stateSub = conn.sbcWebrtc!.onStateChange.listen((_) {
        _safeNotify();
      });
      await conn.sbcWs!
          .connect(token: token, deviceId: deviceId, purpose: 'video');
      debugPrint('[Conn] SBC connected, cameraCount=$cameraCount');
      // Connect cameras with sbcId for multi-SBC routing
      final device =
          _deviceProvider?.devices.where((d) => d.id == deviceId).firstOrNull;
      final cameras = device?.cameras ?? [];
      if (cameras.isNotEmpty) {
        // Group by SBC, each SBC's cameras indexed from 0
        final sbcGroups = <String, List<SubDevice>>{};
        for (final cam in cameras) {
          final sid = cam.parentId ?? '';
          sbcGroups.putIfAbsent(sid, () => []).add(cam);
        }
        for (final entry in sbcGroups.entries) {
          for (var i = 0; i < entry.value.length; i++) {
            final cam = entry.value[i];
            final sessionKey =
                entry.key.isNotEmpty ? '${entry.key}:${cam.id}' : cam.id;
            await conn.sbcWebrtc!.connectCamera(sessionKey,
                sbcId: entry.key.isNotEmpty ? entry.key : null,
                remoteCameraName: cam.id);
          }
        }
      } else {
        for (var i = 0; i < cameraCount; i++) {
          final camId = 'cam-${i + 1}';
          await conn.sbcWebrtc!
              .connectCamera(camId, remoteCameraName: camId);
        }
      }
    } catch (e) {
      debugPrint('[Conn] SBC failed $deviceId: $e');
    }
  }

  void _startHeartbeat(DeviceConnection conn) {
    conn.heartbeatTimer?.cancel();
    conn.heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (conn.ws?.isConnected == true) conn.ws!.send({'action': 'ping'});
    });
  }

  void _onDisconnected(String id) {
    final conn = _connections[id];
    if (conn == null) return;
    conn.connected = false;
    conn.reconnecting = true;
    conn.heartbeatTimer?.cancel();
    _safeNotify();
    _scheduleReconnect(id);
  }

  // ignore: unused_element
  Future<void> _reconnectMcu(String id) async {
    final conn = _connections[id];
    if (conn == null || _token == null) return;
    conn.connected = false;
    conn.heartbeatTimer?.cancel();
    conn.dcSub?.cancel();
    conn.pushSub?.cancel();
    await conn.webrtc?.disconnect();
    conn.webrtc?.dispose();
    await conn.ws?.disconnect();
    conn.ws?.dispose();
    // Rebuild MCU connection, keep SBC intact
    try {
      conn.ws = WebSocketService();
      conn.webrtc = WebRTCService(conn.ws!);
      conn.ws!.messages.listen((msg) {
        final action = msg['action'];
        if (action == 'leave' || action == 'id-taken') _onDisconnected(id);
      });
      conn.dcSub = conn.webrtc!.onDataChannel.listen((dc) {
        conn.dc.attach(dc);
        conn.api.attachDataChannel(conn.dc);
        conn.connected = true;
        conn.reconnecting = false;
        _startHeartbeat(conn);
        conn.pushSub?.cancel();
        conn.pushSub = conn.dc.onPush.listen((msg) {
          final type = msg['type'];
          if (type == 'alarm_new') {
            conn.hasNewAlarms = true;
            _safeNotify();
          } else if (type == 'telemetry') {
            conn.latestTelemetry = msg;
            _safeNotify();
          } else if (type == 'config_updated') {
            conn.latestConfig = msg;
            onConfigUpdated?.call();
            _safeNotify();
          } else if (type == 'sbc_stats') {
            conn.sbcStats = msg['data'] as Map<String, dynamic>?;
            _safeNotify();
          }
        });
        _safeNotify();
      });
      await conn.ws!.connect(token: _token!, deviceId: id, purpose: 'data');
      await conn.webrtc!.connectData(id);
    } catch (e) {
      debugPrint('[Conn] MCU reconnect failed $id: $e');
    }
  }

  void _scheduleReconnect(String id) {
    final conn = _connections[id];
    if (conn == null || _token == null) return;
    conn.reconnecting = true;
    _safeNotify();
    Future.delayed(const Duration(seconds: 3), () async {
      if (!_connections.containsKey(id)) return;
      await _connectDeviceInternal(
          token: _token!, deviceId: id, cameraCount: conn.cameraCount);
    });
  }

  Future<void> _disconnectDevice(String id) async {
    final conn = _connections.remove(id);
    if (conn == null) return;
    conn.connected = false;
    conn.heartbeatTimer?.cancel();
    conn.dcSub?.cancel();
    conn.pushSub?.cancel();
    conn.streamSub?.cancel();
    conn.stateSub?.cancel();
    conn.dc.dispose();
    conn.sbcDc.dispose();
    await conn.webrtc?.disconnect();
    conn.webrtc?.dispose();
    await conn.ws?.disconnect();
    conn.ws?.dispose();
    await conn.sbcWebrtc?.disconnect();
    conn.sbcWebrtc?.dispose();
    await conn.sbcWs?.disconnect();
    conn.sbcWs?.dispose();
  }

  Future<void> disconnectAll() async {
    for (final id in _connections.keys.toList()) {
      await _disconnectDevice(id);
    }
    _activeDeviceId = null;
    _token = null;
    _safeNotify();
  }

  @override
  void dispose() {
    disconnectAll();
    super.dispose();
  }
}
