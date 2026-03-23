import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/app_tokens.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BrijYatra')),
      body: ListView(
        padding: const EdgeInsets.all(BrijTokens.spacing),
        children: [
          Text('Discovery', style: Theme.of(context).textTheme.titleLarge),
          _tile(context, 'Explore themes', '/themes', Icons.explore_outlined),
          _tile(context, 'Booking history', '/bookings', Icons.history),
          _tile(context, 'Profile', '/profile', Icons.person_outline),
          _tile(context, 'Settings', '/settings', Icons.settings_outlined),
          _tile(context, 'Support center', '/support', Icons.support_agent),
          _tile(context, 'Donations / offerings', '/donations', Icons.volunteer_activism_outlined),
          const Divider(height: 32),
          Text('Live yatra', style: Theme.of(context).textTheme.titleLarge),
          _tile(
            context,
            'Group dashboard (enter ID from pay response)',
            '/groups/00000000-0000-0000-0000-000000000000',
            Icons.groups_2_outlined,
          ),
          const Divider(height: 32),
          Text('Ops', style: Theme.of(context).textTheme.titleLarge),
          _tile(context, 'Admin tools', '/admin', Icons.admin_panel_settings_outlined),
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
