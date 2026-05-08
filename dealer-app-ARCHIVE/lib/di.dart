import 'package:get_it/get_it.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dealer_app/shared/api/api_client.dart';
import 'package:dealer_app/shared/api/auth_repository.dart';
import 'package:dealer_app/shared/api/analytics_repository.dart';
import 'package:dealer_app/shared/api/firebase_service.dart';
import 'package:dealer_app/shared/services/device_management_service.dart';
import 'package:dealer_app/features/auth/auth_bloc.dart';
import 'package:dealer_app/features/dealer/bloc/analytics_bloc.dart';
import 'package:dealer_app/features/dealer/bloc/neir_export_bloc.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  const storage = FlutterSecureStorage();
  getIt.registerSingleton<FlutterSecureStorage>(storage);

  final apiClient = ApiClient();
  getIt.registerSingleton<ApiClient>(apiClient);

  final authRepository = AuthRepository(apiClient);
  getIt.registerSingleton<AuthRepository>(authRepository);

  final analyticsRepository = AnalyticsRepository(apiClient);
  getIt.registerSingleton<AnalyticsRepository>(analyticsRepository);

  final firebaseService = FirebaseService();
  getIt.registerSingleton<FirebaseService>(firebaseService);

  final deviceManagementService = DeviceManagementService(dio: apiClient.dio);
  getIt.registerSingleton<DeviceManagementService>(deviceManagementService);

  getIt.registerFactory<AuthBloc>(() => AuthBloc(authRepository));
  getIt.registerFactory<AnalyticsBloc>(() => AnalyticsBloc(analyticsRepository));
  getIt.registerFactory<NeirExportBloc>(() => NeirExportBloc(apiClient));
}
