import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  String? _msg;

  Future<void> _send() async {
    final client = ref.read(apiClientProvider);
    try {
      await client.postJson('/groups/${widget.groupId}/incidents', {
        'incident_type': 'lost_traveler',
        'severity': 'high',
        'notes': 'Traveler needs assistance — Lost in Brij flow',
        'payload_json': {'lat': 27.57, 'lng': 77.69},
      });
      setState(() => _msg = 'Guide and ops notified.');
    } catch (e) {
      setState(() => _msg = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS / Lost in Brij')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This sends a high-severity incident to your guide and admins. Use mindfully.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
                onPressed: _send,
                child: const Text('I need help now'),
              ),
              if (_msg != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_msg!)),
            ],
          ),
        ),
      ),
    );
  }
}
