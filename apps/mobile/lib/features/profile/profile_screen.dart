import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_flags.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/session_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String? _deviceMsg;

  Future<void> _registerDeviceToken() async {
    if (kIsWeb && AppFlags.useFirebaseAuth) {
      setState(() => _deviceMsg =
          'Push tokens on web need extra FCM web setup (VAPID / service worker). Use the mobile app for now.');
      return;
    }
    final client = ref.read(apiClientProvider);
    try {
      if (AppFlags.useFirebaseAuth) {
        await FirebaseMessaging.instance.requestPermission();
        final token = await FirebaseMessaging.instance.getToken();
        if (token == null || token.isEmpty) {
          setState(() => _deviceMsg = 'No FCM token (check Firebase / platform).');
          return;
        }
        await client.postJson('/users/me/device-token', {
          'token': token,
          'platform': defaultTargetPlatform.name,
        });
        setState(() => _deviceMsg = 'FCM token registered.');
      } else {
        await client.postJson('/users/me/device-token', {
          'token': 'stub-fcm-${DateTime.now().millisecondsSinceEpoch}',
          'platform': 'flutter_test',
        });
        setState(() => _deviceMsg = 'Device token registered (stub).');
      }
    } catch (e) {
      setState(() => _deviceMsg = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          ListTile(title: const Text('User id'), subtitle: Text(s.userId ?? '—')),
          ListTile(title: const Text('Role'), subtitle: Text(s.role ?? '—')),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(AppFlags.useFirebaseAuth ? 'Register FCM token' : 'Register FCM token (stub)'),
            subtitle: Text(_deviceMsg ?? 'POST /users/me/device-token'),
            onTap: _registerDeviceToken,
          ),
          ListTile(
            title: const Text('Sign out'),
            onTap: () async {
              await ref.read(sessionProvider.notifier).signOut();
              if (context.mounted) context.go('/auth');
            },
          ),
        ],
      ),
    );
  }
}
