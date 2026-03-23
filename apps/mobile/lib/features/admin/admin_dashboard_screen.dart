import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<dynamic>(
            future: client.getJson('/admin/analytics/summary'),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ));
              }
              if (snap.hasError) {
                return Text('${snap.error}');
              }
              final m = snap.data as Map<String, dynamic>;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: m.entries
                        .map((e) => Text('${e.key}: ${e.value}'))
                        .toList(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('Requires admin role from bootstrap.'),
        ],
      ),
    );
  }
}
