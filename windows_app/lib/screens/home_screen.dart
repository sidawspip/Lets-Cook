import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../core/app_config.dart';
import '../models/models.dart';
import '../state/watch_party_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/media_preview.dart';
import 'media_discovery_screen.dart';
import 'user_profile_screen.dart';

Route<void> directChatRoute(
  WatchPartyController controller,
  Map<String, dynamic> friend,
) => MaterialPageRoute<void>(
  builder: (_) => _DirectChatScreen(controller: controller, friend: friend),
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final WatchPartyController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: Stack(
      children: [
        const Positioned.fill(child: _HomeBackdrop()),
        SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SizedBox(
                width: math.min(constraints.maxWidth, 1180),
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    _Header(
                      onSettings: _showProfilePrivacy,
                      onFriends: _openFriends,
                    ),
                    _SearchBar(onSubmitted: (query) => _openDiscovery(query)),
                    Expanded(
                      child: _RoomsPane(
                        key: const ValueKey('rooms'),
                        controller: widget.controller,
                      ),
                    ),
                    const SizedBox(height: 82),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: math.max(
            22,
            (MediaQuery.sizeOf(context).width - 1180) / 2 + 22,
          ),
          bottom: 22,
          child: FloatingActionButton(
            heroTag: 'start-party',
            onPressed: widget.controller.busy ? null : _showSources,
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF78C8),
                    Color(0xFF9B6CFF),
                    Color(0xFF45D8FF),
                  ],
                ),
                border: Border.all(color: const Color(0x99FFFFFF), width: 1.3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x779E62FF),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded, size: 32),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _showSources() async {
    await _openDiscovery('');
  }

  Future<void> _showProfilePrivacy() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF171224),
      builder: (sheetContext) => _ProfilePrivacySheet(
        controller: widget.controller,
        onOpenProfile: () {
          Navigator.pop(sheetContext);
          final currentUser = widget.controller.profile;
          if (currentUser == null) return;
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => UserProfileScreen(
                controller: widget.controller,
                userId: currentUser.id,
                summary: {
                  'id': currentUser.id,
                  'username': currentUser.username,
                  'displayName': currentUser.displayName,
                  'bio': currentUser.bio,
                  'avatarUrl': currentUser.avatarUrl,
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openFriends() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _FriendsScreen(controller: widget.controller),
    ),
  );

  Future<void> _openDiscovery(String query) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MediaDiscoveryScreen(
          controller: widget.controller,
          initialQuery: query,
        ),
      ),
    );
  }
}

class _HomeBackdrop extends StatelessWidget {
  const _HomeBackdrop();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF31204B),
              Color(0xFF4B315D),
              Color(0xFF25465C),
              Color(0xFF101D2B),
            ],
            stops: [0, .34, .68, 1],
          ),
        ),
      ),
      const Positioned(
        top: -90,
        right: -90,
        child: _Glow(color: Color(0x66E33F9E), size: 300),
      ),
      const Positioned(
        bottom: 70,
        left: -100,
        child: _Glow(color: Color(0x661AA8D6), size: 340),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x12000000), Color(0xB3050910)],
          ),
        ),
      ),
    ],
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings, required this.onFriends});
  final VoidCallback onSettings;
  final VoidCallback onFriends;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
    child: Row(
      children: [
        _HeaderButton(
          onPressed: onSettings,
          icon: Icons.blur_on_rounded,
          label: 'Settings',
          colors: const [Color(0xFFFF75BD), Color(0xFF9D6CFF)],
        ),
        const Expanded(
          child: Text(
            "LET'S COOK",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'sans-serif-condensed',
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
        ),
        _HeaderButton(
          onPressed: onFriends,
          label: 'Friends',
          icon: Icons.group_rounded,
          colors: const [Color(0xFF8D75FF), Color(0xFF42D7FF)],
        ),
      ],
    ),
  );
}

