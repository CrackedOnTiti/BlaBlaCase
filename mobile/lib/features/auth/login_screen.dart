import '../../core/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _verificationId;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String _normalisePhone(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (digits.startsWith('+')) return digits;          // already E.164
    if (digits.startsWith('0')) return '+33${digits.substring(1)}';
    return '+33$digits';
  }

  Future<void> _sendCode() async {
    setState(() { _loading = true; _error = null; });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _normalisePhone(_phoneController.text),
      verificationCompleted: (PhoneAuthCredential cred) async {
        await FirebaseAuth.instance.signInWithCredential(cred);
        if (mounted) context.go('/home');
      },
      verificationFailed: (e) {
        setState(() { _error = e.message; _loading = false; });
      },
      codeSent: (verificationId, _) {
        setState(() { _verificationId = verificationId; _codeSent = true; _loading = false; });
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _verifyCode() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _codeController.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900),
                  children: [
                    TextSpan(text: 'Bla', style: TextStyle(color: kPrimary)),
                    TextSpan(text: 'Bla', style: TextStyle(color: kAccent)),
                    TextSpan(text: 'Case'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('Covoiturage Pas de la Case', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 48),
              if (!_codeSent) ...[
                const Text('Numéro de téléphone', style: TextStyle(fontSize: 13, color: Colors.white54)),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    prefixText: '🇫🇷 +33  ',
                    hintText: '6 12 34 56 78',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                const Text('Code de vérification', style: TextStyle(fontSize: 13, color: Colors.white54)),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '123456',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : (_codeSent ? _verifyCode : _sendCode),
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_codeSent ? 'Vérifier' : 'Envoyer le code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
