import 'package:flutter/material.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Support center placeholder — wire chat/helpdesk when Phase 4 chat lands.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
