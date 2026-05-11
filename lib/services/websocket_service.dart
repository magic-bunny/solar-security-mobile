import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/constants.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _pingTimer;

  String _deviceId = '';
  String _role = 'mobile';
  String _purpose = 'data';
  String _instanceId = '';

  Stream<Map<String, dynamic>> get messages => _controller.stream;
  bool get isConnected => _channel != null;

  static Future<String> _getOrCreateInstanceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('appInstanceId');
    if (id == null || id.isEmpty) {
      final rng = Random.secure();
      id = List.generate(8, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString('appInstanceId', id);
    }
    return id;
  }

  Future<void> connect({
    required String token,
    required String deviceId,
    String role = 'mobile',
    String purpose = 'data',
  }) async {
    _deviceId = deviceId;
    _role = role;
    _purpose = purpose;
    _instanceId = await _getOrCreateInstanceId();

    final uri = Uri.parse(BridgeConstants.wsUrl).replace(
      queryParameters: {
        'token': token,
        'deviceId': deviceId,
        'role': role,
        'purpose': purpose,
        'instanceId': _instanceId,
      },
    );
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    _channel!.stream.listen(
      (raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        _controller.add(msg);
      },
      onDone: () => _cleanup(),
      onError: (_) => _cleanup(),
    );

    // Heartbeat every 5 min to keep API GW connection alive
    _pingTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => send({'action': 'ping'}),
    );
  }

  void send(Map<String, dynamic> data) {
    if (_channel == null) return;
    // Inject self-identifying fields
    final enriched = {
      ...data,
      '_deviceId': _deviceId,
      '_role': _role,
      '_purpose': _purpose,
    };
    _channel?.sink.add(jsonEncode(enriched));
  }

  void sendSignal({
    required String type,
    String? sdp,
    Map<String, dynamic>? candidate,
    String? camera,
    String? sbcId,
  }) {
    send({
      'action': 'signal',
      'type': type,
      if (sdp != null) 'sdp': sdp,
      if (candidate != null) 'candidate': candidate,
      if (camera != null) 'camera': camera,
      if (sbcId != null) 'sbcId': sbcId,
    });
  }

  Future<void> disconnect() async {
    _cleanup();
    await _channel?.sink.close();
    _channel = null;
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
