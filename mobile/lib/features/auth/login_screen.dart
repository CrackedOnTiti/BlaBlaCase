import '../../core/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _verificationId;

  late AnimationController _anim;
  late Animation<double> _logoOpacity;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _formOpacity;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _logoOpacity = CurvedAnimation(
      parent: _anim, curve: const Interval(0.0, 0.4, curve: Curves.easeOut));
    _subtitleOpacity = CurvedAnimation(
      parent: _anim, curve: const Interval(0.35, 0.72, curve: Curves.easeOut));
    _formOpacity = CurvedAnimation(
      parent: _anim, curve: const Interval(0.65, 1.0, curve: Curves.easeOut));
    _anim.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _anim.dispose();
    super.dispose();
  }

  String _normalisePhone(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('0')) return '+33${digits.substring(1)}';
    return '+33$digits';
  }

  Future<void> _sendCode() async {
    setState(() { _loading = true; _error = null; });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _normalisePhone(_phoneController.text),
      verificationCompleted: (PhoneAuthCredential cred) async {
        await FirebaseAuth.instance.signInWithCredential(cred);
        // Router handles navigation via authStateChanges
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
      // Router handles navigation via authStateChanges
    } on FirebaseAuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Logo ────────────────────────────────────────────────────
              FadeTransition(
                opacity: _logoOpacity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900),
                        children: [
                          TextSpan(text: 'Bla', style: TextStyle(color: kPrimary)),
                          TextSpan(text: 'Bla', style: TextStyle(color: kAccent)),
                          TextSpan(text: 'Case'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('Covoiturage Pas de la Case',
                        style: TextStyle(color: Colors.white38, fontSize: 14)),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // ── Subtitle ────────────────────────────────────────────────
              if (!_codeSent)
                FadeTransition(
                  opacity: _subtitleOpacity,
                  child: const Text(
                    'Avant de planifier ton prochain trajet,\nmets ci-dessous ton numéro 👇',
                    style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.5),
                  ),
                ),

              const SizedBox(height: 28),

              // ── Form ────────────────────────────────────────────────────
              FadeTransition(
                opacity: _formOpacity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_codeSent) ...[
                      const Text('Numéro de téléphone',
                          style: TextStyle(fontSize: 13, color: Colors.white54)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          prefixText: '🇫🇷 +33  ',
                          hintText: '6 12 34 56 78',
                        ),
                      ),
                    ] else ...[
                      const Text('Code de vérification',
                          style: TextStyle(fontSize: 13, color: Colors.white54)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        decoration: const InputDecoration(hintText: '123456'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : (_codeSent ? _verifyCode : _sendCode),
                        child: _loading
                            ? const SizedBox(height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_codeSent ? 'Vérifier' : 'Continuer'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
