import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Sends JSON requests over WebRTC DataChannel, returns responses.
class DataChannelService {
  RTCDataChannel? _dc;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _pushController = StreamController<Map<String, dynamic>>.broadcast();
  int _seq = 0;

  Stream<Map<String, dynamic>> get onPush => _pushController.stream;

  void attach(RTCDataChannel dc) {
    _dc = dc;
    dc.onMessage = (msg) {
      final data = jsonDecode(msg.text) as Map<String, dynamic>;
      final id = data['id']?.toString();
      if (id != null && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(data);
      } else {
        // Push message (telemetry, alarm, etc.)
        _pushController.add(data);
      }
    };
  }

  bool get isOpen {
    try { return _dc?.state == RTCDataChannelState.RTCDataChannelOpen; } catch (_) { return false; }
  }

  Future<Map<String, dynamic>> request(String action, [Map<String, dynamic>? params]) async {
    if (_dc == null || !isOpen) {
      throw Exception('DataChannel not open');
    }
    final id = '${++_seq}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final msg = {'id': id, 'action': action, ...?params};
    _dc!.send(RTCDataChannelMessage(jsonEncode(msg)));

    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('DataChannel request timeout: $action');
    });
  }

  void dispose() {
    for (final c in _pending.values) {
      c.completeError('disposed');
    }
    _pending.clear();
    _pushController.close();
    _dc = null;
  }
}
