import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import 'trip_list_screen.dart' show myUserProvider;

// ── Provider ──────────────────────────────────────────────────────────────

final myTripsFullProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await createApiClient().get('/trips/mine/full');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Screen ────────────────────────────────────────────────────────────────

class MyTripsScreen extends ConsumerWidget {
  const MyTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsFullProvider);
    final myId = ref.watch(myUserProvider).valueOrNull?['id'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Mes trajets')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myTripsFullProvider);
          await ref.read(myTripsFullProvider.future);
        },
        child: tripsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur: $e')),
          data: (trips) {
            if (trips.isEmpty) {
              return const CustomScrollView(slivers: [
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Aucun trajet pour le moment.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ]);
            }

            final driverTrips = trips.where((t) =>
                (t['driver'] as Map)['id'] as String == myId).toList();
            final passengerTrips = trips.where((t) =>
                (t['driver'] as Map)['id'] as String != myId).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (driverTrips.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'Conducteur',
                    icon: Icons.drive_eta_outlined,
                    count: driverTrips.length,
                  ),
                  const SizedBox(height: 8),
                  ...driverTrips.map((t) => _MyTripCard(trip: t, role: 'Conducteur')),
                ],
                if (driverTrips.isNotEmpty && passengerTrips.isNotEmpty)
                  const SizedBox(height: 8),
                if (passengerTrips.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'Passager',
                    icon: Icons.airline_seat_recline_normal_outlined,
                    count: passengerTrips.length,
                  ),
                  const SizedBox(height: 8),
                  ...passengerTrips.map((t) => _MyTripCard(trip: t, role: 'Passager')),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  const _SectionHeader({required this.label, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: kAccent),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: kAccent, letterSpacing: 0.5),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 11, color: kAccent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── Trip card ─────────────────────────────────────────────────────────────

class _MyTripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final String role;
  const _MyTripCard({required this.trip, required this.role});

  @override
  Widget build(BuildContext context) {
    final driver = trip['driver'] as Map<String, dynamic>;
    final departAt = DateTime.parse(trip['depart_at'] as String).toLocal();
    final returnAt = DateTime.parse(trip['return_at'] as String).toLocal();
    final fmt = DateFormat('EEE d MMM · HH:mm', 'fr_FR');
    final fmtReturn = DateFormat('d MMM · HH:mm', 'fr_FR');
    final tripStatus = trip['status'] as String;
    final isDriver = role == 'Conducteur';

    Color statusColor;
    String statusLabel;
    switch (tripStatus) {
      case 'open':
        statusColor = Colors.green;
        statusLabel = 'Ouvert';
      case 'full':
        statusColor = kAccent;
        statusLabel = 'Complet';
      case 'completed':
        statusColor = Colors.white38;
        statusLabel = 'Terminé';
      default:
        statusColor = Colors.redAccent;
        statusLabel = tripStatus;
    }

    final passengers = trip['passengers'] as List;
    final acceptedCount = passengers.where((p) => p['status'] == 'accepted').length;
    final pendingCount = passengers.where((p) => p['status'] == 'pending').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDriver ? const Color(0xFF0D2A3D) : null,
      shape: isDriver
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
              // Role badge + status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDriver
                          ? kPrimary.withValues(alpha: 0.4)
                          : kSurface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDriver ? Icons.drive_eta_outlined : Icons.airline_seat_recline_normal_outlined,
                          size: 12,
                          color: isDriver ? kAccent : Colors.white54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          role,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDriver ? kAccent : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Route
              Row(children: [
                const Icon(Icons.location_on, size: 16, color: kPrimary),
                const SizedBox(width: 4),
                Text(
                  trip['departure_city'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const Text(' → Pas de la Case'),
              ]),
              const SizedBox(height: 4),

              // Dates
              Row(children: [
                const Icon(Icons.arrow_upward, size: 12, color: Colors.white38),
                const SizedBox(width: 4),
                Text(fmt.format(departAt),
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.arrow_downward, size: 12, color: Colors.white38),
                const SizedBox(width: 4),
                Text(fmtReturn.format(returnAt),
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
              const SizedBox(height: 12),

              // Bottom row: driver info + passengers
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!isDriver)
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
                  if (isDriver) const SizedBox.shrink(),
                  Row(children: [
                    const Icon(Icons.event_seat, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      '$acceptedCount/${trip['seats_total']} passagers',
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    if (isDriver && pendingCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$pendingCount en attente',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),

              // Notes
              if (trip['notes'] != null && (trip['notes'] as String).isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder),
                  ),
                  child: Text(
                    trip['notes'] as String,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
