import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

final notificationsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await createApiClient().get('/trips/notifications');
  return List<Map<String, dynamic>>.from(res.data as List);
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Demandes')),
      body: notifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (notifs) => notifs.isEmpty
            ? const Center(
                child: Text('Aucune demande en attente.', style: TextStyle(color: Colors.white54)),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(notificationsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RequestCard(notif: notifs[i], ref: ref),
                ),
              ),
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  final Map<String, dynamic> notif;
  final WidgetRef ref;
  const _RequestCard({required this.notif, required this.ref});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _loading = false;

  Future<void> _respond(String status) async {
    setState(() => _loading = true);
    try {
      final tripId = widget.notif['trip_id'] as String;
      final userId = (widget.notif['passenger'] as Map)['id'] as String;
      await createApiClient().patch('/trips/$tripId/passengers/$userId', data: {'status': status});
      widget.ref.invalidate(notificationsProvider);
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
    final fmt = DateFormat('EEE d MMM · HH:mm', 'fr_FR');
    final introMessage = widget.notif['intro_message'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Passenger info
            Row(children: [
              CircleAvatar(
                backgroundColor: kBorder,
                child: Text(passenger['display_name'].toString().isNotEmpty ? passenger['display_name'].toString()[0].toUpperCase() : '?'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(passenger['display_name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Row(children: [
                    const Icon(Icons.star, size: 12, color: kAccent),
                    Text(' ${(passenger['avg_rating'] as num).toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ]),
                ]),
              ),
              GestureDetector(
                onTap: () => context.push('/trip/${widget.notif['trip_id']}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(city, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  Text(fmt.format(departAt),
                      style: const TextStyle(fontSize: 11, color: Colors.white38)),
                ]),
              ),
            ]),
            if (introMessage != null && introMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSurface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder),
                ),
                child: Text(introMessage,
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
              ),
            ],
            const SizedBox(height: 14),
            // Accept / Reject buttons
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _respond('rejected'),
                        icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                        label: const Text('Refuser', style: TextStyle(color: Colors.redAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _respond('accepted'),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Accepter'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ),
                  ]),
          ],
        ),
      ),
    );
  }
}
