import 'package:brijyatra_mobile/app.dart';
import 'package:brijyatra_mobile/core/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('BrijYatraApp loads', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const BrijYatraApp(),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Brij'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  });
}
