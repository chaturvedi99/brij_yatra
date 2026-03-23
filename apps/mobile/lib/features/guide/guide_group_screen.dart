import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class GuideGroupScreen extends ConsumerStatefulWidget {
  const GuideGroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GuideGroupScreen> createState() => _GuideGroupScreenState();
}

class _GuideGroupScreenState extends ConsumerState<GuideGroupScreen> {
  final _otp = TextEditingController();
  final _announcement = TextEditingController();
  String? _msg;
  Map<String, dynamic>? _detail;

  Future<void> _load() async {
    final client = ref.read(apiClientProvider);
    try {
      final d =
          await client.getJson('/guide/groups/${widget.groupId}') as Map<String, dynamic>;
      setState(() => _detail = d);
    } catch (e) {
      setState(() => _msg = e.toString());
    }
  }

  Future<void> _startTrip() async {
    final otp = _otp.text.trim();
    if (otp.length < 4) {
      setState(() => _msg = 'Enter a valid trip OTP from the traveler leader.');
      return;
    }
    final client = ref.read(apiClientProvider);
    try {
      await client.postJson('/guide/groups/${widget.groupId}/trip/start', {
        'otp': otp,
      });
      setState(() => _msg = 'Trip started');
      await _load();
    } catch (e) {
      setState(() => _msg = e.toString());
    }
  }

  Future<void> _announce() async {
    final msg = _announcement.text.trim();
    if (msg.isEmpty) {
      setState(() => _msg = 'Announcement message cannot be empty.');
      return;
    }
    final client = ref.read(apiClientProvider);
    try {
      await client.postJson('/guide/groups/${widget.groupId}/announce', {
        'message': msg,
      });
      setState(() {
        _announcement.clear();
        _msg = 'Announcement sent to group.';
      });
    } catch (e) {
      setState(() => _msg = e.toString());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _otp.dispose();
    _announcement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Group ${widget.groupId}')),
      body: _detail == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Travelers', style: Theme.of(context).textTheme.titleMedium),
                ...((_detail!['travelers'] as List<dynamic>? ?? []).map((t) {
                  final m = t as Map<String, dynamic>;
                  return ListTile(
                    dense: true,
                    title: Text(m['name']?.toString() ?? ''),
                    subtitle: Text(m['is_leader'] == true ? 'Leader' : 'Member'),
                  );
                })),
                const Divider(),
                TextField(
                  controller: _otp,
                  decoration: const InputDecoration(
                    labelText: 'Trip start OTP (from leader)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: _startTrip, child: const Text('Start trip')),
                const SizedBox(height: 16),
                TextField(
                  controller: _announcement,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Broadcast update to travelers',
                    hintText: 'Example: Meet at Gate 2 in 10 minutes.',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _announce,
                  child: const Text('Send announcement'),
                ),
                const SizedBox(height: 24),
                Text('Mark stop complete', style: Theme.of(context).textTheme.titleMedium),
                const Text(
                  'Paste theme_itinerary UUID from API /themes/:slug/itinerary',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                _StopCompleter(groupId: widget.groupId),
                if (_msg != null) Text(_msg!),
              ],
            ),
    );
  }
}

class _StopCompleter extends ConsumerStatefulWidget {
  const _StopCompleter({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_StopCompleter> createState() => _StopCompleterState();
}

class _StopCompleterState extends ConsumerState<_StopCompleter> {
  final _sid = TextEditingController();
  String? _note;
  final _uuidLike = RegExp(
    r'^[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}$',
  );

  @override
  void dispose() {
    _sid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _sid,
          decoration: const InputDecoration(labelText: 'Stop (itinerary) id'),
        ),
        FilledButton.tonal(
          onPressed: () async {
            final sid = _sid.text.trim();
            if (!_uuidLike.hasMatch(sid)) {
              setState(() => _note = 'Enter a valid itinerary UUID.');
              return;
            }
            final client = ref.read(apiClientProvider);
            try {
              await client.postJson(
                '/guide/groups/${widget.groupId}/stops/$sid/complete',
                {'notes': 'completed from app'},
              );
              setState(() => _note = 'Marked complete');
            } catch (e) {
              setState(() => _note = e.toString());
            }
          },
          child: const Text('Complete stop'),
        ),
        if (_note != null) Text(_note!),
      ],
    );
  }
}
