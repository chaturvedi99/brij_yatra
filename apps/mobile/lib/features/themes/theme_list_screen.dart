import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';

class ThemeListScreen extends ConsumerWidget {
  const ThemeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      body: FutureBuilder<dynamic>(
        future: client.getJson('/themes'),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final list = snap.data as List<dynamic>;
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i] as Map<String, dynamic>;
              final slug = t['slug'] as String;
              final name = t['name'] as String;
              final summary = t['summary'] as String? ?? '';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(name),
                  subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => context.push('/themes/$slug'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
