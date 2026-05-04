import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/api/auth_repository.dart';
import '../../shared/models/user.dart';

enum AuthStatus { initial, authenticated, unauthenticated, twoFactorRequired }

class AuthState extends Equatable {
  final AuthStatus status;
  final User? user;
  final String? userRole;
  final String? error;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.userRole,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? userRole,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      userRole: userRole ?? this.userRole,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, user, userRole, error];
}

abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String phone;
  final String password;
  AuthLoginRequested(this.phone, this.password);
  @override
  List<Object?> get props => [phone, password];
}

class AuthTwoFactorVerified extends AuthEvent {
  final String code;
  final String phone;
  final String password;
  AuthTwoFactorVerified({required this.code, required this.phone, required this.password});
  @override
  List<Object?> get props => [code, phone, password];
}

class AuthLogoutRequested extends AuthEvent {}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc(this._authRepository) : super(const AuthState()) {
    on<AuthCheckRequested>(_onCheck);
    on<AuthLoginRequested>(_onLogin);
    on<AuthTwoFactorVerified>(_onTwoFactorVerify);
    on<AuthLogoutRequested>(_onLogout);
  }

  Future<void> _onCheck(AuthCheckRequested event, Emitter<AuthState> emit) async {
    try {
      final user = await _authRepository.getCurrentUser();
      if (user != null) {
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          userRole: user.role.name.toUpperCase(),
        ));
      } else {
        emit(state.copyWith(status: AuthStatus.unauthenticated));
      }
    } catch (e) {
      emit(state.copyWith(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onLogin(AuthLoginRequested event, Emitter<AuthState> emit) async {
    try {
      final user = await _authRepository.login(phone: event.phone, password: event.password);
      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        userRole: user.role.name.toUpperCase(),
      ));
    } catch (e) {
      if (e.toString().contains('2FA_REQUIRED')) {
        emit(state.copyWith(status: AuthStatus.twoFactorRequired));
      } else {
        emit(state.copyWith(status: AuthStatus.unauthenticated, error: e.toString()));
      }
    }
  }

  Future<void> _onTwoFactorVerify(AuthTwoFactorVerified event, Emitter<AuthState> emit) async {
    try {
      final user = await _authRepository.login(
        phone: event.phone,
        password: event.password,
        twoFactorCode: event.code,
      );
      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        userRole: user.role.name.toUpperCase(),
      ));
    } catch (e) {
      emit(state.copyWith(status: AuthStatus.twoFactorRequired, error: e.toString()));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await _authRepository.logout();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }
}
