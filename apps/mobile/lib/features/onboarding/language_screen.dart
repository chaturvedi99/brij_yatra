import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('English'),
            trailing: const Icon(Icons.check),
            onTap: () => context.go('/onboarding'),
          ),
          ListTile(
            title: const Text('हिन्दी'),
            onTap: () => context.go('/onboarding'),
          ),
        ],
      ),
    );
  }
}
