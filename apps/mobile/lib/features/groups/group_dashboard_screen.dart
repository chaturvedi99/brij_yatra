import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';

class GroupDashboardScreen extends ConsumerWidget {
  const GroupDashboardScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: FutureBuilder<dynamic>(
        future: client.getJson('/groups/$groupId/dashboard'),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final data = snap.data as Map<String, dynamic>;
          final itin = data['itinerary'] as List<dynamic>? ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Itinerary', style: Theme.of(context).textTheme.titleMedium),
              ...itin.map((e) {
                final m = e as Map<String, dynamic>;
                return ListTile(
                  title: Text(m['stop_name']?.toString() ?? ''),
                  subtitle: Text('Status: ${m['progress']}'),
                );
              }),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.support_agent),
                title: const Text('Service request'),
                onTap: () => context.push('/groups/$groupId/request'),
              ),
              ListTile(
                leading: const Icon(Icons.sos),
                title: const Text('SOS / Lost in Brij'),
                onTap: () => context.push('/groups/$groupId/sos'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Memory album'),
                onTap: () => context.push('/groups/$groupId/memory'),
              ),
            ],
          );
        },
      ),
    );
  }
}
