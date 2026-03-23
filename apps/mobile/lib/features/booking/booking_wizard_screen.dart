import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';

class BookingWizardScreen extends ConsumerStatefulWidget {
  const BookingWizardScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<BookingWizardScreen> createState() => _BookingWizardScreenState();
}

class _BookingWizardScreenState extends ConsumerState<BookingWizardScreen> {
  int _step = 0;
  DateTimeRange? _dates;
  final Map<String, TextEditingController> _metaCtrls = {};
  final Map<String, TextEditingController> _needsCtrls = {};
  Map<String, dynamic>? _theme;
  List<String> _metaKeys = [];
  List<String> _needsKeys = [];
  String? _bookingId;
  String? _groupId;
  String? _otp;
  String? _error;

  @override
  void dispose() {
    for (final c in _metaCtrls.values) {
      c.dispose();
    }
    for (final c in _needsCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final client = ref.read(apiClientProvider);
    final t = await client.getJson('/themes/${widget.slug}') as Map<String, dynamic>;
    final config = t['config_json'] as Map<String, dynamic>? ?? {};
    final schema = config['booking_field_schema'] as Map<String, dynamic>? ?? {};
    final mk = (schema['required_metadata_keys'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final nk = (schema['required_needs_keys'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    setState(() {
      _theme = t;
      _metaKeys = mk;
      _needsKeys = nk;
      for (final k in mk) {
        _metaCtrls.putIfAbsent(k, TextEditingController.new);
      }
      for (final k in nk) {
        _needsCtrls.putIfAbsent(k, TextEditingController.new);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTheme());
  }

  Future<void> _createBooking() async {
    setState(() => _error = null);
    final client = ref.read(apiClientProvider);
    if (_dates == null) {
      setState(() => _error = 'Pick dates');
      return;
    }
    final meta = <String, dynamic>{};
    for (final k in _metaKeys) {
      final v = _metaCtrls[k]!.text.trim();
      if (v.isEmpty) {
        setState(() => _error = 'Please fill required field: $k');
        return;
      }
      meta[k] = v;
    }
    final needs = <String, dynamic>{};
    for (final k in _needsKeys) {
      final v = _needsCtrls[k]!.text.trim();
      if (v.isEmpty) {
        setState(() => _error = 'Please fill required preference: $k');
        return;
      }
      needs[k] = v;
    }
    final fmt = DateFormat('yyyy-MM-dd');
    try {
      final res = await client.postJson('/bookings', {
        'theme_slug': widget.slug,
        'date_start': fmt.format(_dates!.start),
        'date_end': fmt.format(_dates!.end),
        'booking_metadata_json': meta,
        'needs_json': needs,
        'traveler_ids': <String>[],
      }) as Map<String, dynamic>;
      setState(() {
        _bookingId = res['id'].toString();
        _step = 3;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pay() async {
    if (_bookingId == null) return;
    setState(() => _error = null);
    final client = ref.read(apiClientProvider);
    try {
      final res = await client.postJson('/bookings/$_bookingId/pay', {
        'idempotency_key': 'mvp-${DateTime.now().millisecondsSinceEpoch}',
      }) as Map<String, dynamic>;
      setState(() {
        _groupId = res['group_id']?.toString();
        _otp = res['trip_start_otp']?.toString();
        _step = 4;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_theme == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Book · ${widget.slug}')),
      body: Stepper(
        currentStep: _step,
        onStepContinue: () {
          if (_step == 0) {
            if (_dates != null) setState(() => _step = 1);
          } else if (_step == 1) {
            setState(() => _step = 2);
          } else if (_step == 2) {
            _createBooking();
          } else if (_step == 3) {
            _pay();
          }
        },
        onStepCancel: () {
          if (_step > 0) setState(() => _step -= 1);
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                if (_step < 4)
                  FilledButton(
                    onPressed: details.onStepContinue,
                    child: Text(_step == 2
                        ? 'Save draft'
                        : _step == 3
                            ? 'Pay (stub)'
                            : 'Continue'),
                  ),
                const SizedBox(width: 12),
                if (_step > 0 && _step < 4)
                  TextButton(onPressed: details.onStepCancel, child: const Text('Back')),
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('Dates & group'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _dates = picked);
                  },
                  child: Text(_dates == null
                      ? 'Select travel dates'
                      : '${DateFormat('yyyy-MM-dd').format(_dates!.start)} -> ${DateFormat('yyyy-MM-dd').format(_dates!.end)}'),
                ),
              ],
            ),
            isActive: _step >= 0,
          ),
          Step(
            title: const Text('Details'),
            content: Column(
              children: _metaKeys
                  .map(
                    (k) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _metaCtrls[k],
                        decoration: InputDecoration(labelText: k),
                      ),
                    ),
                  )
                  .toList(),
            ),
            isActive: _step >= 1,
          ),
          Step(
            title: const Text('Needs & preferences'),
            content: Column(
              children: _needsKeys
                  .map(
                    (k) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _needsCtrls[k],
                        decoration: InputDecoration(labelText: k),
                      ),
                    ),
                  )
                  .toList(),
            ),
            isActive: _step >= 2,
          ),
          Step(
            title: const Text('Review & pay'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Booking id: ${_bookingId ?? "—"}'),
                if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
            isActive: _step >= 3,
          ),
          Step(
            title: const Text('Confirmed'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Group id:\n$_groupId'),
                const SizedBox(height: 8),
                Text('Trip start OTP (share with guide at pickup):\n$_otp'),
                const SizedBox(height: 16),
                Text(
                  'Next: assign a guide via Admin API, then open Guide home.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            isActive: _step >= 4,
          ),
        ],
      ),
      bottomNavigationBar: _error == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
    );
  }
}
