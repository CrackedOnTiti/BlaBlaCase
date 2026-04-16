import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../notifications/notifications_screen.dart' show notificationsProvider;

// ── Providers ──────────────────────────────────────────────────────────────

final tripRoomsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await createApiClient().get('/trips/mine');
  return List<Map<String, dynamic>>.from(res.data as List);
});

/// Rooms filtered by local hidden list
final visibleRoomsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rooms = await ref.watch(tripRoomsProvider.future);
  final prefs = await SharedPreferences.getInstance();
  return rooms.where((r) {
    final tripId = r['trip_id'] as String;
    return !(prefs.getBool('hidden_trip_$tripId') ?? false);
  }).toList();
});

final unreadRoomsProvider = FutureProvider.autoDispose<int>((ref) async {
  final rooms = await ref.watch(visibleRoomsProvider.future);
  int count = 0;
  for (final room in rooms) {
    final tripId = room['trip_id'] as String;
    final lastAt = room['last_message_at'] as String?;
    if (await isTripUnread(tripId, lastAt)) count++;
  }
  return count;
});

// ── SharedPreferences helpers ──────────────────────────────────────────────

Future<void> markTripRead(String tripId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('last_read_$tripId', DateTime.now().toIso8601String());
}

Future<bool> isTripUnread(String tripId, String? lastMessageAt) async {
  if (lastMessageAt == null) return false;
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('last_read_$tripId');
  if (raw == null) return true;
  final lastRead = DateTime.parse(raw);
  final lastMsg = DateTime.parse(lastMessageAt);
  return lastMsg.isAfter(lastRead);
}

Future<void> hideTripLocally(String tripId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('hidden_trip_$tripId', true);
}

Future<bool> isTripMuted(String tripId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('muted_trip_$tripId') ?? false;
}

Future<void> setTripMuted(String tripId, bool muted) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('muted_trip_$tripId', muted);
}

// ── Screen ────────────────────────────────────────────────────────────────

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(notificationsProvider);
    final roomsAsync = ref.watch(visibleRoomsProvider);

    final pendingRequests = notifAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(notificationsProvider);
                ref.invalidate(tripRoomsProvider);
                await ref.read(visibleRoomsProvider.future);
              },
              child: roomsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e')),
                data: (rooms) {
                  if (pendingRequests.isEmpty && rooms.isEmpty) {
                    return const CustomScrollView(slivers: [
                      SliverFillRemaining(
                        child: Center(
                          child: Text('Aucun message pour le moment.',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      ),
                    ]);
                  }

                  return ListView(
                    children: [
                      // ── Pending join requests ────────────────────────
                      if (pendingRequests.isNotEmpty) ...[
                        const _SectionLabel(label: 'Demandes en attente'),
                        ...pendingRequests.map((n) => _RequestTile(notif: n, ref: ref)),
                      ],

                      // Ad between sections (or at top if no requests)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: _MessagesBannerAd(),
                      ),

                      // ── Chat rooms ───────────────────────────────────
                      if (rooms.isNotEmpty) ...[
                        const _SectionLabel(label: 'Conversations'),
                        ...rooms.map((r) => _RoomTile(room: r, ref: ref)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          // Fixed bottom ad
          const _MessagesBannerAd(),
        ],
      ),
    );
  }
}

// ── Banner ad ─────────────────────────────────────────────────────────────

class _MessagesBannerAd extends StatefulWidget {
  const _MessagesBannerAd();

  @override
  State<_MessagesBannerAd> createState() => _MessagesBannerAdState();
}

class _MessagesBannerAdState extends State<_MessagesBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', // test ID
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _loaded = true),
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white38,
              letterSpacing: 1)),
    );
  }
}

// ── Request tile ──────────────────────────────────────────────────────────

class _RequestTile extends StatefulWidget {
  final Map<String, dynamic> notif;
  final WidgetRef ref;
  const _RequestTile({required this.notif, required this.ref});

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  bool _loading = false;

