import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'device_event.dart';
import 'device_state.dart';
import '../../../shared/api/device_repository.dart';
import '../../../shared/api/firebase_service.dart';
import '../../../shared/models/alert_model.dart';
import '../../../shared/api/api_client.dart';

class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final DeviceRepository _deviceRepository;
  final FirebaseService _firebaseService;
  final String dealerId;
  StreamSubscription? _devicesSubscription;

  DeviceBloc({
    required DeviceRepository deviceRepository,
    required FirebaseService firebaseService,
    required this.dealerId,
  })  : _deviceRepository = deviceRepository,
        _firebaseService = firebaseService,
        super(const DeviceState()) {
    on<LoadDevices>(_onLoadDevices);
    on<UpdateDevicesList>(_onUpdateDevicesList);
    on<LoadAlerts>(_onLoadAlerts);
    on<RequestLock>(_onRequestLock);
    
    _startFirebaseListener();
  }

  void _startFirebaseListener() {
    _devicesSubscription?.cancel();
    _devicesSubscription = _firebaseService.listenToDealerDevices(dealerId).listen((devices) {
      add(UpdateDevicesList(devices));
    });
  }

  Future<void> _onLoadDevices(LoadDevices event, Emitter<DeviceState> emit) async {
    emit(state.copyWith(status: DeviceStatusType.loading));
    try {
      final devices = await _deviceRepository.getDevices();
      emit(state.copyWith(
        status: DeviceStatusType.success,
        devices: devices,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: DeviceStatusType.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onUpdateDevicesList(UpdateDevicesList event, Emitter<DeviceState> emit) {
    emit(state.copyWith(
      status: DeviceStatusType.success,
      devices: event.devices,
    ));
  }

  Future<void> _onLoadAlerts(LoadAlerts event, Emitter<DeviceState> emit) async {
    // In a real app, this would fetch from an API or another Firebase node
    // For now, let's mock some alerts based on device states
    final mockAlerts = state.devices.where((d) => d.status == DeviceStatus.compromised).map((d) => AlertModel(
      id: 'alert_${d.id}',
      deviceId: d.id,
      type: AlertType.fraudAlert,
      severity: AlertSeverity.critical,
      title: 'Security Compromised',
      message: 'Device ${d.model} (IMEI: ${d.imei1}) has detected a security violation.',
      createdAt: DateTime.now(),
    )).toList();
    
    emit(state.copyWith(alerts: mockAlerts));
  }

  Future<void> _onRequestLock(RequestLock event, Emitter<DeviceState> emit) async {
    emit(state.copyWith(isSubmittingLock: true, lockRequestResult: null, isLockRequestApproved: null));
    try {
      // Simulate server verification logic
      final apiClient = ApiClient();
      final response = await apiClient.post('/devices/${event.deviceId}/lock-request', data: {
        'reason_code': event.reasonCode,
        'note': event.note,
        'totp_code': event.totpCode,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final bool approved = data['status'] == 'APPROVED';
        emit(state.copyWith(
          isSubmittingLock: false,
          isLockRequestApproved: approved,
          lockRequestResult: approved ? 'APPROVED' : data['reason'] ?? 'REJECTED',
        ));
      } else {
        emit(state.copyWith(
          isSubmittingLock: false,
          isLockRequestApproved: false,
          lockRequestResult: 'Server returned error: ${response.statusCode}',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isSubmittingLock: false,
        isLockRequestApproved: false,
        lockRequestResult: e.toString(),
      ));
    }
  }

  @override
  Future<void> close() {
    _devicesSubscription?.cancel();
    return super.close();
  }
}
