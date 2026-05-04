import 'package:equatable/equatable.dart';
import '../../../shared/models/device.dart';
import '../../../shared/models/alert_model.dart';

enum DeviceStatusType { initial, loading, success, failure }

class DeviceState extends Equatable {
  final DeviceStatusType status;
  final List<Device> devices;
  final List<AlertModel> alerts;
  final String? errorMessage;
  final bool isSubmittingLock;
  final String? lockRequestResult;
  final bool? isLockRequestApproved;

  const DeviceState({
    this.status = DeviceStatusType.initial,
    this.devices = const [],
    this.alerts = const [],
    this.errorMessage,
    this.isSubmittingLock = false,
    this.lockRequestResult,
    this.isLockRequestApproved,
  });

  DeviceState copyWith({
    DeviceStatusType? status,
    List<Device>? devices,
    List<AlertModel>? alerts,
    String? errorMessage,
    bool? isSubmittingLock,
    String? lockRequestResult,
    bool? isLockRequestApproved,
  }) {
    return DeviceState(
      status: status ?? this.status,
      devices: devices ?? this.devices,
      alerts: alerts ?? this.alerts,
      errorMessage: errorMessage ?? this.errorMessage,
      isSubmittingLock: isSubmittingLock ?? this.isSubmittingLock,
      lockRequestResult: lockRequestResult ?? this.lockRequestResult,
      isLockRequestApproved: isLockRequestApproved ?? this.isLockRequestApproved,
    );
  }

  @override
  List<Object?> get props => [
        status,
        devices,
        alerts,
        errorMessage,
        isSubmittingLock,
        lockRequestResult,
        isLockRequestApproved,
      ];
}
