part of 'neir_export_bloc.dart';

abstract class NeirExportState extends Equatable {
  const NeirExportState();

  @override
  List<Object?> get props => [];
}

class NeirExportInitial extends NeirExportState {}

class NeirExportLoading extends NeirExportState {}

class NeirDevicesLoaded extends NeirExportState {
  final List<NeirDeviceRecord> devices;

  const NeirDevicesLoaded(this.devices);

  @override
  List<Object?> get props => [devices];
}

class NeirExportSuccess extends NeirExportState {
  final File file;

  const NeirExportSuccess(this.file);

  @override
  List<Object?> get props => [file];
}

class NeirExportShared extends NeirExportState {
  final int deviceCount;

  const NeirExportShared(this.deviceCount);

  @override
  List<Object?> get props => [deviceCount];
}

class NeirExportError extends NeirExportState {
  final String message;

  const NeirExportError(this.message);

  @override
  List<Object?> get props => [message];
}
