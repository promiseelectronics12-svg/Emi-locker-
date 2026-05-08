import 'package:equatable/equatable.dart';

enum UserRole { dealer, reseller }

class User extends Equatable {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final String? shopName;
  final String? tradeLicense;
  final String? address;
  final String? resellerCode;
  final bool twoFactorEnabled;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.shopName,
    this.tradeLicense,
    this.address,
    this.resellerCode,
    this.twoFactorEnabled = false,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      role: json['role'] == 'dealer' ? UserRole.dealer : UserRole.reseller,
      shopName: json['shop_name'] as String?,
      tradeLicense: json['trade_license'] as String?,
      address: json['address'] as String?,
      resellerCode: json['reseller_code'] as String?,
      twoFactorEnabled: json['two_factor_enabled'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role == UserRole.dealer ? 'dealer' : 'reseller',
      'shop_name': shopName,
      'trade_license': tradeLicense,
      'address': address,
      'reseller_code': resellerCode,
      'two_factor_enabled': twoFactorEnabled,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, email, role];
}