class _HeaderButton extends StatefulWidget {
  const _HeaderButton({
    required this.onPressed,
    required this.label,
    required this.icon,
    required this.colors,
  });

  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final List<Color> colors;

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label == 'Friends' ? 'Open friends' : 'Open settings',
    child: AnimatedScale(
      scale: pressed ? .96 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 110),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: widget.onPressed,
          onHighlightChanged: (value) => setState(() => pressed = value),
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pressed ? const Color(0x24FFFFFF) : Colors.transparent,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: widget.colors,
                  ).createShader(bounds),
                  child: Icon(widget.icon, color: Colors.white, size: 25),
                ),
                const Positioned(
                  right: 5,
                  top: 5,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xBFFFFFFF),
                    size: 7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProfilePrivacySheet extends StatelessWidget {
  const _ProfilePrivacySheet({
    required this.controller,
    required this.onOpenProfile,
  });
  final WatchPartyController controller;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Settings',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Privacy, playback and social preferences.',
                              style: TextStyle(color: Color(0xBFFFFFFF)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: controller.savingProfilePreferences.isEmpty
                        ? const SizedBox.shrink()
                        : const Padding(
                            key: ValueKey('settings-saving-banner'),
                            padding: EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(minHeight: 3),
                                SizedBox(height: 6),
                                Text(
                                  'Saving settings…',
                                  style: TextStyle(
                                    color: Color(0xFFE9C8FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  const _SettingsLabel('ACCOUNT'),
                  ListTile(
                    onTap: onOpenProfile,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0x44FFFFFF),
                      child: Text(
                        controller.displayName.characters.first.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    title: Text(
                      controller.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '@${controller.profile?.username ?? 'member'} · Signed in',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                  _CompactSwitch(
                    key: const ValueKey('setting-hide-sensitive-content'),
                    label: 'Hide sensitive content',
                    icon: Icons.visibility_off_outlined,
                    value: controller.hideSensitiveContent,
                    saving: controller.savingProfilePreferences.contains(
                      'hideSensitiveContent',
                    ),
                    onChanged: controller.setHideSensitiveContent,
                  ),
                  const _SettingsLabel('EXPERIENCE'),
                  _CompactSwitch(
                    key: const ValueKey('setting-floating-video'),
                    label: 'Floating video',
                    icon: Icons.picture_in_picture_alt_outlined,
                    value: controller.floatingVideo,
                    saving: controller.savingProfilePreferences.contains(
                      'floatingVideo',
                    ),
                    onChanged: (v) =>
                        controller.setProfilePreference('floatingVideo', v),
                  ),
                  _CompactSwitch(
                    key: const ValueKey('setting-mute-other-audio'),
                    label: 'Mute other audio',
                    icon: Icons.volume_off_outlined,
                    value: controller.muteOtherAudio,
                    saving: controller.savingProfilePreferences.contains(
                      'muteOtherAudio',
                    ),
                    onChanged: (v) =>
                        controller.setProfilePreference('muteOtherAudio', v),
                  ),
                  _CompactSwitch(
                    key: const ValueKey('setting-haptic-feedback'),
                    label: 'Haptic feedback',
                    icon: Icons.vibration_rounded,
                    value: controller.hapticFeedback,
                    saving: controller.savingProfilePreferences.contains(
                      'hapticFeedback',
                    ),
                    onChanged: (v) =>
                        controller.setProfilePreference('hapticFeedback', v),
                  ),
                  _CompactSwitch(
                    key: const ValueKey('setting-auto-translation'),
                    label: 'Automatic translation',
                    icon: Icons.translate_rounded,
                    value: controller.autoTranslate,
                    saving: controller.savingProfilePreferences.contains(
                      'autoTranslate',
                    ),
                    onChanged: (v) =>
                        controller.setProfilePreference('autoTranslate', v),
                  ),
                  _CompactSwitch(
                    key: const ValueKey('setting-hide-location'),
                    label: 'Hide location',
                    icon: Icons.location_off_outlined,
                    value: controller.hideLocation,
                    saving: controller.savingProfilePreferences.contains(
                      'hideLocation',
                    ),
                    onChanged: (v) =>
                        controller.setProfilePreference('hideLocation', v),
                  ),
                  _CompactSwitch(
                    key: const ValueKey('setting-restrict-invites'),
                    label: 'Friends-only invitations',
                    icon: Icons.person_add_disabled_outlined,
                    value: controller.restrictInvites,
                    saving: controller.savingProfilePreferences.contains(
                      'restrictInvites',
                    ),
                    onChanged: (v) =>
                        controller.setProfilePreference('restrictInvites', v),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    dense: true,
                    leading: const Icon(
                      Icons.language_rounded,
                      color: Color(0xFFDBC4F5),
                    ),
                    title: const Text(
                      'Language',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: DropdownButton<String>(
                      value: controller.preferredLanguage,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                        DropdownMenuItem(value: 'es', child: Text('Spanish')),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        controller.preferredLanguage = value;
                        await controller.saveProfilePreferences();
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    dense: true,
                    leading: const Icon(
                      Icons.add_reaction_outlined,
                      color: Color(0xFFDBC4F5),
                    ),
                    title: const Text(
                      'Quick reaction',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: PopupMenuButton<String>(
                      initialValue: controller.quickReaction,
                      onSelected: (value) async {
                        controller.quickReaction = value;
                        await controller.saveProfilePreferences();
                      },
                      itemBuilder: (_) => const ['❤️', '🔥', '😂', '👏', '😮']
                          .map(
                            (reaction) => PopupMenuItem(
                              value: reaction,
                              child: Text(
                                reaction,
                                style: TextStyle(fontSize: 22),
                              ),
                            ),
                          )
                          .toList(),
                      child: Text(
                        controller.quickReaction,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _SettingsLabel('SUPPORT & APP'),
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 2),
                    leading: Icon(Icons.workspace_premium_outlined),
                    title: Text('Premium'),
                    subtitle: Text(
                      'Plan controls will appear here when enabled',
                    ),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 2),
                    leading: Icon(Icons.help_outline_rounded),
                    title: Text('Help and feedback'),
                    subtitle: Text('Help centre and diagnostics'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 2),
                    leading: Icon(Icons.code_rounded),
                    title: Text('Developer information'),
                    subtitle: Text('Build and service information'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await controller.logout();
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Log out'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: const Color(0xFFFFB9C3),
                      side: const BorderSide(color: Color(0x66FF8798)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CompactSwitch extends StatefulWidget {
  const _CompactSwitch({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.saving = false,
  });
  final String label;
  final IconData icon;
  final bool value;
  final Future<void> Function(bool) onChanged;
  final bool saving;

  @override
  State<_CompactSwitch> createState() => _CompactSwitchState();
}

class _CompactSwitchState extends State<_CompactSwitch> {
  bool _saving = false;

  Future<void> _change(bool value) async {
    if (_saving || widget.saving) return;
    setState(() => _saving = true);
    try {
      await widget.onChanged(value);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = _saving || widget.saving;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: saving ? const Color(0x1FDDA7F7) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: saving ? const Color(0xFFDDA7F7) : Colors.transparent,
          width: saving ? 2.5 : 0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            dense: true,
            visualDensity: const VisualDensity(vertical: -1),
            leading: Icon(
              widget.icon,
              size: 21,
              color: const Color(0xFFDDA7F7),
            ),
            title: Text(
              widget.label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            onTap: saving ? null : () => _change(!widget.value),
            trailing: saving
                ? const SizedBox(
                    width: 70,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox.square(
                          dimension: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Color(0xFFF1C6FF),
                          ),
                        ),
                        SizedBox(width: 7),
                        Text(
                          'SAVE',
                          style: TextStyle(
                            color: Color(0xFFF1C6FF),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          ),
                        ),
                      ],
                    ),
                  )
                : Switch.adaptive(value: widget.value, onChanged: _change),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: saving
                ? const ClipRRect(
                    key: ValueKey('saving-border'),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      color: Color(0xFFF1C6FF),
                      backgroundColor: Color(0x335F2A76),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('idle-border')),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onSubmitted});

  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: TextField(
          textInputAction: TextInputAction.search,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: 'Search YouTube or paste a video URL',
            hintStyle: const TextStyle(color: Color(0xBFFFFFFF), fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white),
            filled: true,
            fillColor: const Color(0x2EFFFFFF),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: const BorderSide(color: Color(0x33FFFFFF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: const BorderSide(color: Colors.white70),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RoomsPane extends StatelessWidget {
  const _RoomsPane({super.key, required this.controller});

  final WatchPartyController controller;

  Future<void> _openRoom(BuildContext context, PartyRoom room) async {
    var accessKey = '';
    if (!room.joined && room.accessPolicy.contains('KEY')) {
      final keyController = TextEditingController();
      final submitted = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Join ${room.name}'),
          content: TextField(
            controller: keyController,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
            decoration: const InputDecoration(
              labelText: 'Room key',
              hintText: 'Enter the key shared by the host',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, keyController.text.trim()),
              child: const Text('Join'),
            ),
          ],
        ),
      );
      keyController.dispose();
      if (submitted == null || submitted.isEmpty) return;
      accessKey = submitted;
    }
    await controller.openRoom(room, accessKey: accessKey);
  }

  @override
  Widget build(BuildContext context) {
    final visibleRooms = controller.visibleRooms;
    final invited = visibleRooms.take(2).toList();
    final publicRooms = visibleRooms.skip(2).toList();
    return RefreshIndicator(
      onRefresh: controller.resumeConnections,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 26),
        children: [
          _ConnectionBanner(controller: controller),
          if (!controller.hideSensitiveContent) ...[
            const SizedBox(height: 12),
            _SensitiveContentToggle(controller: controller),
          ],
          const SizedBox(height: 18),
          _SectionTitle(
            icon: Icons.lock_rounded,
            label: 'Invited',
            count: invited.length,
          ),
          const SizedBox(height: 9),
          _RoomGrid(rooms: invited, onOpen: (room) => _openRoom(context, room)),
          const SizedBox(height: 12),
          _SectionTitle(
            icon: Icons.public_rounded,
            label: 'Public',
            count: publicRooms.length,
          ),
          const SizedBox(height: 9),
          if (publicRooms.isEmpty)
            const _EmptyRoomCard()
          else
            _RoomGrid(
              rooms: publicRooms,
              onOpen: (room) => _openRoom(context, room),
            ),
        ],
      ),
    );
  }
}

class _RoomGrid extends StatelessWidget {
  const _RoomGrid({required this.rooms, required this.onOpen});

  final List<PartyRoom> rooms;
  final ValueChanged<PartyRoom> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 820 ? 2 : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rooms.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 108,
        ),
        itemBuilder: (context, index) {
          final room = rooms[index];
          return _RoomCard(room: room, onTap: () => onOpen(room));
        },
      );
    },
  );
}

class _SensitiveContentToggle extends StatelessWidget {
  const _SensitiveContentToggle({required this.controller});
  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) {
    final saving = controller.savingProfilePreferences.contains(
      'hideSensitiveContent',
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
      decoration: BoxDecoration(
        color: const Color(0x22120A1D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x28FFFFFF)),
      ),
      child: Row(
        children: [
          Icon(
            controller.hideSensitiveContent
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: const Color(0xFFE9C8FF),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hide sensitive content',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Hide sensitive rooms and blur them in history',
                  style: TextStyle(color: Color(0xAFFFFFFF), fontSize: 11),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 52,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: saving
                  ? const SizedBox.square(
                      key: ValueKey('saving-sensitive-content'),
                      dimension: 38,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          Icon(
                            Icons.sync_rounded,
                            size: 18,
                            color: Color(0xFFE9C8FF),
                          ),
                        ],
                      ),
                    )
                  : Switch.adaptive(
                      key: const ValueKey('sensitive-content-switch'),
                      value: controller.hideSensitiveContent,
                      onChanged: controller.setHideSensitiveContent,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatefulWidget {
  const _ConnectionBanner({required this.controller});

  final WatchPartyController controller;

  @override
  State<_ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<_ConnectionBanner> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final connected = widget.controller.fullyConnected;
    final reconnecting = widget.controller.reconnecting;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => expanded = !expanded),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          decoration: BoxDecoration(
            color: const Color(0x2EFFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: reconnecting
                          ? Colors.amber
                          : connected
                          ? AppColors.mint
                          : Colors.white38,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      reconnecting ? 'RECONNECTING' : 'STAY CONNECTED',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: .4,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: expanded
                    ? const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Lets Cook keeps your room connected while this window is open. '
                          'If the connection is interrupted, it automatically rejoins and '
                          'syncs the video when you return.',
                          style: TextStyle(
                            color: Color(0xCFFFFFFF),
                            height: 1.35,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: Colors.white),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      const Spacer(),
      Text(
        '$count ${count == 1 ? 'room' : 'rooms'}',
        style: const TextStyle(color: Color(0xBFFFFFFF), fontSize: 11),
      ),
    ],
  );
}

class _RoomCard extends StatefulWidget {
  const _RoomCard({required this.room, required this.onTap});

  final PartyRoom room;
  final VoidCallback onTap;

  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> {
  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final youtubeId =
        room.mediaId != null && RegExp(r'^[\w-]{11}$').hasMatch(room.mediaId!)
        ? room.mediaId
        : null;
    final provider =
        room.mediaProvider ?? (youtubeId != null ? 'YOUTUBE' : 'WEB');
    final sensitive = _looksSensitive(
      '${room.name} ${room.mediaTitle ?? ''} ${room.mediaId ?? ''}',
    );
    final duration = room.durationSeconds ?? 0;
    final progress = duration > 0
        ? (room.positionSeconds / duration).clamp(0.0, 1.0)
        : 0.0;
    return Material(
      color: const Color(0x2E180D37),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: SizedBox(
          height: 108,
          child: Stack(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 142,
                    child: MediaPreview(
                      mediaId: room.mediaId ?? '',
                      provider: provider,
                      thumbnailUrl: room.thumbnailUrl,
                      contentLabel: '${room.name} ${room.mediaTitle ?? ''}',
                      sensitive: sensitive,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.mediaTitle ?? room.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              height: 1.15,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              _AvatarStack(count: room.viewerCount.clamp(1, 4)),
                              const Spacer(),
                              const Icon(
                                Icons.people_alt_rounded,
                                size: 15,
                                color: Color(0xCCFFFFFF),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${room.viewerCount}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  color: const Color(0xFFFF72C7),
                  backgroundColor: const Color(0x26FFFFFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 25,
    width: 76,
    child: Stack(
      children: [
        for (var index = 0; index < count; index++)
          Positioned(
            left: index * 17,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFF1E1631),
              child: const Icon(
                Icons.person_rounded,
                size: 14,
                color: Color(0xFFDCC8F5),
              ),
            ),
          ),
      ],
    ),
  );
}

class _EmptyRoomCard extends StatelessWidget {
  const _EmptyRoomCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0x1FFFFFFF),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Text(
      'No public rooms right now. Start one with the + button.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Color(0xCFFFFFFF)),
    ),
  );
}

// Retained while the settings editor is migrated into the richer public-profile
// surface; the account entry now opens UserProfileScreen above.
// ignore: unused_element
class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen({required this.controller});

  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Text('Profile'),
    ),
    body: Stack(
      children: [
        const Positioned.fill(child: _HomeBackdrop()),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SizedBox(
                width: math.min(constraints.maxWidth, 900),
                height: constraints.maxHeight,
                child: _ProfilePane(controller: controller),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _FriendsScreen extends StatefulWidget {
  const _FriendsScreen({required this.controller});

  final WatchPartyController controller;

  @override
  State<_FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<_FriendsScreen> {
  bool loading = true;
  String? error;
  String query = '';
  List<Map<String, dynamic>> friends = const [];
  List<Map<String, dynamic>> requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => loading = true);
    try {
      final loadedFriends = await widget.controller.api.friends();
      final loadedRequests = await widget.controller.api.friendRequests();
      if (!mounted) return;
      setState(() {
        friends = loadedFriends;
        requests = loadedRequests;
        error = null;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> _decide(String requestId, bool accept) async {
    try {
      await widget.controller.api.decideFriendRequest(requestId, accept);
      await _load();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.toString())));
    }
  }

  Future<void> _openChat(Map<String, dynamic> friend) async {
    await Navigator.of(
      context,
    ).push<void>(directChatRoute(widget.controller, friend));
  }

  Future<void> _openFriendProfile(Map<String, dynamic> friend) async {
    final userId = (friend['id'] ?? friend['userId'])?.toString();
    if (userId == null || userId.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          controller: widget.controller,
          userId: userId,
          summary: friend,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final visibleFriends = normalizedQuery.isEmpty
        ? friends
        : friends.where((friend) {
            final name = (friend['displayName'] ?? '').toString().toLowerCase();
            final handle = (friend['username'] ?? '').toString().toLowerCase();
            return name.contains(normalizedQuery) ||
                handle.contains(normalizedQuery);
          }).toList();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Friends'),
        actions: [
          IconButton(
            tooltip: 'Refresh friends',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _HomeBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: SizedBox(
                  width: math.min(constraints.maxWidth, 1000),
                  height: constraints.maxHeight,
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                      ? _FriendsError(message: error!, onRetry: _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 620,
                                  ),
                                  child: TextField(
                                    onChanged: (value) =>
                                        setState(() => query = value),
                                    decoration: InputDecoration(
                                      hintText: 'Search friends',
                                      prefixIcon: const Icon(
                                        Icons.search_rounded,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0x16FFFFFF),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              if (requests.isNotEmpty) ...[
                                _FriendsSectionHeader(
                                  title: 'Requests',
                                  count: requests.length,
                                ),
                                const SizedBox(height: 8),
                                for (final request in requests)
                                  _FriendRequestTile(
                                    request: request,
                                    onAccept: () =>
                                        _decide(request['id'].toString(), true),
                                    onReject: () => _decide(
                                      request['id'].toString(),
                                      false,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                              ],
                              _FriendsSectionHeader(
                                title: 'Friends',
                                count: visibleFriends.length,
                              ),
                              const SizedBox(height: 14),
                              if (friends.isEmpty)
                                const _EmptyFriends()
                              else if (visibleFriends.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 38),
                                  child: Text(
                                    'No friends match that search.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Color(0xBFFFFFFF)),
                                  ),
                                )
                              else ...[
                                SizedBox(
                                  height: 112,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: visibleFriends.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 15),
                                    itemBuilder: (_, index) => _FriendBubble(
                                      friend: visibleFriends[index],
                                      onTap: () => _openFriendProfile(
                                        visibleFriends[index],
                                      ),
                                    ),
                                  ),
                                ),
                                const Divider(
                                  height: 28,
                                  color: Color(0x22FFFFFF),
                                ),
                                for (final friend in visibleFriends)
                                  _FriendListTile(
                                    friend: friend,
                                    onTap: () => _openFriendProfile(friend),
                                    onChat: () => _openChat(friend),
                                  ),
                              ],
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendBubble extends StatelessWidget {
  const _FriendBubble({required this.friend, required this.onTap});

  final Map<String, dynamic> friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (friend['displayName'] ?? friend['username'] ?? 'Member')
        .toString();
    final avatar = friend['avatarUrl']?.toString();
    final online = friend['online'] == true;
    final togetherSeconds = (friend['watchTogetherSeconds'] as num? ?? 0)
        .toInt();
    return Semantics(
      button: true,
      label: 'Chat with $name',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(38),
        child: SizedBox(
          width: 74,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Color(0xFFFF79C7),
                          Color(0xFF8F72FF),
                          Color(0xFF4BD9FF),
                          Color(0xFFFF79C7),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(color: Color(0x559C6CFF), blurRadius: 16),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF25142F),
                      backgroundImage: avatar == null || avatar.isEmpty
                          ? null
                          : NetworkImage(avatar),
                      child: avatar == null || avatar.isEmpty
                          ? Text(
                              name.characters.first.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: online
                            ? const Color(0xFF5DE2A5)
                            : Colors.white38,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF24132E),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _watchTimeDetailed(togetherSeconds),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendListTile extends StatelessWidget {
  const _FriendListTile({
    required this.friend,
    required this.onTap,
    required this.onChat,
  });

  final Map<String, dynamic> friend;
  final VoidCallback onTap;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final name = (friend['displayName'] ?? friend['username'] ?? 'Member')
        .toString();
    final username = (friend['username'] ?? 'member').toString();
    final avatar = friend['avatarUrl']?.toString();
    final online = friend['online'] == true;
    final togetherSeconds = (friend['watchTogetherSeconds'] as num? ?? 0)
        .toInt();
    return Semantics(
      button: true,
      label: 'Chat with $name',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: const Color(0xFF392442),
                    backgroundImage: avatar == null || avatar.isEmpty
                        ? null
                        : NetworkImage(avatar),
                    child: avatar == null || avatar.isEmpty
                        ? Text(
                            name.characters.first.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          )
                        : null,
                  ),
                  if (online)
                    Positioned(
                      right: 0,
                      bottom: 1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: const Color(0xFF52E09D),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF160C20),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username · ${_watchTimeDetailed(togetherSeconds)} together',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xAFFFFFFF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Message $name',
                onPressed: onChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectChatScreen extends StatefulWidget {
  const _DirectChatScreen({required this.controller, required this.friend});

  final WatchPartyController controller;
  final Map<String, dynamic> friend;

  @override
  State<_DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<_DirectChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();
  List<DirectMessage> _messages = const [];
  Timer? _refreshTimer;
  bool _loading = true;
  bool _refreshing = false;
  bool _sending = false;
  bool _uploading = false;
  bool _showEmojis = false;
  String? _error;

  String get _friendId => widget.friend['id'].toString();
  String get _friendName =>
      (widget.friend['displayName'] ?? widget.friend['username'] ?? 'Friend')
          .toString();
  String get _friendUsername =>
      (widget.friend['username'] ?? 'friend').toString();

  @override
  void initState() {
    super.initState();
    widget.controller.markDirectMessagesRead(_friendId);
    _load(showSpinner: true);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(showSpinner: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool showSpinner}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final messages = await widget.controller.api.directMessages(_friendId);
      if (!mounted) return;
      final changed =
          messages.length != _messages.length ||
          (messages.isNotEmpty &&
              (_messages.isEmpty || messages.last.id != _messages.last.id));
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
      if (changed) _scrollToLatest();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = exception.toString();
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await widget.controller.api.sendDirectMessage(
        _friendId,
        body,
      );
      if (!mounted) return;
      _composer.clear();
      setState(() {
        _messages = [..._messages, sent];
        _error = null;
      });
      _scrollToLatest();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendEmoji(String emoji) async {
    if (_sending || _uploading) return;
    _composer.text = emoji;
    await _send();
  }

  Future<void> _pickAttachment(String kind) async {
    if (_sending || _uploading) return;
    final XFile? file = kind == 'IMAGE'
        ? await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 88,
            maxWidth: 2048,
          )
        : await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(minutes: 5),
          );
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final sent = await widget.controller.api.sendDirectAttachment(
        friendId: _friendId,
        filePath: file.path,
        fileName: file.name,
        kind: kind,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, sent];
        _error = null;
      });
      _scrollToLatest();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showAttachmentPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF21172C),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _pickAttachment('IMAGE');
                  },
                  icon: const Icon(Icons.image_rounded),
                  label: const Text('Photo'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _pickAttachment('VIDEO');
                  },
                  icon: const Icon(Icons.video_library_rounded),
                  label: const Text('Video'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final avatar = widget.friend['avatarUrl']?.toString();
    final online = widget.friend['online'] == true;
    final myId = widget.controller.profile?.id;
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xCC171022),
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF392442),
                  backgroundImage: avatar == null || avatar.isEmpty
                      ? null
                      : NetworkImage(avatar),
                  child: avatar == null || avatar.isEmpty
                      ? Text(_friendName.characters.first.toUpperCase())
                      : null,
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFF52E09D) : Colors.white38,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF171022),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _friendName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '@$_friendUsername',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _HomeBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: SizedBox(
                  width: math.min(constraints.maxWidth, 900),
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _error != null && _messages.isEmpty
                            ? Center(
                                child: TextButton.icon(
                                  onPressed: () => _load(showSpinner: true),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text('Retry: $_error'),
                                ),
                              )
                            : _messages.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.waving_hand_rounded,
                                      size: 42,
                                      color: Color(0xFFFF7CC8),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Say hello to $_friendName',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: () => _load(showSpinner: false),
                                child: ListView.builder(
                                  controller: _scroll,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    18,
                                    16,
                                    12,
                                  ),
                                  itemCount: _messages.length,
                                  itemBuilder: (_, index) {
                                    final message = _messages[index];
                                    final mine = message.senderId == myId;
                                    final emojiOnly = _isRaveEmoji(
                                      message.body,
                                    );
                                    return Align(
                                      alignment: mine
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          maxWidth: 300,
                                        ),
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        padding: emojiOnly
                                            ? EdgeInsets.zero
                                            : const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 10,
                                              ),
                                        decoration: BoxDecoration(
                                          gradient: mine && !emojiOnly
                                              ? const LinearGradient(
                                                  colors: [
                                                    Color(0xFF9C62F2),
                                                    Color(0xFFE05FAE),
                                                  ],
                                                )
                                              : null,
                                          color: mine || emojiOnly
                                              ? null
                                              : const Color(0x2FFFFFFF),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: _DirectMessageContent(
                                          message: message,
                                          mine: mine,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          10,
                          12,
                          10 + MediaQuery.paddingOf(context).bottom,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xEE171022),
                          border: Border(
                            top: BorderSide(color: Color(0x24FFFFFF)),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              child: _showEmojis
                                  ? SizedBox(
                                      height: 54,
                                      child: ListView(
                                        scrollDirection: Axis.horizontal,
                                        children: [
                                          for (final emoji in const [
                                            '❤️',
                                            '😊',
                                            '😂',
                                            '🔥',
                                            '😍',
                                            '👏',
                                            '🎉',
                                            '🤯',
                                            '👀',
                                          ])
                                            _AnimatedEmojiButton(
                                              emoji: emoji,
                                              onTap: () => _sendEmoji(emoji),
                                            ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Photos and videos',
                                  onPressed: _uploading
                                      ? null
                                      : _showAttachmentPicker,
                                  icon: _uploading
                                      ? const SizedBox.square(
                                          dimension: 19,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_circle_outline_rounded,
                                        ),
                                ),
                                IconButton(
                                  tooltip: 'Animated emoji',
                                  onPressed: () => setState(
                                    () => _showEmojis = !_showEmojis,
                                  ),
                                  icon: Icon(
                                    _showEmojis
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.emoji_emotions_outlined,
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _composer,
                                    minLines: 1,
                                    maxLines: 4,
                                    maxLength: 2000,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: 'Message $_friendName',
                                      filled: true,
                                      fillColor: const Color(0x18FFFFFF),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 15,
                                            vertical: 11,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(22),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onSubmitted: (_) => _send(),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton.filled(
                                  tooltip: 'Send message',
                                  onPressed: _sending || _uploading
                                      ? null
                                      : _send,
                                  icon: _sending
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.send_rounded),
                                ),
                              ],
                            ),
                          ],
                        ),
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
  }
}

class _DirectMessageContent extends StatelessWidget {
  const _DirectMessageContent({required this.message, required this.mine});

  final DirectMessage message;
  final bool mine;

  String? get _attachmentUrl {
    final path = message.attachmentUrl;
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return Uri.parse(AppConfig.appBaseUrl).resolve(path).toString();
  }

  @override
  Widget build(BuildContext context) {
    final url = _attachmentUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url != null && message.attachmentType == 'IMAGE')
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              width: 220,
              height: 180,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      width: 220,
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    ),
              errorBuilder: (_, _, _) => const SizedBox(
                width: 220,
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        if (url != null && message.attachmentType == 'VIDEO')
          InkWell(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => _VideoAttachmentScreen(
                  url: url,
                  title: message.attachmentName ?? 'Video',
                ),
              ),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 220,
              height: 124,
              decoration: BoxDecoration(
                color: const Color(0x66000000),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_circle_fill_rounded, size: 46),
                  const SizedBox(height: 6),
                  Text(
                    message.attachmentName ?? 'Play video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        if (message.body.isNotEmpty) ...[
          if (url != null) const SizedBox(height: 8),
          if (_isRaveEmoji(message.body))
            _RaveAnimatedEmoji(emoji: message.body, mine: mine)
          else
            Text(message.body),
        ],
      ],
    );
  }
}

bool _isRaveEmoji(String value) =>
    value.isNotEmpty &&
    value.characters.length <= 3 &&
    !RegExp(r'[A-Za-z0-9]').hasMatch(value);

class _RaveAnimatedEmoji extends StatefulWidget {
  const _RaveAnimatedEmoji({required this.emoji, required this.mine});

  final String emoji;
  final bool mine;

  @override
  State<_RaveAnimatedEmoji> createState() => _RaveAnimatedEmojiState();
}

class _RaveAnimatedEmojiState extends State<_RaveAnimatedEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: 76,
      height: 76,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final motion = _emojiMotion(widget.emoji, t);
          return CustomPaint(
            painter: _EmojiEffectPainter(emoji: widget.emoji, progress: t),
            child: Center(
              child: Transform.translate(
                offset: motion.offset,
                child: Transform.rotate(
                  angle: motion.rotation,
                  child: Transform.scale(scale: motion.scale, child: child),
                ),
              ),
            ),
          );
        },
        child: Text(
          widget.emoji,
          textDirection: widget.mine ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(fontSize: 50, height: 1),
        ),
      ),
    ),
  );
}

({double scale, double rotation, Offset offset}) _emojiMotion(
  String emoji,
  double t,
) {
  final wave = math.sin(t * math.pi * 2);
  final quickWave = math.sin(t * math.pi * 4);
  if (emoji.contains('🔥')) {
    return (
      scale: 1 + .08 * wave.abs(),
      rotation: .07 * quickWave,
      offset: Offset(0, -3 * wave.abs()),
    );
  }
  if (emoji.contains('😂') || emoji.contains('😊') || emoji.contains('😍')) {
    return (
      scale: 1 + .05 * wave.abs(),
      rotation: .09 * quickWave,
      offset: Offset(0, -7 * wave.abs()),
    );
  }
  if (emoji.contains('❤️') || emoji.contains('❤')) {
    final beat = math.pow(wave.abs(), 5).toDouble();
    return (scale: 1 + .18 * beat, rotation: 0, offset: Offset.zero);
  }
  if (emoji.contains('👏')) {
    return (
      scale: 1 + .1 * wave.abs(),
      rotation: .13 * quickWave,
      offset: Offset(4 * wave, 0),
    );
  }
  if (emoji.contains('🎉')) {
    return (
      scale: 1 + .08 * wave.abs(),
      rotation: -.12 + .08 * wave,
      offset: Offset(0, -3 * wave.abs()),
    );
  }
  if (emoji.contains('🤯')) {
    return (
      scale: 1 + .12 * wave.abs(),
      rotation: .05 * math.sin(t * math.pi * 10),
      offset: Offset(2.5 * math.sin(t * math.pi * 12), 0),
    );
  }
  if (emoji.contains('👀')) {
    return (
      scale: 1,
      rotation: 0,
      offset: Offset(7 * math.sin(t * math.pi * 2), 0),
    );
  }
  return (
    scale: 1 + .08 * wave.abs(),
    rotation: .05 * quickWave,
    offset: Offset(0, -4 * wave.abs()),
  );
}

class _EmojiEffectPainter extends CustomPainter {
  const _EmojiEffectPainter({required this.emoji, required this.progress});

  final String emoji;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (emoji.contains('🔥')) {
      const colors = [Color(0xFFFFD54F), Color(0xFFFF7043), Color(0xFFFF3D81)];
      for (var i = 0; i < 7; i++) {
        final phase = (progress + i / 7) % 1;
        final x = size.width * (.24 + ((i * 37) % 53) / 100);
        final y = size.height * (.78 - phase * .72);
        canvas.drawCircle(
          Offset(x + math.sin(phase * math.pi * 4) * 5, y),
          2.8 * (1 - phase),
          Paint()
            ..color = colors[i % colors.length].withValues(alpha: 1 - phase),
        );
      }
    } else if (emoji.contains('🎉') || emoji.contains('🤯')) {
      const colors = [
        Color(0xFFFF5DB1),
        Color(0xFF8F72FF),
        Color(0xFF4BD9FF),
        Color(0xFFFFD54F),
      ];
      for (var i = 0; i < 12; i++) {
        final angle = i * math.pi * 2 / 12;
        final distance = 18 + 23 * progress;
        final point =
            size.center(Offset.zero) +
            Offset(math.cos(angle), math.sin(angle)) * distance;
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(angle + progress * math.pi);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 5, height: 2.5),
          Paint()
            ..color = colors[i % colors.length].withValues(
              alpha: 1 - progress * .65,
            ),
        );
        canvas.restore();
      }
    } else if (emoji.contains('❤️') || emoji.contains('❤')) {
      final radius = 24 + progress * 14;
      canvas.drawCircle(
        size.center(Offset.zero),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFF6FAE).withValues(alpha: 1 - progress),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmojiEffectPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.emoji != emoji;
}

class _AnimatedEmojiButton extends StatefulWidget {
  const _AnimatedEmojiButton({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  State<_AnimatedEmojiButton> createState() => _AnimatedEmojiButtonState();
}

class _AnimatedEmojiButtonState extends State<_AnimatedEmojiButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    lowerBound: .92,
    upperBound: 1.08,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _controller,
    child: IconButton(
      tooltip: 'Send ${widget.emoji}',
      onPressed: widget.onTap,
      icon: Text(widget.emoji, style: const TextStyle(fontSize: 28)),
    ),
  );
}

class _VideoAttachmentScreen extends StatefulWidget {
  const _VideoAttachmentScreen({required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<_VideoAttachmentScreen> createState() => _VideoAttachmentScreenState();
}

class _VideoAttachmentScreenState extends State<_VideoAttachmentScreen> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          _controller.play();
          setState(() {});
        })
        .catchError((Object error) {
          if (mounted) setState(() => _error = error);
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.title)),
    body: LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SizedBox(
          width: math.min(constraints.maxWidth, 1280),
          height: math.min(constraints.maxHeight, 720),
          child: Center(
            child: _error != null
                ? const Text('Could not play this video.')
                : !_controller.value.isInitialized
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () {
                      _controller.value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                      setState(() {});
                    },
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
          ),
        ),
      ),
    ),
    floatingActionButton: _controller.value.isInitialized
        ? FloatingActionButton.small(
            onPressed: () {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
              setState(() {});
            },
            child: Icon(
              _controller.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          )
        : null,
  );
}

class _FriendsSectionHeader extends StatelessWidget {
  const _FriendsSectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      const Spacer(),
      Text(
        '$count',
        style: const TextStyle(
          color: Color(0xFFDBAEF3),
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 42),
    child: Column(
      children: [
        Icon(Icons.people_outline_rounded, size: 46, color: Color(0xFFDBAEF3)),
        SizedBox(height: 12),
        Text(
          'Your circle starts here',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 6),
        Text(
          'Accepted friends will appear here with presence and time watched together.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xAFFFFFFF), height: 1.35),
        ),
      ],
    ),
  );
}

class _FriendRequestTile extends StatelessWidget {
  const _FriendRequestTile({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
    leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
    title: Text(
      (request['displayName'] ?? request['username'] ?? 'Member').toString(),
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text('@${request['username'] ?? 'member'}'),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Reject request',
          onPressed: onReject,
          icon: const Icon(Icons.close_rounded),
        ),
        IconButton.filled(
          tooltip: 'Accept request',
          onPressed: onAccept,
          icon: const Icon(Icons.check_rounded),
        ),
      ],
    ),
  );
}

class _FriendsError extends StatelessWidget {
  const _FriendsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _ProfilePane extends StatelessWidget {
  const _ProfilePane({required this.controller});

  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: const Color(0x44FFFFFF),
              backgroundImage: controller.profile?.avatarUrl == null
                  ? null
                  : NetworkImage(controller.profile!.avatarUrl!),
              child: controller.profile?.avatarUrl == null
                  ? Text(
                      controller.displayName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.displayName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '@${controller.profile?.username ?? 'member'}',
                    style: const TextStyle(
                      color: Color(0xAFFFFFFF),
                      fontSize: 13,
                    ),
                  ),
                  if (controller.profile?.bio?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 7),
                    Text(
                      controller.profile!.bio!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xDFFFFFFF),
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFFECA3FF),
                  size: 20,
                ),
                const SizedBox(height: 8),
                _ProfileVisibilityButton(
                  section: 'bio',
                  controller: controller,
                ),
              ],
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: Color(0x24FFFFFF)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ProfileStat(
              value: '${controller.friendCount}',
              label: 'Friends',
              icon: Icons.people_alt_rounded,
              accent: const Color(0xFFFF78C8),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _FriendsScreen(controller: controller),
                ),
              ),
            ),
            _ProfileStat(
              value: _watchTime(controller.watchTogetherSeconds),
              label: 'Together',
              icon: Icons.auto_awesome_rounded,
              accent: const Color(0xFFB98AFF),
            ),
            _ProfileStat(
              value: '${controller.gallery.length}',
              label: 'Gallery',
              icon: Icons.collections_rounded,
              accent: const Color(0xFF63D8FF),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _ProfileSectionHeader(
        label: 'YOUR ACTIVITY',
        section: 'activity',
        controller: controller,
      ),
      _ActivitySummary(controller: controller),
      const SizedBox(height: 8),
      _HistoryStrip(controller: controller),
      if (controller.likedVideos.isNotEmpty) ...[
        const _SettingsLabel('LIKED VIDEOS'),
        _LikedVideosStrip(controller: controller),
      ],
      if (controller.gallery.isNotEmpty) ...[
        _ProfileSectionHeader(
          label: 'GALLERY',
          section: 'gallery',
          controller: controller,
        ),
        _GalleryStrip(controller: controller),
      ],
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: controller.logout,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: const Color(0xFFFFB9C3),
          side: const BorderSide(color: Color(0x66FF8798)),
        ),
      ),
    ],
  );
}

