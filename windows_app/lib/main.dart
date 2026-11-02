import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/watch_room_screen.dart';
import 'state/watch_party_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(960, 640));
  unawaited(
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 800),
        center: true,
        minimumSize: Size(960, 640),
        title: "Let's Cook",
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    ),
  );
  runApp(const LetsCookApp());
}

class LetsCookApp extends StatefulWidget {
  const LetsCookApp({super.key});

  @override
  State<LetsCookApp> createState() => _LetsCookAppState();
}

class _LetsCookAppState extends State<LetsCookApp> with WidgetsBindingObserver {
  late final WatchPartyController controller;
  final navigatorKey = GlobalKey<NavigatorState>();
  bool _openingNotificationChat = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = WatchPartyController();
    controller.addListener(_openPendingNotificationChat);
    controller.initialize();
  }

  void _openPendingNotificationChat() {
    if (_openingNotificationChat ||
        controller.pendingDirectMessageSenderId == null) {
      return;
    }
    _openingNotificationChat = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final senderId = controller.takePendingDirectMessageSenderId();
      try {
        if (senderId == null || !controller.authenticated) return;
        final friends = await controller.api.friends();
        final friend = friends
            .where((item) => item['id'] == senderId)
            .firstOrNull;
        final navigator = navigatorKey.currentState;
        if (friend != null && navigator != null) {
          await navigator.push<void>(directChatRoute(controller, friend));
        }
      } finally {
        _openingNotificationChat = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.resumeConnections());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_openPendingNotificationChat);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: "Let's Cook",
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.initializing) return const _LaunchScreen();
        if (!controller.authenticated) {
          return LoginScreen(controller: controller);
        }
        if (controller.activeRoom != null) {
          return WatchRoomScreen(controller: controller);
        }
        return HomeScreen(controller: controller);
      },
    ),
  );
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LogoMark(size: 72),
          SizedBox(height: 18),
          Text(
            "LET'S COOK",
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
          ),
          SizedBox(height: 22),
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    ),
  );
}

class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .3),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.lime, AppColors.mint],
      ),
      boxShadow: const [
        BoxShadow(color: Color(0x507EE852), blurRadius: 28, spreadRadius: 1),
      ],
    ),
    child: Icon(
      Icons.connected_tv_rounded,
      size: size * .58,
      color: AppColors.ink,
    ),
  );
}
