import 'package:brijyatra_mobile/core/mvp/mvp_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MVP flow has role coverage and endpoint mapping', () {
    final roles = mvpFlowSteps.map((s) => s.role).toSet();
    expect(roles.contains('traveler'), isTrue);
    expect(roles.contains('guide'), isTrue);
    expect(roles.contains('admin'), isTrue);

    for (final step in mvpFlowSteps) {
      expect(step.route.isNotEmpty, isTrue);
      expect(step.endpoints.isNotEmpty, isTrue);
    }
  });
}
