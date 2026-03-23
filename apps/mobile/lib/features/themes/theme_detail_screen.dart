import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';

class ThemeDetailScreen extends ConsumerWidget {
  const ThemeDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: Text(slug)),
      body: FutureBuilder<dynamic>(
        future: Future.wait([
          client.getJson('/themes/$slug'),
          client.getJson('/themes/$slug/itinerary'),
        ]),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final data = snap.data as List<dynamic>;
          final theme = data[0] as Map<String, dynamic>;
          final steps = data[1] as List<dynamic>;
          final summary = theme['summary'] as String? ?? '';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(summary, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              Text('Itinerary preview', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...steps.map((s) {
                final m = s as Map<String, dynamic>;
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(m['stop_name'] as String? ?? ''),
                  subtitle: Text(m['description'] as String? ?? ''),
                );
              }),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.push('/themes/$slug/book'),
                child: const Text('Begin booking'),
              ),
            ],
          );
        },
      ),
    );
  }
}
