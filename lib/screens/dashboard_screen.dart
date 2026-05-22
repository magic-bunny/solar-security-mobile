import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/device_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../models/device.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _mapController = MapController();
  bool _panelExpanded = true;
  double _panelHeight = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dp = context.read<DeviceProvider>();
      if (dp.devices.isEmpty) dp.loadDevices();
      final conn = context.read<ConnectionProvider>();
      conn.onConfigUpdated = () => dp.loadDevices();
      conn.ensureConnected(
        context.read<AuthProvider>(),
        dp,
      );
    });
  }

  void _onDeviceTap(Device d) {
    final conn = context.read<ConnectionProvider>();
    final status = conn.statusOf(d.id);
    if (status == ConnectionStatus.connected) {
      conn.setActiveDevice(d.id);
      context.go('/device/${d.id}');
    } else if (status == ConnectionStatus.disconnected) {
      _connectDevice(d);
    }
  }

  Future<void> _connectDevice(Device d) async {
    final conn = context.read<ConnectionProvider>();
    final auth = context.read<AuthProvider>();
    final token = await auth.getIdToken() ?? 'dev-token';
    conn.connectDevice(
        token: token, deviceId: d.id, cameraCount: d.cameraCount);
  }

  void _focusDevice(Device d) {
    if (d.lat != null && d.lng != null) {
      setState(() => _panelExpanded = false);
      _mapController.move(LatLng(d.lat!, d.lng!), 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DeviceProvider>();
    final user = context.read<AuthProvider>().user;
    final helloName = user == null
        ? ''
        : (user.name?.isNotEmpty == true
            ? user.name!
            : user.email.split('@').first);
    if (!_dragging) {
      final h = MediaQuery.of(context).size.height;
      _panelHeight = _panelExpanded ? h * 0.65 : 100;
    }
    return Scaffold(
      body: dp.loading
          ? _buildSkeleton(context)
          : Stack(children: [
              // Map background
              _buildMap(dp.devices),
              // Device list panel
              AnimatedPositioned(
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                left: 0,
                right: 0,
                bottom: 0,
                height: _panelHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 10)
                    ],
                  ),
                  child: Column(children: [
                    GestureDetector(
                      onTap: () =>
                          setState(() => _panelExpanded = !_panelExpanded),
                      onVerticalDragUpdate: (d) => setState(() {
                        _dragging = true;
                        _panelHeight = (_panelHeight - d.delta.dy).clamp(
                            100.0, MediaQuery.of(context).size.height * 0.85);
                      }),
                      onVerticalDragEnd: (d) => setState(() {
                        _dragging = false;
                        _panelExpanded = _panelHeight >
                            MediaQuery.of(context).size.height * 0.3;
                      }),
                      child: Container(
                        color: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              Text('Hello, $helloName',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ]),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              Text('My Assets',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: Colors.grey)),
                              const Spacer(),
                              Text('${dp.devices.length} devices',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                              const SizedBox(width: 4),
                              Icon(
                                  _panelExpanded
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_up,
                                  color: Colors.grey,
                                  size: 20),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                    if (_panelHeight > 110)
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: dp.devices.length,
                          itemBuilder: (_, i) => _deviceCard(dp.devices[i]),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: c, borderRadius: BorderRadius.circular(h / 2)));
    Widget card() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: c, borderRadius: BorderRadius.circular(8))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    bar(120, 14),
                    const SizedBox(height: 8),
                    bar(80, 10)
                  ])),
              bar(24, 24),
            ]),
          ),
        );
    return Column(children: [
      Expanded(child: Container(color: c.withValues(alpha: 0.3))),
      Container(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16))),
        padding: const EdgeInsets.only(top: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          bar(40, 4),
          const SizedBox(height: 12),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child:
                  Row(children: [bar(100, 16), const Spacer(), bar(60, 12)])),
          const SizedBox(height: 12),
          card(),
          card(),
          card(),
        ]),
      ),
    ]);
  }

  Widget _buildMap(List<Device> devices) {
    final conn = context.watch<ConnectionProvider>();
    final markers =
        devices.where((d) => d.lat != null && d.lng != null).map((d) {
      final online = conn.statusOf(d.id) == ConnectionStatus.connected;
      return Marker(
        point: LatLng(d.lat!, d.lng!),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _onDeviceTap(d),
          child: Icon(Icons.location_on,
              size: 36, color: online ? Colors.green : Colors.grey),
        ),
      );
    }).toList();

    final center = devices.where((d) => d.lat != null).isNotEmpty
        ? LatLng(devices.firstWhere((d) => d.lat != null).lat!,
            devices.firstWhere((d) => d.lng != null).lng!)
        : const LatLng(22.5431, 114.0579);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 13),
      children: [
        TileLayer(
          key: ValueKey(isDark),
          urlTemplate: isDark
              ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png?lang=en'
              : 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png?lang=en',
          userAgentPackageName: 'com.solar.security',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _deviceCard(Device d) {
    final conn = context.watch<ConnectionProvider>();
    final p2p = conn.statusOf(d.id);
    final connected = p2p == ConnectionStatus.connected;
    final connecting = p2p == ConnectionStatus.connecting ||
        p2p == ConnectionStatus.reconnecting;
    final online = connected;
    final statusLabel = connected
        ? 'SBC P2P online'
        : connecting
            ? 'Connecting SBC P2P'
            : 'SBC P2P offline';
    const ratedV = 12;
    return Opacity(
        opacity: online ? 1.0 : 0.5,
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _onDeviceTap(d),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                GestureDetector(
                  onTap: !connected && !connecting
                      ? () => _connectDevice(d)
                      : null,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (connected ? Colors.green : Colors.grey)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: connecting
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(connected ? Icons.power : Icons.power_off,
                            color: connected
                                ? Colors.green
                                : connecting
                                    ? Colors.orange
                                    : Colors.grey,
                            size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      '$statusLabel · ${d.cameras.length} cam · ${d.solars.isNotEmpty ? d.solars.first.name : "no MPPT"} · ${ratedV}V',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                )),
                GestureDetector(
                  onTap: () => _focusDevice(d),
                  child: const Icon(Icons.my_location,
                      size: 16, color: Colors.grey),
                ),
              ]),
            ),
          ),
        ));
  }
}
