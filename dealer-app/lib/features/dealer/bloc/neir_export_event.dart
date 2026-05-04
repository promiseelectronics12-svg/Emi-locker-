part of 'neir_export_bloc.dart';

abstract class NeirExportEvent extends Equatable {
  const NeirExportEvent();

  @override
  List<Object?> get props => [];
}

class LoadNeirDevices extends NeirExportEvent {}

class ExportNeirExcel extends NeirExportEvent {}

class ShareNeirExcel extends NeirExportEvent {}
