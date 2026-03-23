import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class ServiceRequestScreen extends ConsumerStatefulWidget {
  const ServiceRequestScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends ConsumerState<ServiceRequestScreen> {
  final _cat = TextEditingController(text: 'food');
  final _text = TextEditingController();
  String? _msg;

  Future<void> _submit() async {
    final client = ref.read(apiClientProvider);
    try {
      await client.postJson('/groups/${widget.groupId}/service-requests', {
        'category': _cat.text,
        'request_text': _text.text,
        'priority': 'normal',
      });
      setState(() => _msg = 'Request submitted');
    } catch (e) {
      setState(() => _msg = e.toString());
    }
  }

  @override
  void dispose() {
    _cat.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Service request')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _cat, decoration: const InputDecoration(labelText: 'Category')),
            TextField(controller: _text, decoration: const InputDecoration(labelText: 'Details')),
            FilledButton(onPressed: _submit, child: const Text('Submit')),
            if (_msg != null) Text(_msg!),
          ],
        ),
      ),
    );
  }
}
