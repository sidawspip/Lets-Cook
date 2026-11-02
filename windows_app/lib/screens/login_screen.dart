import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../main.dart';
import '../state/watch_party_controller.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final WatchPartyController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: _LoginBackdrop()),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SizedBox(
                width: constraints.maxWidth >= 720 ? 560 : constraints.maxWidth,
                height: constraints.maxHeight,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    constraints.maxWidth >= 1440 ? 64 : 36,
                    24,
                    24,
                  ),
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: LogoMark(size: 62),
                    ),
                    const SizedBox(height: 42),
                    Text(
                      'Watch together.\nStay connected.',
                      style: Theme.of(
                        context,
                      ).textTheme.displaySmall?.copyWith(fontSize: 46),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Watch, talk, and build the queue together—without leaving the room.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 16,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 42),
                    TextField(
                      controller: username,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: obscure,
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (widget.controller.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.controller.error!,
                        style: const TextStyle(color: AppColors.coral),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: widget.controller.busy ? null : _login,
                      child: widget.controller.busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.ink,
                              ),
                            )
                          : const Text("Enter Let's Cook"),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: widget.controller.busy
                          ? null
                          : () => widget.controller.loginWithIdentityProvider(
                              'google',
                            ),
                      icon: const FaIcon(FontAwesomeIcons.google, size: 19),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: widget.controller.busy
                          ? null
                          : () => widget.controller.loginWithIdentityProvider(
                              'x',
                            ),
                      icon: const FaIcon(FontAwesomeIcons.xTwitter, size: 19),
                      label: const Text('Continue with X'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _register,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Create an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void _login() {
    if (username.text.trim().isEmpty || password.text.isEmpty) return;
    widget.controller.login(username.text, password.text);
  }

  Future<void> _register() async {
    final opened = await launchUrl(
      AppConfig.registrationUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open account registration.')),
      );
    }
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(1.15, -.8),
        radius: 1.3,
        colors: [Color(0x665D2C87), Color(0xFF081C31), AppColors.ink],
      ),
    ),
    child: CustomPaint(painter: _DotPainter()),
  );
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .045);
    for (double y = 16; y < size.height; y += 28) {
      for (double x = 14; x < size.width; x += 28) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
