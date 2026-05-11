class User {
  final String id;
  final String email;
  final String? name;
  final String? role;

  User({required this.id, required this.email, this.name, this.role});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] ?? '',
    email: json['email'] ?? '',
    name: json['name'],
    role: json['role'],
  );
}

class Invitation {
  final String id;
  final String deviceId;
  final String inviteeEmail;
  final String status;
  final DateTime createdAt;

  Invitation({required this.id, required this.deviceId, required this.inviteeEmail, required this.status, required this.createdAt});

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
    id: json['id'] ?? '',
    deviceId: json['deviceId'] ?? '',
    inviteeEmail: json['inviteeEmail'] ?? '',
    status: json['status'] ?? 'pending',
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}

class SharedUser {
  final String userId;
  final String deviceId;
  final String email;
  final String permission;

  SharedUser({required this.userId, required this.deviceId, required this.email, required this.permission});

  factory SharedUser.fromJson(Map<String, dynamic> json) => SharedUser(
    userId: json['userId'] ?? '',
    deviceId: json['deviceId'] ?? '',
    email: json['email'] ?? '',
    permission: json['permission'] ?? 'read',
  );
}
