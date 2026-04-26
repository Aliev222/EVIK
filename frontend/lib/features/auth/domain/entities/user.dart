enum UserRole {
  client,
  driver,
  admin,
}

class User {
  const User({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.role,
    this.avatar,
    required this.isActive,
    required this.createdAt,
    required this.lastSeen,
  });

  final String id;
  final String phone;
  final String fullName;
  final UserRole role;
  final String? avatar;
  final bool isActive;
  final DateTime createdAt;
  final DateTime lastSeen;

  User copyWith({
    String? id,
    String? phone,
    String? fullName,
    UserRole? role,
    String? avatar,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastSeen,
  }) {
    return User(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      avatar: avatar ?? this.avatar,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  // Map serialization
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as String,
      phone: map['phone'] as String,
      fullName: map['fullName'] as String,
      role: UserRole.values.byName(map['role'] as String),
      avatar: map['avatar'] as String?,
      isActive: map['isActive'] as bool,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['lastSeen'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phone': phone,
      'fullName': fullName,
      'role': role.name,
      'avatar': avatar,
      'isActive': isActive,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
    };
  }
}
