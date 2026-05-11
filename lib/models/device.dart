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
      for (final sd in cfg.mcu.subDevices) {
        subs.add(SubDevice(
          id: sd['id'] ?? sd['type'] ?? '',
          name: sd['type'] ?? '',
          type: sd['type'] ?? '',
          protocol: sd['protocol'],
          host: sd['host'],
          port: sd['port'] is int ? sd['port'] : int.tryParse('${sd['port'] ?? ''}'),
        ));
      }
      for (final entry in cfg.sbcCameras.entries) {
        for (final c in entry.value) {
          subs.add(SubDevice(id: c['id'] ?? '', name: c['name'] ?? '', type: 'Camera', parentId: entry.key));
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
  final Map<String, List<Map<String, dynamic>>> sbcCameras; // sbcId -> cameras
  final Map<String, dynamic> alarms;

  DeviceConfig({required this.mcu, this.sbcCameras = const {}, this.alarms = const {}});

  factory DeviceConfig.fromJson(Map<String, dynamic> json) {
    final sbcRaw = json['sbc'] as Map<String, dynamic>? ?? {};
    final cameras = <String, List<Map<String, dynamic>>>{};
    for (final entry in sbcRaw.entries) {
      if (entry.value is Map && (entry.value as Map).containsKey('cameras')) {
        cameras[entry.key] = ((entry.value as Map)['cameras'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
      }
    }
    return DeviceConfig(
      mcu: McuConfig.fromJson(json['mcu'] ?? {}),
      sbcCameras: cameras,
      alarms: json['alarms'] ?? {},
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
    code: json['sub_device_code'] ?? json['code'],
    ratedVoltage: json['sub_device_rated_voltage'] != null ? int.tryParse('${json['sub_device_rated_voltage']}') : null,
    macAddress: json['sub_device_mac_address'] ?? json['macAddress'],
    description: json['sub_device_description'] ?? json['description'],
    icon: json['sub_device_icon'] ?? json['icon'],
  );

  Map<String, dynamic> toJson() => {
    'sub_device_id': id, 'sub_device_name': name, 'sub_device_type': type,
    'device_id': parentId, 'sub_device_code': code,
    'sub_device_rated_voltage': ratedVoltage, 'sub_device_mac_address': macAddress,
    'sub_device_description': description, 'sub_device_icon': icon,
  };
}

class DeviceStatus {
  final String deviceId;
  final bool online;
  final DateTime? lastSeen;
  final Map<String, dynamic> sensors;

  DeviceStatus({required this.deviceId, this.online = false, this.lastSeen, this.sensors = const {}});

  factory DeviceStatus.fromJson(Map<String, dynamic> json) => DeviceStatus(
    deviceId: json['deviceId'] ?? '',
    online: json['online'] ?? false,
    sensors: json['sensors'] ?? {},
  );
}

class MPPTData {
  final double voltage;
  final double current;
  final double power;
  final double batteryVoltage;
  final double batteryCharge;
  final DateTime timestamp;

  MPPTData({required this.voltage, required this.current, required this.power, required this.batteryVoltage, required this.batteryCharge, required this.timestamp});

  factory MPPTData.fromJson(Map<String, dynamic> json) => MPPTData(
    voltage: (json['voltage'] as num?)?.toDouble() ?? 0,
    current: (json['current'] as num?)?.toDouble() ?? 0,
    power: (json['power'] as num?)?.toDouble() ?? 0,
    batteryVoltage: (json['batteryVoltage'] as num?)?.toDouble() ?? 0,
    batteryCharge: (json['batteryCharge'] as num?)?.toDouble() ?? 0,
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
  );
}

class SensorData {
  final String type;
  final double value;
  final String unit;
  final DateTime timestamp;

  SensorData({required this.type, required this.value, required this.unit, required this.timestamp});

  factory SensorData.fromJson(Map<String, dynamic> json) => SensorData(
    type: json['type'] ?? '',
    value: (json['value'] as num?)?.toDouble() ?? 0,
    unit: json['unit'] ?? '',
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
  );
}
