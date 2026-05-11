class Alert {
  final String id;
  final String deviceId;
  final String type;
  final String message;
  final String severity;
  final bool acknowledged;
  final DateTime timestamp;

  Alert({required this.id, required this.deviceId, required this.type, required this.message, required this.severity, this.acknowledged = false, required this.timestamp});

  factory Alert.fromJson(Map<String, dynamic> json) => Alert(
    id: json['id'] ?? '',
    deviceId: json['deviceId'] ?? '',
    type: json['type'] ?? '',
    message: json['message'] ?? '',
    severity: json['severity'] ?? 'info',
    acknowledged: json['acknowledged'] ?? false,
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
  );
}

class AlarmParam {
  final String id;
  final String deviceId;
  final String paramName;
  final double threshold;
  final bool enabled;

  AlarmParam({required this.id, required this.deviceId, required this.paramName, required this.threshold, this.enabled = true});

  factory AlarmParam.fromJson(Map<String, dynamic> json) => AlarmParam(
    id: json['id'] ?? '',
    deviceId: json['deviceId'] ?? '',
    paramName: json['paramName'] ?? '',
    threshold: (json['threshold'] as num?)?.toDouble() ?? 0,
    enabled: json['enabled'] ?? true,
  );
}
