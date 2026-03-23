import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/app_tokens.dart';
import '../../core/mvp/mvp_flow.dart';
import '../../core/providers/session_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isGuide = session.isGuide;
    final isAdmin = session.isAdmin;
    final role = isAdmin ? 'admin' : (isGuide ? 'guide' : 'traveler');
    final stepsCount = mvpFlowSteps.where((s) => s.role == role).length;
    return Scaffold(
      appBar: AppBar(title: const Text('BrijYatra')),
      body: ListView(
        padding: const EdgeInsets.all(BrijTokens.spacing),
        children: [
          Text('MVP flow ready: $stepsCount screens for $role role'),
          const SizedBox(height: 12),
          if (!isGuide && !isAdmin) ...[
            Text('Traveler', style: Theme.of(context).textTheme.titleLarge),
            _tile(context, 'Explore themes', '/themes', Icons.explore_outlined),
            _tile(context, 'Booking history', '/bookings', Icons.history),
            _tile(context, 'Profile', '/profile', Icons.person_outline),
            _tile(context, 'Support center', '/support', Icons.support_agent),
          ],
          if (isGuide) ...[
            Text('Guide', style: Theme.of(context).textTheme.titleLarge),
            _tile(context, 'Assigned groups', '/g/home', Icons.groups_2_outlined),
            _tile(context, 'Support center', '/support', Icons.support_agent),
          ],
          if (isAdmin) ...[
            Text('Admin', style: Theme.of(context).textTheme.titleLarge),
            _tile(context, 'Operations dashboard', '/admin', Icons.admin_panel_settings_outlined),
            _tile(context, 'Guide operations', '/g/home', Icons.badge_outlined),
          ],
          const Divider(height: 32),
          _tile(context, 'Settings', '/settings', Icons.settings_outlined),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    String title,
    String path,
    IconData icon,
  ) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(path),
      ),
    );
  }
}
