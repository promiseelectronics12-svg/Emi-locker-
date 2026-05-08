import 'package:equatable/equatable.dart';

enum UserRole { DEALER, RESELLER, UNKNOWN }

class UserSession extends Equatable {
  final String id;
  final String email;
  final UserRole role;
  final String? token;

  const UserSession({
    required this.id,
    required this.email,
    required this.role,
    this.token,
  });

  @override
  List<Object?> get props => [id, email, role, token];
}
