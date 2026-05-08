import 'package:equatable/equatable.dart';
import '../../../shared/models/device.dart';

abstract class DeviceEvent extends Equatable {
  const DeviceEvent();

  @override
  List<Object?> get props => [];
}

class LoadDevices extends DeviceEvent {}

class UpdateDevicesList extends DeviceEvent {
  final List<Device> devices;

  const UpdateDevicesList(this.devices);

  @override
  List<Object?> get props => [devices];
}

class LoadAlerts extends DeviceEvent {}

class UpdateAlertsList extends DeviceEvent {
  final List<dynamic> alerts; // Should be List<AlertModel>

  const UpdateAlertsList(this.alerts);

  @override
  List<Object?> get props => [alerts];
}

class RequestLock extends DeviceEvent {
  final String deviceId;
  final String reasonCode;
  final String note;
  final String totpCode;

  const RequestLock({
    required this.deviceId,
    required this.reasonCode,
    required this.note,
    required this.totpCode,
  });

  @override
  List<Object?> get props => [deviceId, reasonCode, note, totpCode];
}
