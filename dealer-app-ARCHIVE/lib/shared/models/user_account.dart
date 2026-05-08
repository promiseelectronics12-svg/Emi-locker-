import 'package:equatable/equatable.dart';

enum UserRole { DEALER, RESELLER, UNKNOWN }

class UserAccount extends Equatable {
  final String id;
  final String email;
  final UserRole role;
  final String shopName;
  final String resellerCode;

  const UserAccount({
    required this.id,
    required this.email,
    required this.role,
    this.shopName = '',
    this.resellerCode = '',
  });

  @override
  List<Object?> get props => [id, email, role, shopName, resellerCode];
}
