import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../providers/connection_provider.dart';
import '../providers/device_provider.dart';

class RecordingsScreen extends StatefulWidget {
  final String? cameraId;
  final String? cameraName;
  const RecordingsScreen({super.key, this.cameraId, this.cameraName});
  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<Map<String, dynamic>> _recordings = [];
  bool _loading = true;
  int _total = 0;
  int _offset = 0;
  final int _limit = 20;
  bool _loadingMore = false;
  String? _playingFile;
  double _playDuration = 0;
  double _playElapsed = 0;
  bool _playLoading = false;
  final _renderer = RTCVideoRenderer();
  StreamSubscription? _streamSub;
  Timer? _progressTimer;
  ConnectionProvider? _cp;
  DeviceProvider? _dp;
  String? _activeDeviceId;

  @override
  void initState() {
    super.initState();
    _cp = context.read<ConnectionProvider>();
    _dp = context.read<DeviceProvider>();
    _activeDeviceId = _cp!.activeDeviceId;
    _renderer.initialize().then((_) => _loadRecordings());
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _progressTimer?.cancel();
    if (_playingFile != null) {
      _cmd('stop_playback').catchError((_) => <String, dynamic>{});
      _conn?.sbcWebrtc?.disconnectCamera(_playbackKey);
      _reconnectLiveCameras();
    }
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  DeviceConnection? get _conn {
    return _activeDeviceId != null ? _cp?.getConnection(_activeDeviceId!) : null;
  }

  String get _sbcId {
    final dev = _dp?.devices.where((d) => d.id == _activeDeviceId).firstOrNull;
    return dev?.config?.sbcCameras.keys.firstOrNull ?? '';
  }

  String get _playbackKey {
    final s = _sbcId;
    return s.isNotEmpty ? '$s:playback' : 'playback';
  }

  Future<Map<String, dynamic>> _cmd(String action, [Map<String, dynamic>? params]) async {
    final dc = _conn?.dc;
    if (dc == null || !dc.isOpen) throw Exception('MCU DataChannel not open');
    return dc.request(action, params);
  }

  Future<void> _loadRecordings() async {
    try {
      final res = await _cmd('list_recordings', {
        'offset': 0, 'limit': _limit,
        if (widget.cameraId != null) 'camera_id': widget.cameraId,
      });
      if (mounted) setState(() {
        _recordings = (res['recordings'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _total = res['total'] ?? 0;
        _offset = _recordings.length;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Recordings] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final res = await _cmd('list_recordings', {
        'offset': _offset, 'limit': _limit,
        if (widget.cameraId != null) 'camera_id': widget.cameraId,
      });
      final more = (res['recordings'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) setState(() { _recordings.addAll(more); _offset += more.length; _loadingMore = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Group by camera, then by day within each camera
  Map<String, Map<String, List<Map<String, dynamic>>>> get _grouped {
    final result = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final r in _recordings) {
      final cam = r['camera_id'] as String? ?? 'unknown';
      final ts = r['ts'] as String? ?? '';
      final day = ts.length >= 10 ? ts.substring(0, 10) : 'Unknown';
      result.putIfAbsent(cam, () => {}).putIfAbsent(day, () => []).add(r);
    }
    return result;
  }

  Future<void> _play(Map<String, dynamic> rec) async {
    if (_playLoading) return;
    setState(() => _playLoading = true);
    try {
      await _cmd('play_recording', {
        'camera_id': rec['camera_id'] ?? '', 'file': rec['file'] ?? '',
      });
      setState(() { _playingFile = rec['file']; _playDuration = (rec['duration'] as num?)?.toDouble() ?? 0; _playElapsed = 0; });
      final conn = _conn;
      if (conn?.sbcWebrtc != null) {
        _streamSub?.cancel();
        _streamSub = conn!.sbcWebrtc!.onRemoteStreams.listen((_) {
          if (!mounted) return;
          final stream = conn.sbcWebrtc!.remoteStreams[_playbackKey];
          if (stream != null && _renderer.srcObject != stream) {
            _renderer.srcObject = stream;
            setState(() => _playLoading = false);
            _startProgressTimer();
          }
        });
        await conn.sbcWebrtc!.connectCamera(_playbackKey, sbcId: _sbcId.isNotEmpty ? _sbcId : null, remoteCameraName: 'playback');
        final stream = conn.sbcWebrtc!.remoteStreams[_playbackKey];
        if (stream != null && mounted) {
          _renderer.srcObject = stream;
          setState(() => _playLoading = false);
          _startProgressTimer();
        }
      }
    } catch (e) {
      debugPrint('[Recordings] play failed: $e');
      if (mounted) setState(() => _playLoading = false);
    }
  }

  void _stop() {
    _cmd('stop_playback').catchError((_) => <String, dynamic>{});
    _conn?.sbcWebrtc?.disconnectCamera(_playbackKey);
    _renderer.srcObject = null;
    _progressTimer?.cancel();
    setState(() { _playingFile = null; _playLoading = false; _playElapsed = 0; });
    _reconnectLiveCameras();
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _playElapsed = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _playingFile == null) { _progressTimer?.cancel(); return; }
      setState(() {
        _playElapsed += 1;
        if (_playElapsed >= _playDuration) { _progressTimer?.cancel(); _stop(); }
      });
    });
  }

  Future<void> _reconnectLiveCameras() async {
    final conn = _conn;
    if (conn?.sbcWebrtc == null) return;
    final device = _dp?.getDevice(conn!.deviceId);
    final camCount = device?.cameraCount ?? 0;
    for (var i = 0; i < camCount; i++) {
      await conn!.sbcWebrtc!.connectCamera('cam$i');
    }
  }

  @override
  String _formatTime(double secs) {
    final m = (secs / 60).floor();
    final s = (secs % 60).floor();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final cams = grouped.keys.toList();
    // If filtered by camera, skip camera header
    final singleCam = widget.cameraId != null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.cameraName != null ? '${widget.cameraName} Recordings' : 'Recordings')),
      body: Column(children: [
        // Playback area
        if (_playingFile != null)
          Container(color: Colors.black, child: Column(children: [
            AspectRatio(aspectRatio: 16 / 9, child: Stack(children: [
              RTCVideoView(_renderer),
              if (_playLoading)
                const Center(child: CircularProgressIndicator(color: Colors.white)),
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                Text(_formatTime(_playElapsed), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: LinearProgressIndicator(
                    value: _playDuration > 0 ? (_playElapsed / _playDuration).clamp(0, 1) : 0,
                    backgroundColor: Colors.white24, color: Colors.cyan, minHeight: 3))),
                Text(_formatTime(_playDuration), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                const SizedBox(width: 4),
                GestureDetector(onTap: _stop, child: const Icon(Icons.stop, color: Colors.red, size: 22)),
              ])),
          ])),
        // Recording list
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _recordings.isEmpty
              ? const Center(child: Text('No recordings', style: TextStyle(color: Colors.grey)))
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollEndNotification && n.metrics.extentAfter < 200) _loadMore();
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: () async { _offset = 0; _recordings.clear(); await _loadRecordings(); },
                    child: ListView(children: [
                      for (final cam in cams) ...[
                        if (!singleCam)
                          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text(cam, style: Theme.of(context).textTheme.titleMedium)),
                        for (final day in grouped[cam]!.keys) ...[
                          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Text(day, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey))),
                          GridView.count(
                            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 16 / 12,
                            children: [
                              for (final rec in grouped[cam]![day]!)
                                _RecordingTile(
                                  rec: rec,
                                  playing: _playingFile == rec['file'],
                                  loading: _playLoading && _playingFile == rec['file'],
                                  onTap: () => _playingFile == rec['file'] ? _stop() : _play(rec)),
                            ],
                          ),
                        ],
                      ],
                      if (_loadingMore)
                        const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2))),
                    ]),
                  ),
                ),
        ),
      ]),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  final Map<String, dynamic> rec;
  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  const _RecordingTile({required this.rec, required this.playing, this.loading = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = rec['thumbnail_b64'] as String? ?? '';
    final duration = rec['duration'] as num? ?? 0;
    final ts = rec['ts'] as String? ?? '';
    final time = ts.length >= 19 ? ts.substring(11, 16) : '';
    final min = (duration / 60).floor();
    final sec = (duration % 60).toInt();
    final durStr = '${min}m${sec.toString().padLeft(2, '0')}s';

    return GestureDetector(onTap: onTap, child: Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
        border: playing ? Border.all(color: Colors.cyan, width: 2) : null, color: Colors.grey[900]),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (thumb.isNotEmpty)
          Positioned.fill(child: Image.memory(base64Decode(thumb), fit: BoxFit.cover, gaplessPlayback: true))
        else
          const Positioned.fill(child: Icon(Icons.videocam, color: Colors.grey, size: 32)),
        // Duration badge (top-right)
        Positioned(right: 4, top: 4, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
          child: Text(durStr, style: const TextStyle(color: Colors.white, fontSize: 9)))),
        // Time badge (bottom-left)
        Positioned(left: 4, bottom: 4, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
          child: Text(time, style: const TextStyle(color: Colors.white70, fontSize: 10)))),
        // Play/stop/loading overlay
        if (loading)
          const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyan)))
        else if (playing)
          const Center(child: Icon(Icons.stop_circle, color: Colors.cyan, size: 36))
        else
          const Center(child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 36)),
      ]),
    ));
  }
}
