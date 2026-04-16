import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../notifications/notifications_screen.dart' show notificationsProvider;

// ── Providers ──────────────────────────────────────────────────────────────

final tripsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = createApiClient();
  final res = await dio.get('/trips');
  return List<Map<String, dynamic>>.from(res.data as List);
});

final myUserProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await createApiClient().get('/users/me');
  return Map<String, dynamic>.from(res.data as Map);
});

// ── AdMob banner ──────────────────────────────────────────────────────────

// Use test ad unit ID during development.
// Replace with real ID from AdMob console before release.
const String _bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111'; // test ID

class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget();

  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  BannerAd? _ad;
  bool _adLoaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _adLoaded = true),
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
    if (!_adLoaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────

class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(tripsProvider);
    final myId = ref.watch(myUserProvider).valueOrNull?['id'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            children: [
              TextSpan(text: 'Bla', style: TextStyle(color: kPrimary)),
              TextSpan(text: 'Bla', style: TextStyle(color: kAccent)),
              TextSpan(text: 'Case'),
            ],
          ),
        ),
        actions: [
          _BellIcon(),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Mon profil',
            onPressed: () => context.push('/me'),
          ),
        ],
      ),
      body: Column(
        children: [
          const _BannerAdWidget(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(tripsProvider);
                ref.invalidate(myUserProvider);
                await ref.read(tripsProvider.future);
              },
              child: tripsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e')),
                data: (trips) {
                  final myTrips = trips.where((t) {
                    if ((t['driver']['id'] as String) == myId) return true;
                    final passengers = t['passengers'] as List;
                    return passengers.any((p) =>
                        (p['user']['id'] as String) == myId &&
                        (p['status'] as String) == 'accepted');
                  }).toList();
                  final otherTrips = trips.where((t) => !myTrips.contains(t)).toList();

                  if (trips.isEmpty) {
                    return const CustomScrollView(slivers: [
                      SliverFillRemaining(
                        child: Center(child: Text('Aucun trajet disponible.')),
                      ),
                    ]);
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (myTrips.isNotEmpty) ...[
                        const _SectionHeader(label: 'Mes futurs trajets', icon: Icons.directions_car),
                        const SizedBox(height: 8),
                        ...myTrips.map((t) => _TripCard(trip: t, mine: true)),
                      ],
                      if (myTrips.isNotEmpty && otherTrips.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: _BannerAdWidget(),
                        ),
                      if (otherTrips.isNotEmpty) ...[
                        const _SectionHeader(label: 'Autres trajets', icon: Icons.explore_outlined),
                        const SizedBox(height: 8),
                        ...otherTrips.map((t) => _TripCard(trip: t)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: SpeedDial(
        icon: Icons.menu,
        activeIcon: Icons.close,
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        spacing: 12,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.calculate_outlined),
            label: 'Calculateur',
            backgroundColor: kSurface,
            foregroundColor: kAccent,
            labelStyle: const TextStyle(fontSize: 13),
            onTap: () => context.push('/calculator'),
          ),
          SpeedDialChild(
            child: const Icon(Icons.add),
            label: 'Proposer un trajet',
            backgroundColor: kSurface,
            foregroundColor: kAccent,
            labelStyle: const TextStyle(fontSize: 13),
            onTap: () async {
              await context.push('/home/create');
              ref.invalidate(tripsProvider);
            },
          ),
        ],
      ),
    );
  }
}

// ── Bell icon with red dot ────────────────────────────────────────────────

class _BellIcon extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(notificationsProvider).valueOrNull?.length ?? 0;
    return IconButton(
      tooltip: 'Demandes',
      onPressed: () => context.push('/notifications'),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (count > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Section widgets ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: kAccent),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: kAccent, letterSpacing: 0.5)),
      ],
    );
  }
}

// ── Trip card ────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final bool mine;
  const _TripCard({required this.trip, this.mine = false});

  @override
  Widget build(BuildContext context) {
    final driver = trip['driver'] as Map<String, dynamic>;
    final departAt = DateTime.parse(trip['depart_at'] as String).toLocal();
    final fmt = DateFormat('EEE d MMM · HH:mm', 'fr_FR');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: mine ? const Color(0xFF0D2A3D) : null,
      shape: mine
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kPrimary, width: 1),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/trip/${trip['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: kPrimary),
                  const SizedBox(width: 4),
                  Text(trip['departure_city'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const Text(' → Pas de la Case'),
                ],
              ),
              const SizedBox(height: 4),
              Text(fmt.format(departAt), style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Icon(Icons.person, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(driver['display_name'] as String,
                        style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(width: 4),
                    const Icon(Icons.star, size: 12, color: kAccent),
                    Text(
                      (driver['avg_rating'] as num).toStringAsFixed(1),
                      style: const TextStyle(fontSize: 12, color: kAccent),
                    ),
                  ]),
                  Row(children: [
                    const Icon(Icons.event_seat, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text('${trip['seats_available']}/${trip['seats_total']} places',
                        style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
