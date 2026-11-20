import 'package:flutter/material.dart';

Future<bool> confirmScreenShare(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Share your screen?'),
          content: const Text(
            'Everyone in this room can see what you share until you stop. '
            'On the next Android prompt, choose "Share entire screen" to show '
            'other apps too. "Share one app" only shows the app you select.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Share screen'),
            ),
          ],
        ),
      ) ??
      false;
}
