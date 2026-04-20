import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';

final allowancesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await createApiClient().get('/allowances');
  return res.data as Map<String, dynamic>;
});

class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});

  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  int _adults = 1, _minors = 0, _children = 0;

  @override
  Widget build(BuildContext context) {
    final allowancesAsync = ref.watch(allowancesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculateur douane'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            onPressed: () {
              debugPrint('>>> invalidating allowancesProvider');
              ref.invalidate(allowancesProvider);
              debugPrint('>>> provider state after invalidate: ${ref.read(allowancesProvider)}');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Counters
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Counter(label: 'Adultes', value: _adults, min: 1,
                    onChanged: (v) => setState(() => _adults = v)),
                _Counter(label: 'Mineurs\n15–17 ans', value: _minors,
                    onChanged: (v) => setState(() => _minors = v)),
                _Counter(label: 'Enfants\n< 15 ans', value: _children,
                    onChanged: (v) => setState(() => _children = v)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: allowancesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Impossible de charger les données.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.invalidate(allowancesProvider),
                    child: const Text('Réessayer'),
                  ),
                ]),
              ),
              data: (data) {
                final items = (data['items'] as List).cast<Map<String, dynamic>>();
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final adultQty = (item['per_adult'] as num).toDouble();
                    final minorQty = item['per_minor'] != null ? (item['per_minor'] as num).toDouble() : null;
                    final childQty = item['per_child'] != null ? (item['per_child'] as num).toDouble() : null;
                    final unit = item['unit'] as String;
                    final total = adultQty * _adults +
                        (minorQty ?? 0) * _minors +
                        (childQty ?? 0) * _children;

                    return ListTile(
                      title: Text(item['label'] as String, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        'Adulte: $adultQty $unit'
                        '${minorQty != null ? ' · Mineur: $minorQty $unit' : ' · Mineur: interdit'}',
                        style: const TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${total % 1 == 0 ? total.toInt() : total} $unit',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: kAccent,
                            ),
                          ),
                          const Text('total groupe', style: TextStyle(fontSize: 10, color: Colors.white38)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text(
                  'Informations à titre indicatif. Chaque voyageur est responsable de sa conformité douanière.',
                  style: TextStyle(fontSize: 10, color: Colors.white38),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://www.douane.gouv.fr/passer-la-douane-en-andorre-taxes-et-franchises'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text(
                    'Consulter la source officielle — douane.gouv.fr',
                    style: TextStyle(fontSize: 10, color: Colors.blue, decoration: TextDecoration.underline),
                    textAlign: TextAlign.center,
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

class _Counter extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final void Function(int) onChanged;
  const _Counter({required this.label, required this.value, this.min = 0, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
      ],
    );
  }
}
