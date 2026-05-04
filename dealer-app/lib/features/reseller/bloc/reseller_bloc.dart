import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../shared/api/api_client.dart';
import '../../../shared/models/user.dart';
import 'reseller_event.dart';

class ResellerBloc extends Bloc<ResellerEvent, ResellerState> {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ResellerBloc({required ApiClient apiClient})
      : _apiClient = apiClient,
        super(ResellerInitial()) {
    on<ResellerLoadDealers>(_onLoadDealers);
    on<ResellerLoadKeys>(_onLoadKeys);
    on<ResellerApproveDealer>(_onApproveDealer);
    on<ResellerSuspendDealer>(_onSuspendDealer);
    on<ResellerAddKeys>(_onAddKeys);
    on<ResellerTransferKeys>(_onTransferKeys);
  }

  Future<void> _onLoadDealers(
    ResellerLoadDealers event,
    Emitter<ResellerState> emit,
  ) async {
    emit(ResellerLoading());
    try {
      final response = await _apiClient.get(
        '/resellers/dealers',
        queryParameters: {
          'page': event.page,
          'limit': event.limit,
          if (event.search != null) 'search': event.search,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> dealersJson = data['dealers'] as List<dynamic>;
      final dealers = dealersJson
          .map((json) => User.fromJson(json as Map<String, dynamic>))
          .toList();

      emit(ResellerLoaded(
        dealers: dealers,
        totalCount: data['total'] as int? ?? 0,
        currentPage: event.page,
      ));
    } catch (e) {
      emit(ResellerError(message: e.toString()));
    }
  }

  Future<void> _onLoadKeys(
    ResellerLoadKeys event,
    Emitter<ResellerState> emit,
  ) async {
    emit(ResellerLoading());
    try {
      final response = await _apiClient.get(
        '/resellers/keys',
        queryParameters: {
          if (event.status != null) 'status': event.status,
        },
      );

      final data = response.data as Map<String, dynamic>;
      emit(ResellerKeysLoaded(
        availableKeys: data['available'] as int? ?? 0,
        usedKeys: data['used'] as int? ?? 0,
        totalKeys: data['total'] as int? ?? 0,
      ));
    } catch (e) {
      emit(ResellerError(message: e.toString()));
    }
  }

  Future<void> _onApproveDealer(
    ResellerApproveDealer event,
    Emitter<ResellerState> emit,
  ) async {
    emit(ResellerLoading());
    try {
      await _apiClient.post('/resellers/dealers/${event.dealerId}/approve');
      emit(const ResellerOperationSuccess(
        message: 'Dealer approved successfully',
      ));
    } catch (e) {
      emit(ResellerError(message: e.toString()));
    }
  }

  Future<void> _onSuspendDealer(
    ResellerSuspendDealer event,
    Emitter<ResellerState> emit,
  ) async {
    emit(ResellerLoading());
    try {
      await _apiClient.post('/resellers/dealers/${event.dealerId}/suspend');
      emit(const ResellerOperationSuccess(
        message: 'Dealer suspended successfully',
      ));
    } catch (e) {
      emit(ResellerError(message: e.toString()));
    }
  }

  Future<void> _onAddKeys(
    ResellerAddKeys event,
    Emitter<ResellerState> emit,
  ) async {
    emit(ResellerLoading());
    try {
      final response = await _apiClient.post(
        '/resellers/keys/generate',
        data: {'quantity': event.quantity},
      );

      final data = response.data as Map<String, dynamic>;
      emit(ResellerOperationSuccess(
        message: 'Added ${data['added'] ?? event.quantity} keys',
      ));
    } catch (e) {
      emit(ResellerError(message: e.toString()));
    }
  }

  Future<void> _onTransferKeys(
    ResellerTransferKeys event,
    Emitter<ResellerState> emit,
  ) async {
    emit(ResellerLoading());
    try {
      await _apiClient.post(
        '/resellers/keys/transfer',
        data: {
          'dealer_id': event.dealerId,
          'quantity': event.quantity,
        },
      );

      emit(const ResellerOperationSuccess(
        message: 'Keys transferred successfully',
      ));
    } catch (e) {
      emit(ResellerError(message: e.toString()));
    }
  }
}