class MvpFlowStep {
  const MvpFlowStep({
    required this.role,
    required this.screen,
    required this.route,
    required this.endpoints,
  });

  final String role;
  final String screen;
  final String route;
  final List<String> endpoints;
}

const mvpFlowSteps = <MvpFlowStep>[
  MvpFlowStep(
    role: 'traveler',
    screen: 'Theme list',
    route: '/themes',
    endpoints: ['/themes'],
  ),
  MvpFlowStep(
    role: 'traveler',
    screen: 'Booking wizard',
    route: '/themes/:slug/book',
    endpoints: ['/themes/:slug', '/bookings', '/bookings/:id/pay'],
  ),
  MvpFlowStep(
    role: 'traveler',
    screen: 'Booking history',
    route: '/bookings',
    endpoints: ['/bookings/mine'],
  ),
  MvpFlowStep(
    role: 'guide',
    screen: 'Guide home',
    route: '/g/home',
    endpoints: ['/guide/groups'],
  ),
  MvpFlowStep(
    role: 'guide',
    screen: 'Guide group operations',
    route: '/g/groups/:groupId',
    endpoints: [
      '/guide/groups/:id',
      '/guide/groups/:id/trip/start',
      '/guide/groups/:gid/stops/:sid/complete',
      '/guide/groups/:id/announce',
    ],
  ),
  MvpFlowStep(
    role: 'admin',
    screen: 'Admin dashboard',
    route: '/admin',
    endpoints: ['/admin/analytics/summary', '/admin/bookings', '/admin/incidents'],
  ),
];
