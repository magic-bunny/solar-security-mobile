import 'data_channel_service.dart';

/// API service — sends requests via WebRTC DataChannel to MCU.
/// Actions must match MCU router.py exactly.
class ApiService {
  DataChannelService? _dc;

  void attachDataChannel(DataChannelService dc) => _dc = dc;
  bool get isConnected => _dc?.isOpen ?? false;

  Future<Map<String, dynamic>> _req(String action, [Map<String, dynamic>? params]) async {
    if (_dc == null) throw Exception('DataChannel not attached');
    return _dc!.request(action, params);
  }

  // --- Live telemetry (all sensors at once) ---
  Future<Map<String, dynamic>> getDeviceStatus() => _req('get_all');

  // --- Individual sensors ---
  Future<Map<String, dynamic>> getMppt() => _req('get_mppt');
  Future<Map<String, dynamic>> getBme280() => _req('get_bme280');
  Future<Map<String, dynamic>> getGps() => _req('get_gps');

  // --- Relay ---
  Future<Map<String, dynamic>> getRelayStatus() => _req('get_relay');
  Future<Map<String, dynamic>> setRelay(int channel, bool state) =>
      _req('set_relay', {'channel': channel, 'state': state});

  // --- Telemetry history (stored on SBC, queried via MCU) ---
  Future<List<Map<String, dynamic>>> getHistory({int limit = 100, String? since}) async {
    final params = <String, dynamic>{'limit': limit};
    if (since != null) params['since'] = since;
    final res = await _req('get_history', params);
    return (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  // --- Device logs ---
  Future<List<Map<String, dynamic>>> getLogs({int limit = 50}) async {
    final res = await _req('get_logs', {'limit': limit});
    return (res['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }
}