class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader({
    required this.label,
    required this.section,
    required this.controller,
  });

  final String label;
  final String section;
  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _SettingsLabel(label)),
      _ProfileVisibilityButton(section: section, controller: controller),
    ],
  );
}

class _ProfileVisibilityButton extends StatelessWidget {
  const _ProfileVisibilityButton({
    required this.section,
    required this.controller,
  });

  final String section;
  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) {
    final value = controller.profileVisibility[section] ?? 'PRIVATE';
    final icon = switch (value) {
      'PUBLIC' => Icons.visibility_rounded,
      'FRIENDS' => Icons.group_rounded,
      _ => Icons.visibility_off_rounded,
    };
    return PopupMenuButton<String>(
      tooltip: 'Who can see this section',
      initialValue: value,
      onSelected: (next) => controller.setProfileVisibility(section, next),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'PUBLIC',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.public_rounded),
            title: Text('Everyone'),
          ),
        ),
        PopupMenuItem(
          value: 'FRIENDS',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.group_rounded),
            title: Text('Friends only'),
          ),
        ),
        PopupMenuItem(
          value: 'PRIVATE',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.lock_rounded),
            title: Text('Only me'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22, color: const Color(0xFFECA3FF)),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    this.onTap,
  });
  final String value;
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(bottom: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: .9),
                  accent.withValues(alpha: .35),
                ],
              ),
              border: Border.all(color: const Color(0x66FFFFFF)),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: .28), blurRadius: 13),
              ],
            ),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xAFFFFFFF), fontSize: 11),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 13,
                  color: Color(0xAFFFFFFF),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

