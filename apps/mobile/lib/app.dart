import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design_system/brij_theme_data.dart';
import 'core/routing/app_router.dart';

class BrijYatraApp extends ConsumerWidget {
  const BrijYatraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'BrijYatra',
      theme: buildBrijTheme(),
      routerConfig: router,
    );
  }
}
