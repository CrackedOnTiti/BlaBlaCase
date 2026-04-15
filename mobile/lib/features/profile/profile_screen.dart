import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

final userProfileProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    final res = await createApiClient().get('/users/$userId');
    return res.data as Map<String, dynamic>;
  },
);

class ProfileScreen extends ConsumerWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(userId));

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (user) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: kBorder,
                  child: Text(
                    (user['display_name'] as String)[0].toUpperCase(),
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 16),
                Text(user['display_name'] as String,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.star, color: kAccent, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${(user['avg_rating'] as num).toStringAsFixed(1)} '
                    '(${user['rating_count']} avis)',
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ]),
                const SizedBox(height: 32),
                // Rating count visual
                if ((user['rating_count'] as int) == 0)
                  const Text('Aucun avis pour le moment.',
                      style: TextStyle(color: Colors.white38)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
