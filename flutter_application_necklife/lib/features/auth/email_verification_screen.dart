// =============================================================================
// NeckLife — Écran de vérification d'adresse email
// Affiché tant que l'email du compte n'a pas été confirmé via le lien
// envoyé par Firebase Auth (voir main.dart : gardé par userChanges())
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();

  bool _envoiEnCours = false;
  bool _verificationEnCours = false;
  String? _message;

  // ---------------------------------------------------------------------------
  // Renvoie l'email de confirmation
  // ---------------------------------------------------------------------------
  Future<void> _renvoyerEmail() async {
    setState(() => _envoiEnCours = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) setState(() => _message = 'Email renvoyé.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Recharge l'utilisateur et vérifie emailVerified — si confirmé, le
  // StreamBuilder de main.dart (userChanges) bascule automatiquement vers
  // l'accueil, rien d'autre à faire ici
  // ---------------------------------------------------------------------------
  Future<void> _verifier() async {
    setState(() {
      _verificationEnCours = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      if (mounted && FirebaseAuth.instance.currentUser?.emailVerified != true) {
        setState(() => _message = 'Email pas encore confirmé. Vérifiez votre boîte de réception.');
      }
    } finally {
      if (mounted) setState(() => _verificationEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 64, color: Color(0xFFF68FFA)),
                const SizedBox(height: 16),
                const Text(
                  'Vérifiez votre email',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Un lien de confirmation a été envoyé à $email. '
                  'Cliquez dessus puis revenez ici.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                // Combinaison fond/texte reprenant le couple accessible
                // Bootstrap "warning" (#fff3cd / #856404, ≈5:1, WCAG AA)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFE69C)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFF856404)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Pensez à vérifier vos spams / courriers indésirables.',
                          style: TextStyle(
                            color: Color(0xFF856404),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _verificationEnCours ? null : _verifier,
                  child: _verificationEnCours
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('J\'ai vérifié, continuer'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _envoiEnCours ? null : _renvoyerEmail,
                  child: const Text('Renvoyer l\'email'),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => _authService.deconnecter(),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
