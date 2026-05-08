import 'package:equatable/equatable.dart';

enum UserRole { dealer, reseller, admin }

class User extends Equatable {
  final String id;
  final String email;
  final String name;
  final String shopName;
  final String phone;
  final UserRole role;
  final String? resellerId;
  final DateTime createdAt;
  final bool twoFactorEnabled;
  final bool isActive;

  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.shopName,
    required this.phone,
    required this.role,
    this.resellerId,
    required this.createdAt,
    this.twoFactorEnabled = false,
    this.isActive = true,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      shopName: json['shop_name'] as String? ?? '',
      phone: json['phone'] as String,
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.dealer,
      ),
      resellerId: json['reseller_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      twoFactorEnabled: json['two_factor_enabled'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'shop_name': shopName,
      'phone': phone,
      'role': role.name,
      'reseller_id': resellerId,
      'created_at': createdAt.toIso8601String(),
      'two_factor_enabled': twoFactorEnabled,
      'is_active': isActive,
    };
  }

  bool get isDealer => role == UserRole.dealer;
  bool get isReseller => role == UserRole.reseller;

  @override
  List<Object?> get props => [id, email, name, shopName, phone, role, resellerId, createdAt, twoFactorEnabled, isActive];
}