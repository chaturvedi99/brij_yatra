import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Your yatra begins with intention',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Explore themed journeys, gather your group, and walk Brij with a trusted local guide.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go('/auth'),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