String _watchTime(int seconds) {
  final duration = Duration(seconds: seconds);
  if (duration.inHours > 0) return '${duration.inHours}h';
  return '${duration.inMinutes}m';
}

String _watchTimeDetailed(int seconds) {
  final duration = Duration(seconds: seconds);
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? '${duration.inHours}h'
        : '${duration.inHours}h ${minutes}m';
  }
  if (duration.inMinutes > 0) return '${duration.inMinutes}m';
  return '<1m';
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.controller});
  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) {
    final categories = controller.categoryViews;
    final total = categories.values.fold<int>(0, (sum, value) => sum + value);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x24120A1D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: total == 0
          ? const Text(
              'Your real watch categories will appear after you play something.',
              style: TextStyle(color: Color(0xBFFFFFFF)),
            )
          : Row(
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CustomPaint(painter: _CategoryPiePainter(categories)),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: categories.entries
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              '${entry.key}  ·  ${entry.value}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CategoryPiePainter extends CustomPainter {
  _CategoryPiePainter(this.values);
  final Map<String, int> values;
  static const colors = [
    Color(0xFFECA3FF),
    Color(0xFF53B6FF),
    Color(0xFFF47521),
    Color(0xFF9EE36D),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.values.fold<int>(0, (sum, value) => sum + value);
    var start = -1.5708;
    var index = 0;
    for (final value in values.values) {
      final sweep = 6.28318 * value / total;
      canvas.drawArc(
        Offset.zero & size,
        start,
        sweep,
        true,
        Paint()..color = colors[index++ % colors.length],
      );
      start += sweep;
    }
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide * .25,
      Paint()..color = const Color(0xFF171124),
    );
  }

  @override
  bool shouldRepaint(covariant _CategoryPiePainter oldDelegate) =>
      oldDelegate.values != values;
}

