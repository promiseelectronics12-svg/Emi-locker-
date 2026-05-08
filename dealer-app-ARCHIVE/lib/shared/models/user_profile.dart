import 'package:equatable/equatable.dart';

enum UserRole { ADMIN, DEALER, RESELLER, CUSTOMER }

class UserProfile extends Equatable {
  final String id;
  final String name;
  final String email;
  final UserRole role;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String,
      role: _parseRole(json['role'] as String?),
    );
  }

  static UserRole _parseRole(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return UserRole.ADMIN;
      case 'dealer':
        return UserRole.DEALER;
      case 'reseller':
        return UserRole.RESELLER;
      case 'customer':
        return UserRole.CUSTOMER;
      default:
        return UserRole.CUSTOMER;
    }
  }

  bool get isDealer => role == UserRole.DEALER;
  bool get isReseller => role == UserRole.RESELLER;
  bool get isAdmin => role == UserRole.ADMIN;

  @override
  List<Object?> get props => [id, name, email, role];
}