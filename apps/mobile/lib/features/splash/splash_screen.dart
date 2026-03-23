import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/app_tokens.dart';
import '../../core/providers/session_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      final s = ref.read(sessionProvider);
      if (s.isLoggedIn) {
        context.go(s.isGuide ? '/g/home' : '/home');
      } else {
        context.go('/language');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BrijTokens.peacock, BrijTokens.sandalwood],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.temple_hindu_outlined,
                size: 72,
                color: Colors.white.withValues(alpha: 0.95),
              ),
              const SizedBox(height: 16),
              Text(
                'BrijYatra',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sacred journeys, mindfully guided',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
