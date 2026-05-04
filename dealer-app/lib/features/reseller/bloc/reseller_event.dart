import 'package:equatable/equatable.dart';
import '../../../shared/models/user.dart';

abstract class ResellerEvent extends Equatable {
  const ResellerEvent();

  @override
  List<Object?> get props => [];
}

class ResellerLoadDealers extends ResellerEvent {
  final int page;
  final int limit;
  final String? search;

  const ResellerLoadDealers({
    this.page = 1,
    this.limit = 20,
    this.search,
  });

  @override
  List<Object?> get props => [page, limit, search];
}

class ResellerLoadKeys extends ResellerEvent {
  final String? status;

  const ResellerLoadKeys({this.status});

  @override
  List<Object?> get props => [status];
}

class ResellerApproveDealer extends ResellerEvent {
  final String dealerId;

  const ResellerApproveDealer({required this.dealerId});

  @override
  List<Object?> get props => [dealerId];
}

class ResellerSuspendDealer extends ResellerEvent {
  final String dealerId;

  const ResellerSuspendDealer({required this.dealerId});

  @override
  List<Object?> get props => [dealerId];
}

class ResellerAddKeys extends ResellerEvent {
  final int quantity;

  const ResellerAddKeys({required this.quantity});

  @override
  List<Object?> get props => [quantity];
}

class ResellerTransferKeys extends ResellerEvent {
  final String dealerId;
  final int quantity;

  const ResellerTransferKeys({
    required this.dealerId,
    required this.quantity,
  });

  @override
  List<Object?> get props => [dealerId, quantity];
}

abstract class ResellerState extends Equatable {
  const ResellerState();

  @override
  List<Object?> get props => [];
}

class ResellerInitial extends ResellerState {}

class ResellerLoading extends ResellerState {}

class ResellerLoaded extends ResellerState {
  final List<User> dealers;
  final int totalCount;
  final int currentPage;

  const ResellerLoaded({
    required this.dealers,
    required this.totalCount,
    required this.currentPage,
  });

  @override
  List<Object?> get props => [dealers, totalCount, currentPage];
}

class ResellerKeysLoaded extends ResellerState {
  final int availableKeys;
  final int usedKeys;
  final int totalKeys;

  const ResellerKeysLoaded({
    required this.availableKeys,
    required this.usedKeys,
    required this.totalKeys,
  });

  @override
  List<Object?> get props => [availableKeys, usedKeys, totalKeys];
}

class ResellerOperationSuccess extends ResellerState {
  final String message;

  const ResellerOperationSuccess({required this.message});

  @override
  List<Object?> get props => [message];
}

class ResellerError extends ResellerState {
  final String message;

  const ResellerError({required this.message});

  @override
  List<Object?> get props => [message];
}