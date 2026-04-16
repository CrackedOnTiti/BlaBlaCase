import '../../core/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

final myProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await createApiClient().get('/users/me');
  return res.data as Map<String, dynamic>;
});

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  late TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await createApiClient().patch('/users/me', data: {'display_name': name});
      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nom mis à jour !')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAvatarComingSoon() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Photo de profil'),
        content: const Text('Comming soon'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    // Step 1
    final step1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le compte'),
        content: const Text(
          'C\'ette action est permanente. On ne fait pas de backups, '
          'sûr ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    // Step 2 — humorous second confirmation
    final step2 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('sûr sûr ?'),
        content: const Text(
          'T\'es sûr sûr sûr sûr sûr sûr sûr sûr sûr sûr sûr sûr...?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non je garde mon compte'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Ta gueule'),
          ),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    try {
      await createApiClient().delete('/users/me');
      await FirebaseAuth.instance.signOut();
      // Router will redirect to /login via auth state change
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (user) {
          // Pre-fill name field only on first load
          if (_nameController.text.isEmpty) {
            _nameController.text = user['display_name'] as String;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Avatar ──────────────────────────────────────────────
                Center(
                  child: GestureDetector(
                    onTap: _showAvatarComingSoon,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: kBorder,
                          child: user['avatar_url'] != null
                              ? ClipOval(child: Image.network(
                                  user['avatar_url'] as String,
                                  width: 104, height: 104, fit: BoxFit.cover,
                                ))
                              : ClipOval(child: Image.asset(
                                  'assets/logo.png',
                                  width: 104, height: 104, fit: BoxFit.cover,
                                )),
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: kPrimary,
                              shape: BoxShape.circle,
                              border: Border.all(color: kBackground, width: 2),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 14, color: kAccent),
                      const SizedBox(width: 4),
                      Text(
                        '${(user['avg_rating'] as num).toStringAsFixed(1)} '
                        '(${user['rating_count']} avis)',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Display name ─────────────────────────────────────────
                const Text('Nom affiché',
                    style: TextStyle(fontSize: 13, color: Colors.white54)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Ton prénom ou pseudo',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _saveName,
                    child: _saving
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sauvegarder'),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Phone ────────────────────────────────────────────────
                const Text('Numéro de téléphone',
                    style: TextStyle(fontSize: 13, color: Colors.white54)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: kBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    (user['phone'] as String?) ?? '—',
                    style: const TextStyle(fontSize: 15, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Mes trajets ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: navigate to my trips screen
                    },
                    icon: const Icon(Icons.directions_car_outlined),
                    label: const Text('Mes trajets'),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Logout ───────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Se déconnecter'),
                  ),
                ),
                const SizedBox(height: 48),

                // ── Delete account ───────────────────────────────────────
                const Divider(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _deleteAccount,
                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                    label: const Text('Supprimer le compte',
                        style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