  Future<void> _respond(String status) async {
    setState(() => _loading = true);
    try {
      final tripId = widget.notif['trip_id'] as String;
      final userId = (widget.notif['passenger'] as Map)['id'] as String;
      await createApiClient().patch('/trips/$tripId/passengers/$userId', data: {'status': status});
      widget.ref.invalidate(notificationsProvider);
      widget.ref.invalidate(tripRoomsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final passenger = widget.notif['passenger'] as Map<String, dynamic>;
    final city = widget.notif['departure_city'] as String;
    final departAt = DateTime.parse(widget.notif['depart_at'] as String).toLocal();
    final fmt = DateFormat('d MMM', 'fr_FR');
    final intro = widget.notif['intro_message'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: kBorder,
                  child: Text(
                    passenger['display_name'].toString().isNotEmpty
                        ? passenger['display_name'].toString()[0].toUpperCase()
                        : '?',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(passenger['display_name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('veut rejoindre · $city · ${fmt.format(departAt)}',
                        style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ]),
                ),
              ]),
              if (intro != null && intro.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder),
                  ),
                  child: Text(intro,
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ),
              ],
              const SizedBox(height: 12),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _respond('rejected'),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent)),
                          child: const Text('Refuser',
                              style: TextStyle(color: Colors.redAccent)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _respond('accepted'),
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.green),
                          child: const Text('Accepter'),
                        ),
                      ),
                    ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chat room tile ────────────────────────────────────────────────────────

class _RoomTile extends StatefulWidget {
  final Map<String, dynamic> room;
  final WidgetRef ref;
  const _RoomTile({required this.room, required this.ref});

  @override
  State<_RoomTile> createState() => _RoomTileState();
}

class _RoomTileState extends State<_RoomTile> {
  bool _unread = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _checkUnread();
    _checkMuted();
  }

  Future<void> _checkUnread() async {
    final tripId = widget.room['trip_id'] as String;
    final lastAt = widget.room['last_message_at'] as String?;
    final unread = await isTripUnread(tripId, lastAt);
    if (mounted) setState(() => _unread = unread);
  }

  Future<void> _checkMuted() async {
    final tripId = widget.room['trip_id'] as String;
    final muted = await isTripMuted(tripId);
    if (mounted) setState(() => _muted = muted);
  }

  void _showOptions(BuildContext context) {
    final tripId = widget.room['trip_id'] as String;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Mute / Unmute
              ListTile(
                leading: Icon(
                  _muted ? Icons.volume_up_outlined : Icons.volume_off_outlined,
                  color: Colors.white70,
                ),
                title: Text(_muted ? 'Activer les notifications' : 'Mettre en sourdine'),
                subtitle: const Text('Notifications à venir', style: TextStyle(fontSize: 11, color: Colors.white38)),
                onTap: () async {
                  final newMuted = !_muted;
                  await setTripMuted(tripId, newMuted);
                  if (mounted) setState(() => _muted = newMuted);
                  setSheetState(() {});
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              // Participants
              ListTile(
                leading: const Icon(Icons.group_outlined, color: Colors.white70),
                title: const Text('Voir les participants'),
                onTap: () {
                  Navigator.pop(ctx);
                  // Navigate to trip detail for now; full participants view coming soon
                  context.push('/trip/$tripId');
                },
              ),
              // Delete (hide locally)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Supprimer la conversation',
                    style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Masquée localement seulement',
                    style: TextStyle(fontSize: 11, color: Colors.white38)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await hideTripLocally(tripId);
                  widget.ref.invalidate(tripRoomsProvider);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final tripId = room['trip_id'] as String;
    final city = room['departure_city'] as String;
    final departAt = DateTime.parse(room['depart_at'] as String).toLocal();
    final lastContent = room['last_message_content'] as String?;
    final lastAt = room['last_message_at'] as String?;
    final lastSender = room['last_message_sender'] as String?;
    final userHasMessaged = room['user_has_messaged'] as bool? ?? false;
    final fmtDate = DateFormat('d MMM', 'fr_FR');
    final fmtTime = DateFormat('HH:mm', 'fr_FR');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onLongPress: () => _showOptions(context),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: kSurface2,
            child: const Icon(Icons.directions_car, color: kAccent, size: 20),
          ),
          if (_unread)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: Colors.redAccent, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '$city → Pas de la Case',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          if (_muted)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.volume_off_outlined, size: 13, color: Colors.white38),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lastContent != null)
            Text(
              '${lastSender ?? ''}: $lastContent',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: _unread ? Colors.white70 : Colors.white38,
                fontWeight: _unread ? FontWeight.w500 : FontWeight.normal,
              ),
            )
          else
            Text(
              fmtDate.format(departAt),
              style: const TextStyle(fontSize: 13, color: Colors.white38),
            ),
        ],
      ),
      trailing: lastAt != null
          ? Text(
              fmtTime.format(DateTime.parse(lastAt).toLocal()),
              style: TextStyle(
                  fontSize: 11,
                  color: _unread ? kAccent : Colors.white38),
            )
          : null,
      onTap: () async {
        await markTripRead(tripId);
        if (mounted) {
          setState(() => _unread = false);
          context.push('/trip/$tripId/chat');
        }
      },
    );
  }
}
