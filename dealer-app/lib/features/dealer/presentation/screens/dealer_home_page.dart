import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/bloc/auth_bloc.dart';
import '../../../shared/models/device_model.dart';
import '../../../shared/repositories/device_repository.dart';

class DealerHomePage extends StatelessWidget {
  const DealerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dealer Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthBloc>().add(LogoutEvent()),
          ),
        ],
      ),
      body: FutureBuilder<List<DeviceModel>>(
        future: DeviceRepository().getDevices(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final devices = snapshot.data ?? [];
          return ListView.builder(
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                child: ListTile(
                  title: Text(device.imei ?? 'Unknown'),
                  subtitle: Text(device.status ?? 'Unknown'),
                  trailing: Icon(
                    device.status == 'ACTIVE' ? Icons.check_circle : Icons.warning,
                    color: device.status == 'ACTIVE' ? Colors.green : Colors.orange,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}