class _HistoryStrip extends StatelessWidget {
  const _HistoryStrip({required this.controller});
  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.history.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: controller.history.length.clamp(0, 12),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = controller.history[index];
          return SizedBox(
            width: 178,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onLongPress: () => _showHistoryActions(context, controller, item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX:
                                  item.sensitive &&
                                      controller.hideSensitiveContent
                                  ? 14
                                  : 0,
                              sigmaY:
                                  item.sensitive &&
                                      controller.hideSensitiveContent
                                  ? 14
                                  : 0,
                            ),
                            child: MediaPreview(
                              mediaId: item.mediaId,
                              provider: item.provider,
                              thumbnailUrl: item.thumbnailUrl,
                              contentLabel: item.title,
                              sensitive: item.sensitive,
                            ),
                          ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Row(
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      controller.toggleGallery(item),
                                  icon: Icon(
                                    controller.gallery.any(
                                          (entry) =>
                                              entry.mediaId == item.mediaId,
                                        )
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_add_outlined,
                                    color: const Color(0xFFE9C8FF),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => controller.toggleLike(item),
                                  icon: Icon(
                                    controller.likedMediaIds.contains(
                                          item.mediaId,
                                        )
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: const Color(0xFFFF9DB1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> _showHistoryActions(
  BuildContext context,
  WatchPartyController controller,
  ViewingActivity item,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(item.title),
            subtitle: const Text('History options'),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_add_outlined),
            title: Text(
              controller.gallery.any((entry) => entry.mediaId == item.mediaId)
                  ? 'Remove from gallery'
                  : 'Add to gallery',
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              await controller.toggleGallery(item);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFFF9AAA),
            ),
            title: const Text('Remove from history'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await controller.removeHistory(item);
            },
          ),
        ],
      ),
    ),
  );
}

