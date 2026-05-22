class Device {
  final String id;
  final String name;
  final Map<String, dynamic>? hardware;
  final double? lat;
  final double? lng;
  final String? status;
  final List<SubDevice> subDevices;
  final DeviceConfig? config;

  Device({required this.id, required this.name, this.hardware, this.lat, this.lng, this.status, this.subDevices = const [], this.config});

  List<SubDevice> get cameras => subDevices.where((s) => s.isCamera).toList();
  List<SubDevice> get solars => subDevices.where((s) => s.isSolar).toList();
  SubDevice? get sbc => subDevices.where((s) => s.isSBC).firstOrNull;
  int get cameraCount => cameras.length;
  String? get board => hardware?['board'];

  factory Device.fromJson(Map<String, dynamic> json) {
    final cfg = json['config'] != null ? DeviceConfig.fromJson(json['config']) : null;
    final subs = <SubDevice>[];
    if (cfg != null) {
      // New schema: nodes[]
      for (final node in cfg.nodes) {
        if (node['type'] == 'camera') {
          subs.add(SubDevice(id: node['id'] ?? '', name: node['name'] ?? '', type: 'Camera'));
        } else if (node['type'] == 'switch') {
          subs.add(SubDevice(id: node['id'] ?? '', name: node['name'] ?? '', type: 'RELAY'));
        } else if (node['type'] == 'log') {
          subs.add(SubDevice(id: node['id'] ?? '', name: node['name'] ?? '', type: 'MPPT'));
        }
      }
    }
    return Device(
      id: json['deviceId'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      status: json['status'],
      hardware: json['hardware'] != null ? Map<String, dynamic>.from(json['hardware']) : null,
      subDevices: subs,
      config: cfg,
    );
  }
}

class DeviceConfig {
  final McuConfig mcu;
  final Map<String, List<Map<String, dynamic>>> sbcCameras;
  final Map<String, dynamic> alarms;
  final List<Map<String, dynamic>> nodes;

  DeviceConfig({required this.mcu, this.sbcCameras = const {}, this.alarms = const {}, this.nodes = const []});

  factory DeviceConfig.fromJson(Map<String, dynamic> json) {
    final rawNodes = (json['nodes'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];

    // Build sbcCameras from camera nodes (for compat with old screens)
    final cameras = rawNodes.where((n) => n['type'] == 'camera').toList();
    final sbcCameras = <String, List<Map<String, dynamic>>>{};
    if (cameras.isNotEmpty) {
      // Put all cameras under a virtual sbc key
      sbcCameras[''] = cameras.map((c) =>
        <String, dynamic>{'id': c['id'], 'name': c['name'], 'rtsp': c['url'], ...c}
      ).toList();
    }

    // Build mcu config from log nodes
    final logNodes = rawNodes.where((n) => n['type'] == 'log').toList();
    final pollInterval = logNodes.isNotEmpty ? (logNodes.first['pollInterval'] ?? 5) : 5;

    return DeviceConfig(
      mcu: McuConfig(telemetryInterval: pollInterval as int, subDevices: [
        // Add a virtual SBC sub-device so old connection code works
        {'type': 'SBC', 'id': 'sbc', 'protocol': 'http', 'host': '', 'port': 8160},
      ]),
      sbcCameras: sbcCameras,
      alarms: json['alarms'] as Map<String, dynamic>? ?? {},
      nodes: rawNodes,
    );
  }
}

class McuConfig {
  final int telemetryInterval;
  final List<Map<String, dynamic>> subDevices;

  McuConfig({this.telemetryInterval = 5, this.subDevices = const []});

  factory McuConfig.fromJson(Map<String, dynamic> json) => McuConfig(
    telemetryInterval: json['telemetryInterval'] ?? 5,
    subDevices: (json['subDevices'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
  );
}

class SubDevice {
  final String id;
  final String name;
  final String type;
  final String? protocol;
  final String? host;
  final int? port;
  final String? parentId;
  final int? relayChannel;
  final String? code;
  final int? ratedVoltage;
  final String? macAddress;
  final String? description;
  final String? icon;

  SubDevice({required this.id, required this.name, required this.type, this.protocol, this.host, this.port, this.parentId, this.relayChannel, this.code, this.ratedVoltage, this.macAddress, this.description, this.icon});

  bool get isSolar => type == 'Solar' || type == 'MPPT';
  bool get isCamera => type == 'Camera';
  bool get isSBC => type == 'SBC' || type == 'RPI';
  bool get isGPS => type == 'GPS';
  bool get isBME280 => type == 'BME280';

  factory SubDevice.fromJson(Map<String, dynamic> json) => SubDevice(
    id: json['sub_device_id'] ?? json['id'] ?? '',
    name: json['sub_device_name'] ?? json['name'] ?? '',
    type: json['sub_device_type'] ?? json['type'] ?? '',
    parentId: json['device_id'] ?? json['parentId'],
  );
}
