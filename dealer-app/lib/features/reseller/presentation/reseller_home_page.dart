import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/bloc/auth_bloc.dart';
import '../../../shared/repositories/reseller_repository.dart';

class ResellerHomePage extends StatelessWidget {
  const ResellerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reseller Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthBloc>().add(LogoutEvent()),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: ResellerRepository().getDashboardStats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final stats = snapshot.data ?? {};
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Keys: ${stats['totalKeys'] ?? 0}', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text('Active Dealers: ${stats['activeDealers'] ?? 0}', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text('Revenue: \$${stats['revenue'] ?? 0}', style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          );
        },
      ),
    );
  }
}