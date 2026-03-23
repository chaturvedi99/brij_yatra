import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

class BookingHistoryScreen extends ConsumerWidget {
  const BookingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: FutureBuilder<dynamic>(
        future: client.getJson('/bookings/mine'),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Unable to load bookings: ${snap.error}'));
          }
          final rows = snap.data as List<dynamic>;
          if (rows.isEmpty) {
            return const Center(
              child: Text('No bookings yet. Explore themes to start your yatra.'),
            );
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final b = rows[i] as Map<String, dynamic>;
              final id = b['id'].toString();
              final title = b['theme_name']?.toString() ?? b['theme_slug']?.toString() ?? 'Theme';
              final dateStart = b['date_start']?.toString() ?? '';
              final dateEnd = b['date_end']?.toString() ?? '';
              final status = b['status']?.toString() ?? 'unknown';
              final payment = b['payment_status']?.toString() ?? 'unknown';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(title),
                  subtitle: Text('$dateStart -> $dateEnd\nBooking: $id\nStatus: $status | Payment: $payment'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.history),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
