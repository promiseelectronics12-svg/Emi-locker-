import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/env_config.dart';
import '../security/command_signer.dart';
import '../security/hardware_binding.dart';

final getIt = GetIt.instance;

class Injection {
  Injection._();

  static late FlutterSecureStorage secureStorage;

  static Future<void> init() async {
    EnvConfig.validateAll();

    secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    );

    CommandSigner.configure(secureStorage);

    getIt.registerLazySingleton<FlutterSecureStorage>(() => secureStorage);
    getIt.registerLazySingleton<CommandSigner>(() => CommandSigner());
    getIt.registerLazySingleton<HardwareBinding>(() => HardwareBinding());
  }

  static Future<void> dispose() async {
    await getIt.reset();
  }
}
