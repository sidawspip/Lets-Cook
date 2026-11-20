import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lets_cook_windows/screens/login_screen.dart';
import 'package:lets_cook_windows/screens/watch_room_screen.dart';
import 'package:lets_cook_windows/state/watch_party_controller.dart';
import 'package:lets_cook_windows/theme/app_theme.dart';

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

  testWidgets('room video-setting radio choices react to clicks', (
    tester,
  ) async {
    final controller = _RoomControlsTestController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: RoomControlsSheet(controller: controller)),
      ),
    );

    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>).first)
          .groupValue,
      'HOSTS_ONLY',
    );

    await tester.tap(find.text('Selected people'));
    await tester.pump();

    expect(controller.queueMode, 'PERMISSION');
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>).first)
          .groupValue,
      'PERMISSION',
    );
  });
}

class _RoomControlsTestController extends WatchPartyController {
  @override
  bool get canControlWatch => true;

  @override
  Future<void> setRoomQueueMode(String mode) async {
    queueMode = mode;
    notifyListeners();
  }

  @override
  Future<void> setRoomAudience(String visibility) async {}
}
