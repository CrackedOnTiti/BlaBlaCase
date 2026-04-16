import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _nameController = TextEditingController();
  bool _checking = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkExistingName();
  }

  Future<void> _checkExistingName() async {
    try {
      final res = await createApiClient().get('/users/me');
      final name = (res.data['display_name'] as String?) ?? '';
      if (name.isNotEmpty && mounted) {
        context.go('/home');
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Choisis un nom à afficher.');
      return;
    }
    if (name.length < 2) {
      setState(() => _error = 'Au moins 2 caractères.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await createApiClient().patch('/users/me', data: {'display_name': name});
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Apprenons à se\nconnaître un peu 👋',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.3),
              ),
              const SizedBox(height: 12),
              const Text(
                'Comment t\'appelles-tu ?',
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Prénom ou pseudo',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Le username est le biais par lequel les autres utilisateurs pourront te retrouver. '
                'Tu n\'es pas obligé de mettre tes données personnelles 👍',
                style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.5),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('C\'est parti !'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
