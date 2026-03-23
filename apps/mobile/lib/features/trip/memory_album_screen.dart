import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class MemoryAlbumScreen extends ConsumerStatefulWidget {
  const MemoryAlbumScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<MemoryAlbumScreen> createState() => _MemoryAlbumScreenState();
}

class _MemoryAlbumScreenState extends ConsumerState<MemoryAlbumScreen> {
  String? _msg;

  Future<void> _compile() async {
    final client = ref.read(apiClientProvider);
    try {
      await client.postJson('/groups/${widget.groupId}/memory/compile', {});
      setState(() => _msg = 'Memory compilation queued (worker processes outbox).');
    } catch (e) {
      setState(() => _msg = e.toString());
    }
  }

  Future<void> _registerStubAsset() async {
    final client = ref.read(apiClientProvider);
    try {
      await client.postJson('/media/assets', {
        'group_id': widget.groupId,
        'kind': 'image',
        'storage_url': 'https://example.com/memory/stub.jpg',
        'meta_json': {'source': 'flutter_stub'},
      });
      setState(() => _msg = 'Registered stub media asset.');
    } catch (e) {
      setState(() => _msg = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory album')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Register a stub asset, then queue compilation on the worker.'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _registerStubAsset, child: const Text('Add stub photo ref')),
            FilledButton(onPressed: _compile, child: const Text('Queue memory compile')),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_msg!)),
          ],
        ),
      ),
    );
  }
}
