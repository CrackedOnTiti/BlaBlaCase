import '../../core/theme/app_theme.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';

class TripCreateScreen extends StatefulWidget {
  const TripCreateScreen({super.key});

  @override
  State<TripCreateScreen> createState() => _TripCreateScreenState();
}

class _TripCreateScreenState extends State<TripCreateScreen> {
  final _notesController = TextEditingController();

  // City
  String _cityName = '';
  double? _lat, _lng;

  // Date & times — always the same calendar day
  DateTime? _tripDate;
  TimeOfDay? _departTime;
  TimeOfDay? _returnTime;

  int _seats = 3;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // ── Date & time pickers ───────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _tripDate = picked;
      // Reset times when date changes
      _departTime = null;
      _returnTime = null;
    });
  }

  Future<void> _pickDepartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
    );
    if (picked == null) return;
    setState(() {
      _departTime = picked;
      // Invalidate return time if it's no longer after depart
      if (_returnTime != null && !_returnTimeIsAfterDepart(_returnTime!, picked)) {
        _returnTime = null;
      }
    });
  }

  Future<void> _pickReturnTime() async {
    if (_departTime == null) return; // button is disabled anyway
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (_departTime!.hour + 8).clamp(0, 23),
        minute: _departTime!.minute,
      ),
    );
    if (picked == null) return;
    if (!_returnTimeIsAfterDepart(picked, _departTime!)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('L\'heure de retour doit être après le départ.')),
        );
      }
      return;
    }
    setState(() => _returnTime = picked);
  }

  bool _returnTimeIsAfterDepart(TimeOfDay ret, TimeOfDay dep) {
    return ret.hour * 60 + ret.minute > dep.hour * 60 + dep.minute;
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Sélectionnez une ville de départ dans la liste.');
      return;
    }
    if (_tripDate == null) {
      setState(() => _error = 'Choisissez la date du trajet.');
      return;
    }
    if (_departTime == null) {
      setState(() => _error = 'Indiquez l\'heure de départ.');
      return;
    }
    if (_returnTime == null) {
      setState(() => _error = 'Indiquez l\'heure de retour prévue.');
      return;
    }

    final departAt = DateTime(
      _tripDate!.year, _tripDate!.month, _tripDate!.day,
      _departTime!.hour, _departTime!.minute,
    );
    final returnAt = DateTime(
      _tripDate!.year, _tripDate!.month, _tripDate!.day,
      _returnTime!.hour, _returnTime!.minute,
    );

    setState(() { _loading = true; _error = null; });
    try {
      await createApiClient().post('/trips', data: {
        'departure_city': _cityName,
        'departure_lat': _lat,
        'departure_lng': _lng,
        'depart_at': departAt.toUtc().toIso8601String(),
        'return_at': returnAt.toUtc().toIso8601String(),
        'seats_total': _seats,
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      });
      if (mounted) context.pop();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
    final timeFmt = DateFormat('HH:mm');

    String? formattedDate = _tripDate != null ? dateFmt.format(_tripDate!) : null;
    String? formattedDepart = _departTime != null
        ? timeFmt.format(DateTime(2000, 1, 1, _departTime!.hour, _departTime!.minute))
        : null;
    String? formattedReturn = _returnTime != null
        ? timeFmt.format(DateTime(2000, 1, 1, _returnTime!.hour, _returnTime!.minute))
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Proposer un trajet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── City ──────────────────────────────────────────────────────
            const Text('Ville de départ', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 6),
            Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue value) async {
                if (value.text.length < 3) return [];
                // Invalidate confirmed location when user types again
                if (_lat != null) setState(() { _lat = null; _lng = null; });
                try {
                  final url = Uri.parse(
                    'https://nominatim.openstreetmap.org/search'
                    '?q=${Uri.encodeComponent(value.text)}&countrycodes=fr'
                    '&format=json&limit=5&addressdetails=1',
                  );
                  final res = await http.get(url, headers: {'Accept-Language': 'fr'});
                  if (res.statusCode == 200) {
                    final data = jsonDecode(res.body) as List;
                    return data.map((e) => {
                      'label': e['display_name'] as String,
                      'short': (e['display_name'] as String).split(',').first.trim(),
                      'lat': double.parse(e['lat'] as String),
                      'lng': double.parse(e['lon'] as String),
                    }).toList();
                  }
                } catch (_) {}
                return [];
              },
              displayStringForOption: (s) => s['short'] as String,
              onSelected: (s) {
                setState(() {
                  _cityName = s['short'] as String;
                  _lat = s['lat'] as double;
                  _lng = s['lng'] as double;
                });
                FocusScope.of(context).unfocus();
              },
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (_, i) {
                        final s = options.elementAt(i);
                        return ListTile(
                          dense: true,
                          title: Text(s['short'] as String,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            (s['label'] as String).split(',').skip(1).take(2).join(',').trim(),
                            style: const TextStyle(fontSize: 11, color: Colors.white38),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => onSelected(s),
                        );
                      },
                    ),
                  ),
                ),
              ),
              fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: 'Toulouse, Lyon…',
                  border: const OutlineInputBorder(),
                  suffixIcon: _lat != null
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Date ──────────────────────────────────────────────────────
            const Text('Date du trajet', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 6),
            _Tile(
              icon: Icons.calendar_today,
              label: formattedDate ?? 'Choisir la date',
              confirmed: _tripDate != null,
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),

            // ── Times ─────────────────────────────────────────────────────
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Heure de départ', style: TextStyle(fontSize: 13, color: Colors.white54)),
                  const SizedBox(height: 6),
                  _Tile(
                    icon: Icons.flight_takeoff,
                    label: formattedDepart ?? 'Choisir',
                    confirmed: _departTime != null,
                    enabled: _tripDate != null,
                    onTap: _pickDepartTime,
                  ),
                ],
              )),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Heure de retour', style: TextStyle(fontSize: 13, color: Colors.white54)),
                  const SizedBox(height: 6),
                  _Tile(
                    icon: Icons.flight_land,
                    label: formattedReturn ?? 'Choisir',
                    confirmed: _returnTime != null,
                    enabled: _departTime != null,
                    onTap: _pickReturnTime,
                  ),
                ],
              )),
            ]),
            const SizedBox(height: 20),

            // ── Seats ─────────────────────────────────────────────────────
            const Text('Nombre de places (passagers)', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 8),
            Row(children: [
              IconButton(
                onPressed: () => setState(() => _seats = (_seats - 1).clamp(1, 8)),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_seats', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: () => setState(() => _seats = (_seats + 1).clamp(1, 8)),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Notes ─────────────────────────────────────────────────────
            const Text('Notes (optionnel)', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Point de rendez-vous, conditions particulières…',
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Publier le trajet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool confirmed;
  final bool enabled;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.label,
    required this.confirmed,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: confirmed ? kPrimary : kBorder),
          borderRadius: BorderRadius.circular(8),
          color: enabled ? null : Colors.white.withValues(alpha: 0.03),
        ),
        child: Row(children: [
          Icon(icon, size: 16,
              color: confirmed ? kPrimary : (enabled ? Colors.white54 : Colors.white24)),
          const SizedBox(width: 8),
          Expanded(child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: confirmed ? Colors.white : (enabled ? Colors.white54 : Colors.white24),
              fontWeight: confirmed ? FontWeight.w600 : FontWeight.normal,
            ),
          )),
          if (confirmed) const Icon(Icons.check_circle, size: 16, color: kPrimary),
        ]),
      ),
    );
  }
}
