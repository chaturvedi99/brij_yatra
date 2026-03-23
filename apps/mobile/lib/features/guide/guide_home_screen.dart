import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';

class GuideHomeScreen extends ConsumerWidget {
  const GuideHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Guide')),
      body: FutureBuilder<dynamic>(
        future: client.getJson('/guide/groups'),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final list = snap.data as List<dynamic>;
          if (list.isEmpty) {
            return const Center(
              child: Text('No assigned groups yet. Ask admin to assign you.'),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final g = list[i] as Map<String, dynamic>;
              final id = g['group_id'].toString();
              return ListTile(
                title: Text('Group $id'),
                subtitle: Text('Status: ${g['status']}'),
                onTap: () => context.push('/g/groups/$id'),
              );
            },
          );
        },
      ),
    );
  }
}
