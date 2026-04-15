import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';

final tripDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, tripId) async {
    final res = await createApiClient().get('/trips/$tripId');
    return res.data as Map<String, dynamic>;
  },
);

class TripDetailScreen extends ConsumerWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('Trajet')),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (trip) => _TripDetailBody(trip: trip, tripId: tripId, ref: ref),
      ),
    );
  }
}

class _TripDetailBody extends StatefulWidget {
  final Map<String, dynamic> trip;
  final String tripId;
  final WidgetRef ref;

  const _TripDetailBody({required this.trip, required this.tripId, required this.ref});

  @override
  State<_TripDetailBody> createState() => _TripDetailBodyState();
}

class _TripDetailBodyState extends State<_TripDetailBody> {
  bool _showJoinForm = false;
  bool _joining = false;
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendJoinRequest() async {
    setState(() => _joining = true);
    final api = createApiClient();
    try {
      await api.post('/trips/${widget.tripId}/join');
      final msg = _messageController.text.trim();
      if (msg.isNotEmpty) {
        await api.post('/trips/${widget.tripId}/messages', data: {'content': msg});
      }
      widget.ref.invalidate(tripDetailProvider(widget.tripId));
      if (mounted) {
        setState(() { _showJoinForm = false; _joining = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demande envoyée au conducteur !')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _joining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final tripId = widget.tripId;
    final driver = trip['driver'] as Map<String, dynamic>;
    final fmt = DateFormat('EEEE d MMMM yyyy · HH:mm', 'fr_FR');
    final departAt = DateTime.parse(trip['depart_at'] as String).toLocal();
    final returnAt = DateTime.parse(trip['return_at'] as String).toLocal();
    final passengers = (trip['passengers'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route
          Row(children: [
            const Icon(Icons.location_on, color: kPrimary),
            const SizedBox(width: 8),
            Expanded(child: Text('${trip['departure_city']} → Pas de la Case → ${trip['departure_city']}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 16),

          // Dates
          _InfoRow(icon: Icons.flight_takeoff, label: 'Départ', value: fmt.format(departAt)),
          _InfoRow(icon: Icons.flight_land, label: 'Retour', value: fmt.format(returnAt)),
          _InfoRow(
            icon: Icons.event_seat,
            label: 'Places',
            value: '${trip['seats_available']}/${trip['seats_total']} disponibles',
          ),
          const SizedBox(height: 16),

          // Driver
          const Text('Conducteur', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => context.push('/profile/${driver['id']}'),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: kBorder,
                child: Text(driver['display_name'].toString()[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(driver['display_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  const Icon(Icons.star, size: 14, color: kAccent),
                  Text(' ${(driver['avg_rating'] as num).toStringAsFixed(1)} (${driver['rating_count']} avis)',
                      style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ]),
              ]),
            ]),
          ),
          const SizedBox(height: 20),

          if ((trip['notes'] as String?)?.isNotEmpty == true) ...[
            const Text('Notes', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            Text(trip['notes'] as String),
            const SizedBox(height: 20),
          ],

          // Passengers
          if (passengers.isNotEmpty) ...[
            const Text('Passagers', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            ...passengers.map((p) {
              final u = (p as Map)['user'] as Map<String, dynamic>;
              final s = p['status'] as String;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: kBorder,
                  child: Text(u['display_name'].toString()[0].toUpperCase()),
                ),
                title: Text(u['display_name'] as String),
                trailing: _StatusChip(status: s),
              );
            }),
            const SizedBox(height: 20),
          ],

          // Actions
          if (!_showJoinForm)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _showJoinForm = true),
                icon: const Icon(Icons.person_add),
                label: const Text('Demander à rejoindre'),
              ),
            )
          else ...[
            const Text('Message au conducteur (optionnel)',
                style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Présentez-vous, indiquez votre point de départ…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _joining ? null : () => setState(() => _showJoinForm = false),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _joining ? null : _sendJoinRequest,
                  child: _joining
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Envoyer la demande'),
                ),
              ),
            ]),
          ],

          const SizedBox(height: 12),
          const Text(
            'Les sélections d\'articles sont informelles et n\'ont aucun effet légal. '
            'Chaque voyageur est responsable de sa propre conformité douanière.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Text('$label : ', style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'accepted' => (Colors.green, 'Accepté'),
      'rejected' => (Colors.red, 'Refusé'),
      _ => (Colors.orange, 'En attente'),
    };
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.1),
      padding: EdgeInsets.zero,
    );
  }
}
