import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_flags.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/session_provider.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _name = TextEditingController(text: 'Yatri');
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'traveler';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _bootstrapFirebase() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    final password = _password.text;
    try {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          await cred.user?.updateDisplayName(_name.text.trim());
        } else {
          rethrow;
        }
      }

      final client = ref.read(apiClientProvider);
      final body = <String, dynamic>{'name': _name.text.trim()};
      if (_role != 'traveler') {
        body['role'] = _role;
      }
      final res = await client.postJson('/auth/bootstrap', body) as Map<String, dynamic>;
      final jwt = await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
      final userId = res['user_id'].toString();
      final role = res['role'] as String? ?? 'traveler';
      await ref.read(sessionProvider.notifier).setSession(
            token: jwt,
            userId: userId,
            role: role,
          );
      if (!mounted) return;
      context.go(role == 'guide' ? '/g/home' : '/home');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bootstrapDev() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = ApiClient(getToken: () async => null);
      final body = <String, dynamic>{'name': _name.text};
      if (_role != 'traveler') {
        body['role'] = _role;
      }
      final res = await client.postJson('/auth/bootstrap', body) as Map<String, dynamic>;
      final token = res['token'] as String;
      final userId = res['user_id'].toString();
      final role = res['role'] as String? ?? 'traveler';
      await ref.read(sessionProvider.notifier).setSession(
            token: token,
            userId: userId,
            role: role,
          );
      if (!mounted) return;
      context.go(role == 'guide' ? '/g/home' : '/home');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebase = AppFlags.useFirebaseAuth;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              firebase ? 'Firebase + API' : 'Dev sign-in',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              firebase
                  ? 'Email/password via Firebase; then POST /auth/bootstrap with your ID token. Run flutterfire configure and release with --dart-define=USE_FIREBASE_AUTH=true.'
                  : 'Uses POST /auth/bootstrap (set DEV_BYPASS_AUTH=1 on API).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (firebase) ...[
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'traveler', child: Text('Traveler')),
                DropdownMenuItem(value: 'guide', child: Text('Guide')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'traveler'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : (firebase ? _bootstrapFirebase : _bootstrapDev),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(firebase ? 'Sign in / register' : 'Create session'),
            ),
          ],
        ),
      ),
    );
  }
}
