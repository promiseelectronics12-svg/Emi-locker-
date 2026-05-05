import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dealer_app/di.dart';
import 'package:dealer_app/features/auth/auth_bloc.dart';
import 'package:dealer_app/features/dealer/dealer_dashboard_screen.dart';
import 'package:dealer_app/features/dealer/bloc/analytics_bloc.dart';
import 'package:dealer_app/features/dealer/bloc/neir_export_bloc.dart';
import 'package:dealer_app/features/dealer/reseller_dashboard_screen.dart';
import 'package:dealer_app/features/auth/login_screen.dart';
import 'package:dealer_app/features/auth/two_fa_screen.dart';
import 'package:dealer_app/shared/services/device_management_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await dotenv.load(fileName: ".env");
  await setupDependencies();

  runApp(const DealerResellerApp());
}

class DealerResellerApp extends StatelessWidget {
  const DealerResellerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DeviceManagementService>(
          create: (context) => getIt<DeviceManagementService>(),
        ),
      ],
      child: BlocProvider<AuthBloc>(
        create: (context) => getIt<AuthBloc>()..add(AuthCheckRequested()),
        child: BlocProvider<AnalyticsBloc>(
          create: (context) => getIt<AnalyticsBloc>(),
          child: BlocProvider<NeirExportBloc>(
            create: (context) => getIt<NeirExportBloc>(),
            child: MaterialApp(
              title: 'EMI Locker',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: Colors.blue,
                brightness: Brightness.light,
              ),
              home: BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  if (state.status == AuthStatus.authenticated) {
                    if (state.userRole == 'DEALER') return const DealerDashboardScreen();
                    if (state.userRole == 'RESELLER') return const ResellerDashboardScreen();
                  }
                  if (state.status == AuthStatus.twoFactorRequired) {
                    return const TwoFactorScreen();
                  }
                  if (state.status == AuthStatus.initial) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return const LoginScreen();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
