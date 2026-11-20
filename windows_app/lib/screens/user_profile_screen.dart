import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/watch_party_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/media_preview.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.controller,
    required this.userId,
    this.summary = const {},
  });
  final WatchPartyController controller;
  final String userId;
  final Map<String, dynamic> summary;
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? profile;
  String? error;
  bool loading = true;
  bool actionBusy = false;

  Map<String, dynamic> get data => profile ?? widget.summary;
  bool get mine => widget.userId == widget.controller.profile?.id;
  Map<String, dynamic> get relationship =>
      (data['relationship'] as Map<String, dynamic>?) ?? const {};
  String get relationshipStatus =>
      (relationship['status'] ?? (mine ? 'SELF' : 'NONE')).toString();
  bool get outgoingRequest => relationship['outgoing'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.controller.api.publicProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        profile = loaded;
        loading = false;
        error = null;
      });
    } catch (exception) {
      debugPrint('Could not load profile ${widget.userId}: $exception');
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.toString();
      });
    }
  }

  Future<void> _friendAction() async {
    if (actionBusy || mine) return;
    setState(() => actionBusy = true);
    try {
      if (relationshipStatus == 'ACCEPTED' ||
          (relationshipStatus == 'PENDING' && outgoingRequest)) {
        await widget.controller.api.removeFriend(widget.userId);
      } else if (relationshipStatus == 'PENDING') {
        final requestId = relationship['id']?.toString();
        if (requestId != null && requestId.isNotEmpty) {
          await widget.controller.api.decideFriendRequest(requestId, true);
        }
      } else {
        await widget.controller.api.sendFriendRequest(widget.userId);
      }
      await _load();
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _playMedia(Map<String, dynamic> item) async {
    await widget.controller.selectLibraryItem(
      ViewingActivity.fromJson(item),
      targetRoomId: widget.controller.activeRoom?.id,
    );
    if (mounted && widget.controller.activeRoom != null) {
      Navigator.of(context).pop();
    }
  }

  List<Map<String, dynamic>> _maps(String key) =>
      (data[key] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
  Map<String, num> _numberMap(String key) {
    final source = data[key];
    if (source is! Map) return const {};
    return source.map(
      (key, value) => MapEntry(key.toString(), value is num ? value : 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _publicDisplayName(data);
    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(name),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const Positioned.fill(child: _ProfileBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: SizedBox(
                  width: math.min(constraints.maxWidth, 960),
                  height: constraints.maxHeight,
                  child: loading && profile == null
                      ? const Center(child: CircularProgressIndicator())
                      : error != null && profile == null
                      ? _ProfileError(retry: _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 42),
                            children: [
                              _ProfileHeader(
                                data: data,
                                mine: mine,
                                status: relationshipStatus,
                                outgoing: outgoingRequest,
                                busy: actionBusy,
                                onFriendAction: _friendAction,
                              ),
                              _BioSection(data: data),
                              _MediaSection(
                                controller: widget.controller,
                                title: 'Gallery',
                                icon: Icons.photo_library_rounded,
                                items: _maps('gallery'),
                                emptyText: 'No public gallery items yet.',
                                onTap: _playMedia,
                              ),
                              _ActivitySection(
                                activity: _maps('activityByDay'),
                                online: data['online'] == true,
                                lastSeenAt: data['lastSeenAt']?.toString(),
                              ),
                              _FriendsOrbitSection(
                                controller: widget.controller,
                                friends: _maps('watchFriends'),
                                friendCount: _asInt(data['friendCount']),
                              ),
                              _MediaSection(
                                controller: widget.controller,
                                title: 'History',
                                icon: Icons.history_rounded,
                                items: _maps('history'),
                                emptyText: 'Watch history is private or empty.',
                                onTap: _playMedia,
                              ),
                              _MediaSection(
                                controller: widget.controller,
                                title: 'Liked',
                                icon: Icons.favorite_rounded,
                                items: _maps('likedVideos'),
                                emptyText: 'No visible liked videos.',
                                onTap: _playMedia,
                              ),
                              _InterestSection(
                                inferred: _numberMap('inferredInterests'),
                                saved:
                                    (data['interests'] as List<dynamic>? ??
                                            const [])
                                        .map((v) => v.toString())
                                        .toList(),
                                sensitiveHidden:
                                    data['sensitiveContentHidden'] == true,
                              ),
                              _ProviderSection(
                                values: _numberMap('providerUsage'),
                              ),
                              if (_maps('connections').isNotEmpty)
                                _ConnectionsSection(
                                  items: _maps('connections'),
                                ),
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

class _ProfileBackdrop extends StatelessWidget {
  const _ProfileBackdrop();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF24123D), Color(0xFF071923), Color(0xFF080711)],
        stops: [0, .48, 1],
      ),
    ),
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.data,
    required this.mine,
    required this.status,
    required this.outgoing,
    required this.busy,
    required this.onFriendAction,
  });
  final Map<String, dynamic> data;
  final bool mine, outgoing, busy;
  final String status;
  final VoidCallback onFriendAction;
  @override
  Widget build(BuildContext context) {
    final name = _publicDisplayName(data);
    final avatar = data['avatarUrl']?.toString();
    final online = data['online'] == true;
    final joined = _dateLabel(data['joinedAt']?.toString());
    final friendLabel = switch (status) {
      'ACCEPTED' => 'Remove friend',
      'PENDING' when outgoing => 'Revoke request',
      'PENDING' => 'Accept request',
      _ => 'Add friend',
    };
    final friendIcon = switch (status) {
      'ACCEPTED' => Icons.person_remove_rounded,
      'PENDING' when outgoing => Icons.undo_rounded,
      'PENDING' => Icons.person_add_alt_1_rounded,
      _ => Icons.person_add_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(accent: const Color(0x66ECA3FF)),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.lime, AppColors.mint],
                  ),
                ),
                child: CircleAvatar(
                  radius: 54,
                  backgroundColor: AppColors.panelSoft,
                  foregroundImage: avatar?.isNotEmpty == true
                      ? NetworkImage(avatar!)
                      : null,
                  child: avatar?.isNotEmpty == true
                      ? null
                      : Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    color: online ? AppColors.mint : AppColors.muted,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF120B1D),
                      width: 3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            '@${_publicHandle(data)}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                icon: online ? Icons.circle : Icons.schedule_rounded,
                text: online
                    ? 'Online now'
                    : 'Last seen ${_relativeTime(data['lastSeenAt'])}',
                color: online ? AppColors.mint : AppColors.muted,
              ),
              if (joined.isNotEmpty)
                _Pill(
                  icon: Icons.auto_awesome_rounded,
                  text: 'Joined $joined',
                  color: AppColors.lime,
                ),
            ],
          ),
          if (!mine) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onFriendAction,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(friendIcon),
                label: Text(friendLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BioSection extends StatelessWidget {
  const _BioSection({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    if (!data.containsKey('bio')) return const SizedBox.shrink();
    final bio = data['bio']?.toString().trim() ?? '';
    return _SectionCard(
      title: 'Bio',
      icon: Icons.format_quote_rounded,
      child: Text(
        bio.isEmpty ? 'No bio added yet.' : bio,
        style: TextStyle(
          color: bio.isEmpty ? AppColors.muted : Colors.white,
          height: 1.45,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.activity,
    required this.online,
    required this.lastSeenAt,
  });
  final List<Map<String, dynamic>> activity;
  final bool online;
  final String? lastSeenAt;
  @override
  Widget build(BuildContext context) {
    final seconds = activity.map((item) => _asInt(item['seconds'])).toList();
    final total = seconds.fold<int>(0, (sum, value) => sum + value);
    final activeDays = seconds.where((value) => value > 0).length;
    return _SectionCard(
      title: 'Activity · since joining',
      icon: Icons.insights_rounded,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _Metric(_duration(total), 'watch time')),
              Expanded(child: _Metric('$activeDays', 'active days')),
              Expanded(
                child: _Metric(
                  online ? 'Now' : _relativeTime(lastSeenAt),
                  'last active',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ScrollableActivityGraph(activity: activity),
        ],
      ),
    );
  }
}

class _ScrollableActivityGraph extends StatefulWidget {
  const _ScrollableActivityGraph({required this.activity});
  final List<Map<String, dynamic>> activity;
  @override
  State<_ScrollableActivityGraph> createState() =>
      _ScrollableActivityGraphState();
}

class _ScrollableActivityGraphState extends State<_ScrollableActivityGraph> {
  final ScrollController controller = ScrollController();
  bool showBars = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.activity
        .map((item) => _asInt(item['seconds']))
        .toList();
    final first = widget.activity.isEmpty
        ? ''
        : _shortDate(widget.activity.first['day']);
    final last = widget.activity.isEmpty
        ? ''
        : _shortDate(widget.activity.last['day']);
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.show_chart_rounded, size: 16),
                label: Text('Line'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.bar_chart_rounded, size: 16),
                label: Text('Bars'),
              ),
            ],
            selected: {showBars},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            onSelectionChanged: (selection) {
              setState(() => showBars = selection.first);
            },
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final graphWidth = math.max(
              constraints.maxWidth,
              seconds.length * 26.0,
            );
            return Scrollbar(
              controller: controller,
              thumbVisibility: graphWidth > constraints.maxWidth,
              interactive: true,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: graphWidth,
                  height: 155,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CustomPaint(
                      painter: _ActivityPainter(seconds, bars: showBars),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              first.isEmpty ? 'Joined' : first,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swipe_rounded, size: 14, color: AppColors.muted),
                SizedBox(width: 4),
                Text(
                  'slide timeline',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
            Text(
              last.isEmpty ? 'Today' : last,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActivityPainter extends CustomPainter {
  _ActivityPainter(this.values, {required this.bars});
  final List<int> values;
  final bool bars;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = size.height * row / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final maxValue = math.max(1, values.reduce(math.max));
    if (bars) {
      final slot = size.width / values.length;
      final barWidth = math.min(14.0, math.max(4.0, slot * 0.55));
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFF7A5CFA), Color(0xFF53D9FF)],
        ).createShader(Offset.zero & size);
      for (var i = 0; i < values.length; i++) {
        final height = values[i] == 0
            ? 2.0
            : math.max(4.0, values[i] / maxValue * (size.height - 10));
        final centerX = slot * i + slot / 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              centerX - barWidth / 2,
              size.height - height,
              barWidth,
              height,
            ),
            const Radius.circular(5),
          ),
          paint,
        );
      }
      return;
    }
    final path = Path(), fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final y = size.height - (values[i] / maxValue) * (size.height - 10);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x6653B6FF), Color(0x0053B6FF)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF53B6FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ActivityPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.bars != bars;
}