class _GalleryStrip extends StatelessWidget {
  const _GalleryStrip({required this.controller});
  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 126,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: controller.gallery.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final item = controller.gallery[index];
        return SizedBox(
          width: 168,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaPreview(
                  mediaId: item.mediaId,
                  provider: item.provider,
                  thumbnailUrl: item.thumbnailUrl,
                  contentLabel: item.title,
                  sensitive: item.sensitive,
                ),
                Positioned(
                  right: 3,
                  top: 3,
                  child: IconButton(
                    tooltip: 'Remove from gallery',
                    onPressed: () => controller.toggleGallery(item),
                    icon: const Icon(Icons.bookmark_remove_rounded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _LikedVideosStrip extends StatelessWidget {
  const _LikedVideosStrip({required this.controller});

  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 142,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: controller.likedVideos.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final item = controller.likedVideos[index];
        return SizedBox(
          width: 178,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _playLibraryItem(controller, item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX:
                                item.sensitive &&
                                    controller.hideSensitiveContent
                                ? 14
                                : 0,
                            sigmaY:
                                item.sensitive &&
                                    controller.hideSensitiveContent
                                ? 14
                                : 0,
                          ),
                          child: MediaPreview(
                            mediaId: item.mediaId,
                            provider: item.provider,
                            thumbnailUrl: item.thumbnailUrl,
                            contentLabel: item.title,
                            sensitive: item.sensitive,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: IconButton.filledTonal(
                            tooltip: 'Unlike video',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => controller.toggleLike(item),
                            icon: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF9DB1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _playLibraryItem(
  WatchPartyController controller,
  ViewingActivity item,
) async {
  if (item.provider == 'YOUTUBE') {
    await controller.selectYoutubeVideo(
      VideoSuggestion(
        videoId: item.mediaId,
        title: item.title,
        channelTitle: 'YouTube',
        thumbnailUrl: item.thumbnailUrl,
        provider: item.provider,
      ),
    );
    return;
  }
  await controller.selectProviderMedia(
    provider: item.provider,
    mediaId: item.mediaId,
    title: item.title,
    thumbnailUrl: item.thumbnailUrl,
  );
}

bool _looksSensitive(String value) {
  final text = value.toLowerCase();
  return const [
    'nsfw',
    'adult',
    'porn',
    'xxx',
    'xhamster',
    'xvideos',
    'pornhub',
    'femdom',
    'nude',
    'sex',
  ].any(text.contains);
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 7),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFFDEC6F1),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    ),
  );
}

// Legacy picker retained temporarily for visual comparison during the rollout.
// ignore: unused_element
class _SourcePicker extends StatelessWidget {
  const _SourcePicker({required this.controller});

  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) {
    const sources = [
      ('YouTube', Icons.play_circle_fill_rounded, true),
      ('Twitch', Icons.live_tv_rounded, false),
      ('Direct video', Icons.language_rounded, true),
      ('Drive', Icons.cloud_rounded, false),
      ('Photos', Icons.photo_library_rounded, false),
      ('Watch history', Icons.history_rounded, false),
    ];
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF08F376F), Color(0xEE365786), Color(0xF00B1526)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Expanded(
                    child: Text(
                      "LET'S COOK",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                readOnly: true,
                onTap: () => Navigator.pop(context, 'youtube'),
                decoration: const InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Start watching',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose where your room will watch from.',
                style: TextStyle(color: Color(0xCCFFFFFF)),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: GridView.builder(
                  itemCount: sources.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.25,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final source = sources[index];
                    return _SourceTile(
                      name: source.$1,
                      icon: source.$2,
                      available: source.$3,
                      onTap: source.$3
                          ? () {
                              if (source.$1 == 'Direct video') {
                                _openDirectVideo(context);
                                return;
                              }
                              if (source.$1 == 'YouTube') {
                                Navigator.pop(context, 'youtube');
                                return;
                              }
                              Navigator.pop(context);
                              controller.createParty();
                            }
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDirectVideo(BuildContext context) async {
    final field = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open direct video'),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/video.mp4 or stream.m3u8',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, field.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    field.dispose();
    if (url == null || url.trim().isEmpty || !context.mounted) return;
    Navigator.pop(context);
    await controller.createDirectParty(url);
  }
}

class _YoutubeStartPicker extends StatefulWidget {
  const _YoutubeStartPicker({required this.controller});

  final WatchPartyController controller;

  @override
  State<_YoutubeStartPicker> createState() => _YoutubeStartPickerState();
}

class _YoutubeStartPickerState extends State<_YoutubeStartPicker> {
  final field = TextEditingController();
  Timer? debounce;
  List<VideoSuggestion> results = const [];
  bool searching = false;

  @override
  void dispose() {
    debounce?.cancel();
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF0B1020),
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          16,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choose a YouTube video',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Text(
              'Your room is created only after you select a video.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: field,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search YouTube',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text(
                        'Start typing to see videos.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final video = results[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          leading: SizedBox(
                            width: 104,
                            height: 60,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: MediaPreview(
                                mediaId: video.videoId,
                                provider: video.provider,
                                thumbnailUrl: video.thumbnailUrl,
                                contentLabel: video.title,
                              ),
                            ),
                          ),
                          title: Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(video.channelTitle),
                          onTap: () => Navigator.pop(context, video),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  void _onChanged(String value) {
    debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => results = const []);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String value) async {
    if (value.trim().length < 2) return;
    setState(() => searching = true);
    try {
      final found = await widget.controller.searchVideos(value);
      if (mounted) setState(() => results = found);
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.name,
    required this.icon,
    required this.available,
    this.onTap,
  });

  final String name;
  final IconData icon;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: available ? const Color(0x38FFFFFF) : const Color(0x1AFFFFFF),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              icon,
              size: 38,
              color: available ? Colors.white : Colors.white38,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: available ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
                if (!available)
                  const Text(
                    'SOON',
                    style: TextStyle(fontSize: 8, color: Colors.white38),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
