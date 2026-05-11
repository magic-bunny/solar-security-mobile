import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/constants.dart';
import 'websocket_service.dart';

/// Single-camera WebRTC session (one RTCPeerConnection per camera).
class _CameraSession {
  final String camera;
  RTCPeerConnection? pc;
  MediaStream? stream;
  RTCPeerConnectionState connectionState = RTCPeerConnectionState.RTCPeerConnectionStateNew;
  int _lastFrames = 0;
  bool _receiving = false;
  bool _everReceived = false;

  _CameraSession(this.camera);

  bool get showDisconnected {
    if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected
        || connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed
        || connectionState == RTCPeerConnectionState.RTCPeerConnectionStateClosed) return true;
    return _everReceived && !_receiving;
  }

  Future<void> pollStats() async {
    if (pc == null) return;
    try {
      final stats = await pc!.getStats();
      for (final report in stats) {
        if (report.type == 'inbound-rtp' && report.values['kind'] == 'video') {
          final frames = (report.values['framesReceived'] as num?)?.toInt() ?? 0;
          if (frames > _lastFrames) {
            _receiving = true;
            _everReceived = true;
          } else if (_everReceived) {
            _receiving = false;
          }
          _lastFrames = frames;
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> close() async {
    await pc?.close();
    pc = null;
    stream = null;
    connectionState = RTCPeerConnectionState.RTCPeerConnectionStateClosed;
    _receiving = false;
  }
}

class WebRTCService {
  // MCU data-only connection
  RTCPeerConnection? _dataPc;
  RTCDataChannel? _dataChannel;
  final WebSocketService _ws;
  StreamSubscription? _wsSub;
  final _dcController = StreamController<RTCDataChannel>.broadcast();

  // Per-camera video sessions
  final Map<String, _CameraSession> _sessions = {};
  final _remoteStreamController = StreamController<Map<String, MediaStream>>.broadcast();
  final _stateController = StreamController<void>.broadcast();
  Timer? _statsTimer;
  bool _disposed = false;

  WebRTCService(this._ws);

  Stream<RTCDataChannel> get onDataChannel => _dcController.stream;
  RTCDataChannel? get dataChannel => _dataChannel;
  Map<String, MediaStream> get remoteStreams =>
      Map.fromEntries(_sessions.entries.where((e) => e.value.stream != null).map((e) => MapEntry(e.key, e.value.stream!)));
  Stream<Map<String, MediaStream>> get onRemoteStreams => _remoteStreamController.stream;
  bool cameraDisconnected(String camera) => _sessions[camera]?.showDisconnected ?? false;
  Stream<void> get onStateChange => _stateController.stream;

  /// Connect for MCU data channel only.
  Future<void> connectData(String deviceId) async {
    _dataPc = await createPeerConnection({'iceServers': WebRTCConstants.iceServers});
    _dataChannel = await _dataPc!.createDataChannel('data', RTCDataChannelInit());
    _dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen && !_disposed) _dcController.add(_dataChannel!);
    };
    _dataPc!.onIceCandidate = (c) => _ws.sendSignal(type: 'candidate', candidate: {
      'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex,
    });
    _wsSub ??= _ws.messages.listen(_onSignal);
    final offer = await _dataPc!.createOffer();
    await _dataPc!.setLocalDescription(offer);
    _ws.sendSignal(type: 'offer', sdp: offer.sdp);
  }

  /// Start a video session for a single camera.
  Future<void> connectCamera(String camera, {String? sbcId, String? remoteCameraName}) async {
    final remoteCamera = remoteCameraName ?? camera;
    final session = _CameraSession(camera);
    _sessions[camera] = session;
    session.pc = await createPeerConnection({'iceServers': WebRTCConstants.iceServers});
    session.pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] $camera connection: $state');
      session.connectionState = state;
      if (!_disposed) _stateController.add(null);
    };
    session.pc!.onIceConnectionState = (state) {
      debugPrint('[WebRTC] $camera ICE: $state');
    };
    session.pc!.onTrack = (event) async {
      debugPrint('[WebRTC] $camera onTrack: kind=${event.track.kind} streams=${event.streams.length}');
      if (event.track.kind == 'video') {
        session.stream = event.streams.isNotEmpty ? event.streams[0] : null;
        if (session.stream == null) {
          final ms = await createLocalMediaStream('cam-${session.camera}');
          ms.addTrack(event.track);
          session.stream = ms;
        }
        _notifyStreams();
      }
    };
    session.pc!.onIceCandidate = (c) => _ws.sendSignal(type: 'candidate', camera: remoteCamera, sbcId: sbcId, candidate: {
      'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex,
    });
    _wsSub ??= _ws.messages.listen(_onSignal);
    await session.pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    final offer = await session.pc!.createOffer();
    await session.pc!.setLocalDescription(offer);
    // go2rtc needs Mobile's ICE candidates in the offer (no trickle ICE support)
    // Wait for ICE gathering to complete, then send offer with all candidates
    await _waitGatheringComplete(session.pc!);
    final desc = await session.pc!.getLocalDescription();
    debugPrint('[WebRTC] $camera sending offer with candidates (${desc?.sdp?.length ?? 0} bytes)');
    _ws.sendSignal(type: 'offer', sdp: desc?.sdp ?? offer.sdp, camera: remoteCamera, sbcId: sbcId);
    _ensureStatsTimer();
  }

  void _ensureStatsTimer() {
    _statsTimer ??= Timer.periodic(const Duration(seconds: 3), (_) => _pollAllStats());
  }

  Future<void> _pollAllStats() async {
    if (_sessions.isEmpty) return;
    for (final s in List.of(_sessions.values)) await s.pollStats();
    if (!_disposed) _stateController.add(null);
  }

  void _notifyStreams() { if (!_disposed) _remoteStreamController.add(remoteStreams); }

  Future<void> _waitGatheringComplete(RTCPeerConnection pc) async {
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return;
    final c = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete && !c.isCompleted) c.complete();
    };
    await c.future.timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  void _onSignal(Map<String, dynamic> msg) {
    if (msg['action'] != 'signal') return;
    final type = msg['type'] as String?;
    final camera = msg['camera'] as String?;
    final sbcId = msg['sbcId'] as String?;
    // Reconstruct session key: sbcId:camera or just camera
    final sessionCamera = (sbcId != null && sbcId.isNotEmpty && camera != null) ? '$sbcId:$camera' : camera;
    switch (type) {
      case 'answer':
        _handleAnswer(msg['sdp'] as String, sessionCamera);
        break;
      case 'candidate':
        _handleCandidate(msg['candidate'] as Map<String, dynamic>, sessionCamera);
        break;
    }
  }

  Future<void> _handleAnswer(String sdp, String? camera) async {
    if (sdp.length < 50) {
      debugPrint('[WebRTC] ignoring invalid answer for ${camera ?? "data"} (${sdp.length} bytes)');
      return;
    }
    try {
      final pc = camera != null ? _sessions[camera]?.pc : _dataPc;
      debugPrint('[WebRTC] answer for ${camera ?? "data"} (${sdp.length} bytes)');
      if (pc == null) {
        debugPrint('[WebRTC] WARNING: no PC for ${camera ?? "data"}, answer dropped');
        return;
      }
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    } catch (e) {
      debugPrint('[WebRTC] setRemoteDescription failed: $e');
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> c, String? camera) async {
    try {
      final pc = camera != null ? _sessions[camera]?.pc : _dataPc;
      await pc?.addCandidate(RTCIceCandidate(
        c['candidate'] as String?, c['sdpMid'] as String?, c['sdpMLineIndex'] as int?,
      ));
    } catch (_) {}
  }

  Future<void> disconnectCamera(String camera) async {
    final s = _sessions.remove(camera);
    await s?.close();
    _notifyStreams();
  }

  /// Connect a playback session (aiortc P2P with DataChannel + media track).
  /// Returns the DataChannel for sending playback commands.
  Future<RTCDataChannel?> connectPlayback() async {
    await disconnectCamera('playback');
    final session = _CameraSession('playback');
    _sessions['playback'] = session;
    session.pc = await createPeerConnection({'iceServers': WebRTCConstants.iceServers});
    session.pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] playback connection: $state');
      session.connectionState = state;
      if (!_disposed) _stateController.add(null);
    };
    session.pc!.onTrack = (event) {
      debugPrint('[WebRTC] playback onTrack: kind=${event.track.kind}');
      if (event.track.kind == 'video') {
        session.stream = event.streams.isNotEmpty ? event.streams[0] : null;
        if (session.stream == null) {
          createLocalMediaStream('playback-stream').then((ms) {
            ms.addTrack(event.track);
            session.stream = ms;
            _notifyStreams();
          });
        } else {
          _notifyStreams();
        }
      }
    };
    session.pc!.onIceCandidate = (c) => _ws.sendSignal(
      type: 'candidate', camera: 'playback',
      candidate: {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
    );
    _wsSub ??= _ws.messages.listen(_onSignal);

    // DataChannel only — no video transceiver (video goes through go2rtc separately)
    final dc = await session.pc!.createDataChannel('playback', RTCDataChannelInit());

    final offer = await session.pc!.createOffer();
    await session.pc!.setLocalDescription(offer);
    await _waitGatheringComplete(session.pc!);
    final desc = await session.pc!.getLocalDescription();
    _ws.sendSignal(type: 'offer', sdp: desc?.sdp ?? offer.sdp, camera: 'playback-dc');
    _ensureStatsTimer();
    return dc;
  }

  Future<void> disconnect() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    _dataChannel = null;
    await _dataPc?.close();
    _dataPc = null;
    for (final s in _sessions.values) await s.close();
    _sessions.clear();
    _notifyStreams();
  }

  void dispose() {
    _disposed = true;
    _statsTimer?.cancel();
    _remoteStreamController.close();
    _dcController.close();
    _stateController.close();
  }
}
