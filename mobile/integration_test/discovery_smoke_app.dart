import 'package:flutter/material.dart';

import 'package:lets_cook_mobile/screens/media_discovery_screen.dart';
import 'package:lets_cook_mobile/state/watch_party_controller.dart';
import 'package:lets_cook_mobile/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DiscoverySmokeApp());
}

class DiscoverySmokeApp extends StatefulWidget {
  const DiscoverySmokeApp({super.key});

  @override
  State<DiscoverySmokeApp> createState() => _DiscoverySmokeAppState();
}

class _DiscoverySmokeAppState extends State<DiscoverySmokeApp> {
  late final WatchPartyController controller = WatchPartyController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: MediaDiscoveryScreen(controller: controller),
  );
}
