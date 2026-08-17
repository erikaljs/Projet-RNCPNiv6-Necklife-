// =============================================================================
// NeckLife — Écran de connexion / inscription
// Bascule entre les deux modes ; à l'inscription, un code de liaison est
// généré automatiquement pour chaque nouveau compte
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/auth/link_code_service.dart';
import '../../core/validation/text_validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final LinkCodeService _linkCodeService = LinkCodeService();
  final _formKey = GlobalKey<FormState>();

  final _controleurNom        = TextEditingController();
  final _controleurEmail      = TextEditingController();
  final _controleurMotDePasse = TextEditingController();

  bool _modeInscription = false;
  bool _chargement = false;
  String? _messageErreur;
  String? _codeGenere; // affiché après inscription réussie

  @override
  void dispose() {
    _controleurNom.dispose();
    _controleurEmail.dispose();
    _controleurMotDePasse.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Soumission du formulaire (connexion ou inscription selon le mode)
  // ---------------------------------------------------------------------------
  Future<void> _soumettre() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _chargement = true;
      _messageErreur = null;
    });

    try {
      if (_modeInscription) {
        await _inscrire();
      } else {
        await _authService.connecter(
          email: _controleurEmail.text.trim(),
          motDePasse: _controleurMotDePasse.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _messageErreur = _traduireErreur(e.code));
    } catch (e) {
      setState(() => _messageErreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Inscription : crée le compte et lui réserve un code de liaison unique,
  // permanent, à communiquer aux proches qui voudront le suivre
  // ---------------------------------------------------------------------------
  Future<void> _inscrire() async {
    final credential = await _authService.creerCompte(
      email: _controleurEmail.text.trim(),
      motDePasse: _controleurMotDePasse.text,
    );
    final uid = credential.user!.uid;
    await credential.user?.updateDisplayName(_controleurNom.text.trim());

    // Vérification native Firebase Auth — l'utilisateur doit confirmer son
    // email avant d'accéder à l'appli (voir email_verification_screen.dart)
    await credential.user?.sendEmailVerification();

    final code = await _linkCodeService.genererEtReserverCode(uid);

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'nom': _controleurNom.text.trim(),
      'email': _controleurEmail.text.trim(),
      'linkCode': code,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    setState(() => _codeGenere = code);
  }

  // ---------------------------------------------------------------------------
  // Dialogue de réinitialisation du mot de passe par email
  // ---------------------------------------------------------------------------
  Future<void> _ouvrirMotDePasseOublie() async {
    final controleurEmail = TextEditingController(text: _controleurEmail.text.trim());

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mot de passe oublié'),
        content: TextField(
          controller: controleurEmail,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'vous@exemple.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = controleurEmail.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(dialogContext);

              try {
                await _authService.reinitialiserMotDePasse(email);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email de réinitialisation envoyé.')),
                );
              } on FirebaseAuthException catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_traduireErreur(e.code))),
                );
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Traduit les codes d'erreur Firebase en messages compréhensibles
  // ---------------------------------------------------------------------------
  String _traduireErreur(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Cet email est déjà utilisé.';
      case 'invalid-email':
        return 'Adresse email invalide.';
      case 'weak-password':
        return 'Le mot de passe doit contenir au moins 6 caractères.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email ou mot de passe incorrect.';
      default:
        return 'Erreur : $code';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Écran affiché juste après l'inscription, pour montrer le code avant
    // de continuer vers l'accueil.
    if (_codeGenere != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_user, size: 64, color: Color(0xFFF68FFA)),
                  const SizedBox(height: 16),
                  const Text(
                    'Votre code personnel',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Communiquez ce code aux proches que vous souhaitez\n'
                    'autoriser à recevoir vos alertes. Il ne changera jamais.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF68FFA).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF68FFA)),
                    ),
                    child: Text(
                      _codeGenere!,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => setState(() => _codeGenere = null),
                    child: const Text('Continuer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.favorite, size: 64, color: Color(0xFFF68FFA)),
                  const SizedBox(height: 12),
                  Text(
                    'NeckLife',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _modeInscription ? 'Créer un compte' : 'Se connecter',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 32),

                  if (_modeInscription) ...[
                    TextFormField(
                      controller: _controleurNom,
                      decoration: const InputDecoration(
                        labelText: 'Nom complet',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: validerNomPrenom,
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _controleurEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Champ requis';
                      if (!v.contains('@')) return 'Email invalide';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _controleurMotDePasse,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Champ requis';
                      if (v.length < 6) return 'Minimum 6 caractères';
                      return null;
                    },
                  ),

                  if (_messageErreur != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _messageErreur!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _chargement ? null : _soumettre,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _chargement
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_modeInscription ? 'Créer mon compte' : 'Se connecter'),
                  ),

                  if (!_modeInscription) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _chargement ? null : _ouvrirMotDePasseOublie,
                      child: const Text('Mot de passe oublié ?'),
                    ),
                  ],

                  const SizedBox(height: 4),

                  TextButton(
                    onPressed: _chargement
                        ? null
                        : () => setState(() {
                              _modeInscription = !_modeInscription;
                              _messageErreur = null;
                            }),
                    child: Text(
                      _modeInscription
                          ? 'Déjà un compte ? Se connecter'
                          : 'Pas encore de compte ? Créer un compte',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
