import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _groupId = TextEditingController();
  final _guideUserId = TextEditingController();
  final _verifyGuideUserId = TextEditingController();
  bool _approveGuide = true;
  String? _actionMsg;

  @override
  void dispose() {
    _groupId.dispose();
    _guideUserId.dispose();
    _verifyGuideUserId.dispose();
    super.dispose();
  }

  Future<void> _assignGuide() async {
    final gid = _groupId.text.trim();
    final guideId = _guideUserId.text.trim();
    if (gid.isEmpty || guideId.isEmpty) {
      setState(() => _actionMsg = 'Group ID and Guide User ID are required.');
      return;
    }
    final client = ref.read(apiClientProvider);
    try {
      await client.postJson('/admin/groups/$gid/assign-guide', {
        'guide_user_id': guideId,
      });
      setState(() => _actionMsg = 'Guide assigned successfully.');
    } catch (e) {
      setState(() => _actionMsg = e.toString());
    }
  }

  Future<void> _verifyGuide() async {
    final guideId = _verifyGuideUserId.text.trim();
    if (guideId.isEmpty) {
      setState(() => _actionMsg = 'Guide User ID is required.');
      return;
    }
    final client = ref.read(apiClientProvider);
    try {
      await client.patchJson('/admin/guides/$guideId/verify', {
        'verified': _approveGuide,
      });
      setState(() => _actionMsg = 'Guide verification updated.');
    } catch (e) {
      setState(() => _actionMsg = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Operational summary', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<dynamic>(
            future: client.getJson('/admin/analytics/summary'),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snap.hasError) {
                return Text('Summary unavailable: ${snap.error}');
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
          Text('Bookings', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<dynamic>(
            future: client.getJson('/admin/bookings'),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
              }
              if (snap.hasError) {
                return Text('Bookings unavailable: ${snap.error}');
              }
              final rows = snap.data as List<dynamic>;
              if (rows.isEmpty) return const Text('No bookings found.');
              return Card(
                child: Column(
                  children: rows.take(8).map((row) {
                    final b = row as Map<String, dynamic>;
                    return ListTile(
                      dense: true,
                      title: Text('${b['theme_slug']} (${b['status']})'),
                      subtitle: Text('Booking ${b['id']} | Payment ${b['payment_status']}'),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Open incidents', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<dynamic>(
            future: client.getJson('/admin/incidents'),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
              }
              if (snap.hasError) {
                return Text('Incidents unavailable: ${snap.error}');
              }
              final rows = snap.data as List<dynamic>;
              if (rows.isEmpty) return const Text('No active incidents.');
              return Card(
                child: Column(
                  children: rows.take(8).map((row) {
                    final i = row as Map<String, dynamic>;
                    return ListTile(
                      dense: true,
                      title: Text('${i['incident_type']} (${i['severity']})'),
                      subtitle: Text('Group ${i['group_id']} | ${i['status']}'),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text('Guide operations', style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _groupId,
            decoration: const InputDecoration(labelText: 'Group ID'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _guideUserId,
            decoration: const InputDecoration(labelText: 'Guide User ID'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _assignGuide,
            child: const Text('Assign guide to group'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _verifyGuideUserId,
            decoration: const InputDecoration(labelText: 'Guide User ID to verify'),
          ),
          SwitchListTile(
            value: _approveGuide,
            onChanged: (v) => setState(() => _approveGuide = v),
            title: const Text('Verified badge'),
          ),
          FilledButton(
            onPressed: _verifyGuide,
            child: const Text('Update guide verification'),
          ),
          if (_actionMsg != null) ...[
            const SizedBox(height: 8),
            Text(_actionMsg!),
          ],
        ],
      ),
    );
  }
}
