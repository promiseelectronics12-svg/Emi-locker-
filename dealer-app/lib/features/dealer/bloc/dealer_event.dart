part of 'dealer_bloc.dart';

abstract class DealerEvent extends Equatable {
  const DealerEvent();

  @override
  List<Object?> get props => [];
}

class LoadDashboard extends DealerEvent {}

class LoadDevices extends DealerEvent {
  final int page;
  final int limit;
  final String? status;
  final String? search;

  const LoadDevices({
    this.page = 1,
    this.limit = 20,
    this.status,
    this.search,
  });

  @override
  List<Object?> get props => [page, limit, status, search];
}

class LoadDeviceDetail extends DealerEvent {
  final String deviceId;

  const LoadDeviceDetail({required this.deviceId});

  @override
  List<Object?> get props => [deviceId];
}

class EnrollDevice extends DealerEvent {
  final Map<String, dynamic> data;

  const EnrollDevice({required this.data});

  @override
  List<Object?> get props => [data];
}

class SubmitLockRequest extends DealerEvent {
  final String deviceId;
  final String reasonCode;
  final String? note;

  const SubmitLockRequest({
    required this.deviceId,
    required this.reasonCode,
    this.note,
  });

  @override
  List<Object?> get props => [deviceId, reasonCode, note];
}

class SubmitFraudFlag extends DealerEvent {
  final String deviceId;
  final String reason;
  final Map<String, dynamic>? evidence;

  const SubmitFraudFlag({
    required this.deviceId,
    required this.reason,
    this.evidence,
  });

  @override
  List<Object?> get props => [deviceId, reason, evidence];
}

class VerifyNID extends DealerEvent {
  final String nid;
  final String dob;

  const VerifyNID({required this.nid, required this.dob});

  @override
  List<Object?> get props => [nid, dob];
}

class LoadAnalytics extends DealerEvent {}

class ExportNEIR extends DealerEvent {
  final DateTime startDate;
  final DateTime endDate;

  const ExportNEIR({required this.startDate, required this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

class LoadEMISchedule extends DealerEvent {
  final String deviceId;

  const LoadEMISchedule({required this.deviceId});

  @override
  List<Object?> get props => [deviceId];
}