class _FriendsOrbitSection extends StatefulWidget {
  const _FriendsOrbitSection({
    required this.controller,
    required this.friends,
    required this.friendCount,
  });
  final WatchPartyController controller;
  final List<Map<String, dynamic>> friends;
  final int friendCount;

  @override
  State<_FriendsOrbitSection> createState() => _FriendsOrbitSectionState();
}

class _FriendsOrbitSectionState extends State<_FriendsOrbitSection> {
  String? selectedFriendId;

  @override
  Widget build(BuildContext context) {
    if (widget.friends.isEmpty && widget.friendCount == 0) {
      return const SizedBox.shrink();
    }
    final visible = widget.friends;
    final totalSeconds = visible.fold<int>(
      0,
      (sum, friend) => sum + math.max(0, _asInt(friend['watchSeconds'])),
    );
    final percentageById = <String, int>{};
    var cumulativeWeight = 0;
    var assignedPercentage = 0;
    final percentageTotal = totalSeconds == 0 ? visible.length : totalSeconds;
    for (var index = 0; index < visible.length; index++) {
      final friend = visible[index];
      cumulativeWeight += totalSeconds == 0
          ? 1
          : math.max(0, _asInt(friend['watchSeconds']));
      final cumulativePercentage = index == visible.length - 1
          ? 100
          : (cumulativeWeight / percentageTotal * 100).round();
      percentageById[_friendId(friend)] =
          cumulativePercentage - assignedPercentage;
      assignedPercentage = cumulativePercentage;
    }
    Map<String, dynamic>? selectedFriend;
    for (final friend in visible) {
      if (_friendId(friend) == selectedFriendId) selectedFriend = friend;
    }
    return _SectionCard(
      title: 'Watch-together friends · ${widget.friendCount}',
      icon: Icons.bubble_chart_rounded,
      child: visible.isEmpty
          ? const Text(
              'Friend activity is private or no shared watch time yet.',
              style: TextStyle(color: AppColors.muted),
            )
          : Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: 120,
                      maxHeight: 255,
                    ),
                    padding: const EdgeInsets.all(8),
                    color: const Color(0x22000000),
                    child: SingleChildScrollView(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final friend in visible)
                            _FriendBubble(
                              friend: friend,
                              share: totalSeconds == 0
                                  ? 1 / visible.length
                                  : _asInt(friend['watchSeconds']) /
                                        totalSeconds,
                              percent: percentageById[_friendId(friend)] ?? 0,
                              selected: _friendId(friend) == selectedFriendId,
                              onTap: () => _selectOrOpen(friend),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (selectedFriend != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${_publicDisplayName(selectedFriend, fallback: 'Friend')} · '
                    '${_duration(_asInt(selectedFriend['watchSeconds']))} watched together · '
                    'tap again to open profile',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _friendId(Map<String, dynamic> friend) =>
      (friend['id'] ?? friend['userId']).toString();

  void _selectOrOpen(Map<String, dynamic> friend) {
    final id = _friendId(friend);
    if (selectedFriendId != id) {
      setState(() => selectedFriendId = id);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          controller: widget.controller,
          userId: id,
          summary: friend,
        ),
      ),
    );
  }
}

class _FriendBubble extends StatelessWidget {
  const _FriendBubble({
    required this.friend,
    required this.share,
    required this.percent,
    required this.selected,
    required this.onTap,
  });
  final Map<String, dynamic> friend;
  final double share;
  final int percent;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final avatar = friend['avatarUrl']?.toString();
    final name = _publicDisplayName(friend, fallback: 'Friend');
    final normalizedShare = share.clamp(0.0, 1.0);
    final size = 50 + 58 * math.sqrt(normalizedShare);
    return Tooltip(
      message: '$name · ${_duration(_asInt(friend['watchSeconds']))} together',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)],
            ),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFD166)
                  : const Color(0x66FFFFFF),
              width: selected ? 3 : 1.5,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x55FFD166),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF24152E),
                foregroundImage: avatar?.isNotEmpty == true
                    ? NetworkImage(avatar!)
                    : null,
                child: avatar?.isNotEmpty == true
                    ? null
                    : Text(name.isEmpty ? '?' : name[0].toUpperCase()),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC080711),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$percent%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InterestSection extends StatelessWidget {
  const _InterestSection({
    required this.inferred,
    required this.saved,
    required this.sensitiveHidden,
  });
  final Map<String, num> inferred;
  final List<String> saved;
  final bool sensitiveHidden;
  @override
  Widget build(BuildContext context) {
    final labels = <String>{...inferred.keys, ...saved}.toList();
    return _SectionCard(
      title: 'Interests from watch history',
      icon: Icons.interests_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (labels.isEmpty)
            const Text(
              'Interests will grow from watch history.',
              style: TextStyle(color: AppColors.muted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in labels)
                  Chip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: Text(label),
                    backgroundColor: const Color(0x332BDAA5),
                    side: const BorderSide(color: Color(0x334DFFD1)),
                  ),
              ],
            ),
          if (sensitiveHidden) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.shield_rounded, size: 16, color: AppColors.mint),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Mature content is excluded from these interests.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderSection extends StatelessWidget {
  const _ProviderSection({required this.values});
  final Map<String, num> values;
  static const colors = [
    Color(0xFFECA3FF),
    Color(0xFF53B6FF),
    Color(0xFFF47521),
    Color(0xFF9EE36D),
    Color(0xFFFFD166),
    Color(0xFFEF476F),
  ];
  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final entries = values.entries.toList();
    final total = values.values.fold<double>(
      0,
      (sum, value) => sum + value.toDouble(),
    );
    return _SectionCard(
      title: 'Providers & sites used',
      icon: Icons.donut_large_rounded,
      child: Row(
        children: [
          SizedBox(
            width: 118,
            height: 118,
            child: CustomPaint(painter: _DonutPainter(values)),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: colors[i % colors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _providerLabel(entries[i].key),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(entries[i].value / total * 100).round()}%',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);
  final Map<String, num> values;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.values.fold<double>(
      0,
      (sum, value) => sum + value.toDouble(),
    );
    if (total <= 0) return;
    var start = -math.pi / 2, index = 0;
    for (final value in values.values) {
      final sweep = math.pi * 2 * value / total;
      canvas.drawArc(
        (Offset.zero & size).deflate(7),
        start,
        sweep - .025,
        false,
        Paint()
          ..color =
              _ProviderSection.colors[index++ % _ProviderSection.colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.controller,
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyText,
    required this.onTap,
  });
  final WatchPartyController controller;
  final String title, emptyText;
  final IconData icon;
  final List<Map<String, dynamic>> items;
  final Future<void> Function(Map<String, dynamic>) onTap;
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: title,
    icon: icon,
    child: items.isEmpty
        ? Text(emptyText, style: const TextStyle(color: AppColors.muted))
        : SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 11),
              itemBuilder: (_, index) {
                final item = items[index];
                return SizedBox(
                  width: 190,
                  child: Tooltip(
                    message: controller.activeRoom == null
                        ? 'Create a room and play'
                        : 'Add to the room queue',
                    child: InkWell(
                      onTap: () => onTap(item),
                      borderRadius: BorderRadius.circular(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: MediaPreview(
                                mediaId: (item['mediaId'] ?? '').toString(),
                                provider: (item['provider'] ?? 'YOUTUBE')
                                    .toString(),
                                thumbnailUrl: item['thumbnailUrl']?.toString(),
                                contentLabel: (item['title'] ?? 'Video')
                                    .toString(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            (item['title'] ?? 'Video').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.play_circle_outline_rounded,
                                size: 12,
                                color: AppColors.muted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _providerLabel(
                                    (item['provider'] ?? 'Video').toString(),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
  );
}

class _ConnectionsSection extends StatelessWidget {
  const _ConnectionsSection({required this.items});
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Links',
    icon: Icons.link_rounded,
    child: Column(
      children: [
        for (final connection in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.public_rounded),
            title: Text((connection['provider'] ?? 'Link').toString()),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () async {
              final uri = Uri.tryParse(connection['url']?.toString() ?? '');
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.lime, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 11)),
      ],
    ),
  );
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.retry});
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.muted),
          const SizedBox(height: 12),
          const Text('Could not load profile'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

BoxDecoration _cardDecoration({Color accent = const Color(0x28FFFFFF)}) =>
    BoxDecoration(
      color: const Color(0xD9171422),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: accent),
      boxShadow: const [
        BoxShadow(
          color: Color(0x44000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    );

String _publicDisplayName(
  Map<String, dynamic> person, {
  String fallback = 'Member',
}) {
  final displayName = person['displayName']?.toString().trim() ?? '';
  if (displayName.isNotEmpty && !displayName.contains('@')) return displayName;
  final username = person['username']?.toString().trim() ?? '';
  if (username.isNotEmpty && !username.contains('@')) return username;
  return fallback;
}

String _publicHandle(Map<String, dynamic> person) {
  final username = person['username']?.toString().trim() ?? '';
  if (username.isNotEmpty && !username.contains('@')) return username;
  final id = (person['id'] ?? person['userId'])?.toString() ?? '';
  return id.length >= 8 ? 'member-${id.substring(0, 8)}' : 'member';
}

int _asInt(Object? value) => value is num ? value.toInt() : 0;

String _duration(int seconds) {
  final duration = Duration(seconds: math.max(0, seconds));
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? '${duration.inHours}h'
        : '${duration.inHours}h ${minutes}m';
  }
  if (duration.inMinutes > 0) return '${duration.inMinutes}m';
  return seconds > 0 ? '<1m' : '0m';
}

String _dateLabel(String? value) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String _shortDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.day}/${date.month}/${date.year.toString().substring(2)}';
}

String _relativeTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'recently';
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return _dateLabel(value?.toString());
}

String _providerLabel(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) return 'Web';
  return normalized
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
