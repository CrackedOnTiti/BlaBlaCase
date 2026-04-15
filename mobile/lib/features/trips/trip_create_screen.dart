import '../../core/theme/app_theme.dart';
import 'dart:async';
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
  final _cityController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _departAt;
  DateTime? _returnAt;
  int _seats = 3;
  double? _lat, _lng;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _cityController.dispose();
    _notesController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onCityChanged(String query) {
    _debounce?.cancel();
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&countrycodes=fr&format=json&limit=5&addressdetails=1',
      );
      final res = await http.get(url, headers: {'Accept-Language': 'fr'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        setState(() {
          _suggestions = data
              .map((e) => {
                    'label': e['display_name'] as String,
                    'lat': double.parse(e['lat'] as String),
                    'lng': double.parse(e['lon'] as String),
                  })
              .toList();
        });
      }
    });
  }

  void _selectSuggestion(Map<String, dynamic> s) {
    setState(() {
      _cityController.text = (s['label'] as String).split(',').first.trim();
      _lat = s['lat'] as double;
      _lng = s['lng'] as double;
      _suggestions = [];
    });
  }

  Future<void> _pickDateTime({required bool isDepart}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => isDepart ? _departAt = dt : _returnAt = dt);
  }

  Future<void> _submit() async {
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Sélectionnez une ville de départ.');
      return;
    }
    if (_departAt == null || _returnAt == null) {
      setState(() => _error = 'Renseignez les dates de départ et de retour.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await createApiClient().post('/trips', data: {
        'departure_city': _cityController.text.trim(),
        'departure_lat': _lat,
        'departure_lng': _lng,
        'depart_at': _departAt!.toUtc().toIso8601String(),
        'return_at': _returnAt!.toUtc().toIso8601String(),
        'seats_total': _seats,
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      });
      if (mounted) context.pop();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE d MMM · HH:mm', 'fr_FR');
    return Scaffold(
      appBar: AppBar(title: const Text('Proposer un trajet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ville de départ', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 6),
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(
                hintText: 'Toulouse, Lyon…',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.search),
              ),
              onChanged: _onCityChanged,
            ),
            if (_suggestions.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 4),
                child: Column(
                  children: _suggestions.map((s) => ListTile(
                    title: Text(s['label'] as String, style: const TextStyle(fontSize: 13)),
                    onTap: () => _selectSuggestion(s),
                  )).toList(),
                ),
              ),
            const SizedBox(height: 20),

            Row(children: [
              Expanded(child: _DateTile(
                icon: Icons.flight_takeoff,
                label: 'Départ',
                value: _departAt != null ? fmt.format(_departAt!) : null,
                onTap: () => _pickDateTime(isDepart: true),
              )),
              const SizedBox(width: 12),
              Expanded(child: _DateTile(
                icon: Icons.flight_land,
                label: 'Retour',
                value: _returnAt != null ? fmt.format(_returnAt!) : null,
                onTap: () => _pickDateTime(isDepart: false),
              )),
            ]),
            const SizedBox(height: 20),

            const Text('Nombre de places (passagers)', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.start, children: [
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

class _DateTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  const _DateTile({required this.icon, required this.label, this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 14, color: Colors.white38), const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38))]),
          const SizedBox(height: 4),
          Text(value ?? 'Choisir', style: TextStyle(
            fontSize: 13,
            color: value != null ? Colors.white : Colors.white38,
            fontWeight: value != null ? FontWeight.w600 : FontWeight.normal,
          )),
        ]),
      ),
    );
  }
}
