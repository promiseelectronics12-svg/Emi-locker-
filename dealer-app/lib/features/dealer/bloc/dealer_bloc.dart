import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../shared/services/api_client.dart';
import '../../shared/models/device_model.dart';
import '../../shared/constants/constants.dart';

part 'dealer_event.dart';
part 'dealer_state.dart';

class DealerBloc extends Bloc<DealerEvent, DealerState> {
  final ApiClient _apiClient;

  DealerBloc({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient(),
        super(const DealerState()) {
    on<LoadDashboard>(_onLoadDashboard);
    on<LoadDevices>(_onLoadDevices);
    on<LoadDeviceDetail>(_onLoadDeviceDetail);
    on<EnrollDevice>(_onEnrollDevice);
    on<SubmitLockRequest>(_onSubmitLockRequest);
    on<SubmitFraudFlag>(_onSubmitFraudFlag);
    on<VerifyNID>(_onVerifyNID);
    on<LoadAnalytics>(_onLoadAnalytics);
    on<ExportNEIR>(_onExportNEIR);
    on<LoadEMISchedule>(_onLoadEMISchedule);
  }

  Future<void> _onLoadDashboard(
    LoadDashboard event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.get(ApiConstants.analyticsEndpoint);

      if (response.statusCode == 200) {
        final analytics = AnalyticsData.fromJson(response.data);
        final devicesResponse = await _apiClient.get(
          ApiConstants.devicesEndpoint,
          queryParameters: {'limit': 5, 'sortBy': 'enrolledAt', 'order': 'desc'},
        );

        List<Device> recentDevices = [];
        if (devicesResponse.statusCode == 200) {
          final List<dynamic> data = devicesResponse.data['devices'] ?? [];
          recentDevices = data.map((d) => Device.fromJson(d)).toList();
        }

        emit(state.copyWith(
          isLoading: false,
          analytics: analytics,
          recentDevices: recentDevices,
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to load dashboard',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onLoadDevices(
    LoadDevices event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.get(
        ApiConstants.devicesEndpoint,
        queryParameters: {
          'page': event.page,
          'limit': event.limit,
          if (event.status != null) 'status': event.status,
          if (event.search != null) 'search': event.search,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['devices'] ?? [];
        final devices = data.map((d) => Device.fromJson(d)).toList();
        final total = response.data['total'] ?? 0;

        emit(state.copyWith(
          isLoading: false,
          devices: devices,
          totalDevices: total,
          hasMoreDevices: devices.length == event.limit,
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to load devices',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onLoadDeviceDetail(
    LoadDeviceDetail event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.get('${ApiConstants.devicesEndpoint}/${event.deviceId}');

      if (response.statusCode == 200) {
        final device = Device.fromJson(response.data);
        emit(state.copyWith(
          isLoading: false,
          selectedDevice: device,
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to load device',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onEnrollDevice(
    EnrollDevice event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.post(
        ApiConstants.enrollDeviceEndpoint,
        data: event.data,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final device = Device.fromJson(response.data);
        emit(state.copyWith(
          isLoading: false,
          enrolledDevice: device,
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to enroll device',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onSubmitLockRequest(
    SubmitLockRequest event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.post(
        ApiConstants.lockRequestEndpoint,
        data: {
          'deviceId': event.deviceId,
          'reasonCode': event.reasonCode,
          'note': event.note,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        emit(state.copyWith(
          isLoading: false,
          lockRequestSubmitted: true,
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to submit lock request',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onSubmitFraudFlag(
    SubmitFraudFlag event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.post(
        ApiConstants.fraudFlagEndpoint,
        data: {
          'deviceId': event.deviceId,
          'reason': event.reason,
          'evidence': event.evidence,
        },
      );

      if (response.statusCode == 200) {
        emit(state.copyWith(
          isLoading: false,
          fraudFlagSubmitted: true,
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to submit fraud flag',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onVerifyNID(
    VerifyNID event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.post(
        '/api/verify/nid',
        data: {
          'nid': event.nid,
          'dob': event.dob,
        },
      );

      if (response.statusCode == 200) {
        emit(state.copyWith(
          isLoading: false,
          nidVerificationResult: NIDVerificationResult.fromJson(response.data),
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'NID verification failed',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onLoadAnalytics(
    LoadAnalytics event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.get(ApiConstants.analyticsEndpoint);

      if (response.statusCode == 200) {
        final analytics = AnalyticsData.fromJson(response.data);
        emit(state.copyWith(
          isLoading: false,
          analytics: analytics,
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to load analytics',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onExportNEIR(
    ExportNEIR event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.get(
        ApiConstants.neirExportEndpoint,
        queryParameters: {
          'startDate': event.startDate.toIso8601String(),
          'endDate': event.endDate.toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        emit(state.copyWith(
          isLoading: false,
          neirExportPath: response.data['filePath'],
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to export NEIR',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  Future<void> _onLoadEMISchedule(
    LoadEMISchedule event,
    Emitter<DealerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await _apiClient.get(
        ApiConstants.emiScheduleEndpoint,
        queryParameters: {'deviceId': event.deviceId},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['schedule'] ?? [];
        final schedule = data.map((s) => EMISchedule.fromJson(s)).toList();
        emit(state.copyWith(
          isLoading: false,
          emiSchedule: schedule,
        ));
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: response.data['message'] ?? 'Failed to load EMI schedule',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      ));
    }
  }

  String _getErrorMessage(dynamic error) {
    if (error is ApiException) {
      return error.message;
    }
    return 'An unexpected error occurred. Please try again.';
  }
}

class NIDVerificationResult {
  final bool isValid;
  final String? name;
  final String? fatherName;
  final String? motherName;
  final String? dateOfBirth;
  final String? permanentAddress;

  NIDVerificationResult({
    required this.isValid,
    this.name,
    this.fatherName,
    this.motherName,
    this.dateOfBirth,
    this.permanentAddress,
  });

  factory NIDVerificationResult.fromJson(Map<String, dynamic> json) {
    return NIDVerificationResult(
      isValid: json['isValid'] ?? false,
      name: json['name'],
      fatherName: json['fatherName'],
      motherName: json['motherName'],
      dateOfBirth: json['dateOfBirth'],
      permanentAddress: json['permanentAddress'],
    );
  }
}