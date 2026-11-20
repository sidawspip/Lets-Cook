import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lets_cook_mobile/screens/login_screen.dart';
import 'package:lets_cook_mobile/state/watch_party_controller.dart';
import 'package:lets_cook_mobile/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login screen offers local and social account access', (
    tester,
  ) async {
    final controller = WatchPartyController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: LoginScreen(controller: controller),
      ),
    );

    expect(find.text('Watch together.\nStay connected.'), findsOneWidget);
    expect(find.text('Enter Xynk'), findsOneWidget);

    final loginList = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Create an account'),
      250,
      scrollable: loginList,
    );
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with X'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Preview the mobile experience'), findsNothing);
    controller.dispose();
  });
}
