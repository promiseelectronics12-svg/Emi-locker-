part of 'dealer_bloc.dart';

class DealerState extends Equatable {
  final bool isLoading;
  final String? error;
  final AnalyticsData? analytics;
  final List<Device> devices;
  final List<Device> recentDevices;
  final Device? selectedDevice;
  final Device? enrolledDevice;
  final List<EMISchedule> emiSchedule;
  final int totalDevices;
  final bool hasMoreDevices;
  final bool lockRequestSubmitted;
  final bool fraudFlagSubmitted;
  final NIDVerificationResult? nidVerificationResult;
  final String? neirExportPath;

  const DealerState({
    this.isLoading = false,
    this.error,
    this.analytics,
    this.devices = const [],
    this.recentDevices = const [],
    this.selectedDevice,
    this.enrolledDevice,
    this.emiSchedule = const [],
    this.totalDevices = 0,
    this.hasMoreDevices = false,
    this.lockRequestSubmitted = false,
    this.fraudFlagSubmitted = false,
    this.nidVerificationResult,
    this.neirExportPath,
  });

  DealerState copyWith({
    bool? isLoading,
    String? error,
    AnalyticsData? analytics,
    List<Device>? devices,
    List<Device>? recentDevices,
    Device? selectedDevice,
    Device? enrolledDevice,
    List<EMISchedule>? emiSchedule,
    int? totalDevices,
    bool? hasMoreDevices,
    bool? lockRequestSubmitted,
    bool? fraudFlagSubmitted,
    NIDVerificationResult? nidVerificationResult,
    String? neirExportPath,
  }) {
    return DealerState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      analytics: analytics ?? this.analytics,
      devices: devices ?? this.devices,
      recentDevices: recentDevices ?? this.recentDevices,
      selectedDevice: selectedDevice ?? this.selectedDevice,
      enrolledDevice: enrolledDevice ?? this.enrolledDevice,
      emiSchedule: emiSchedule ?? this.emiSchedule,
      totalDevices: totalDevices ?? this.totalDevices,
      hasMoreDevices: hasMoreDevices ?? this.hasMoreDevices,
      lockRequestSubmitted: lockRequestSubmitted ?? this.lockRequestSubmitted,
      fraudFlagSubmitted: fraudFlagSubmitted ?? this.fraudFlagSubmitted,
      nidVerificationResult: nidVerificationResult ?? this.nidVerificationResult,
      neirExportPath: neirExportPath ?? this.neirExportPath,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        error,
        analytics,
        devices,
        recentDevices,
        selectedDevice,
        enrolledDevice,
        emiSchedule,
        totalDevices,
        hasMoreDevices,
        lockRequestSubmitted,
        fraudFlagSubmitted,
        nidVerificationResult,
        neirExportPath,
      ];
}