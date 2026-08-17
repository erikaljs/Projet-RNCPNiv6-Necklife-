// =============================================================================
// NeckLife — Service d'authentification Firebase
// Login / logout / récupération du token JWT pour les appels API
// Package : firebase_auth
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream exposant l'état de connexion en temps réel — userChanges() (et
  // non authStateChanges()) pour aussi réagir à user.reload() (nécessaire à
  // l'écran de vérification d'email, voir email_verification_screen.dart)
  Stream<User?> get etatConnexion => _auth.userChanges();

  // Utilisateur actuellement connecté (null si déconnecté)
  User? get utilisateurCourant => _auth.currentUser;

  bool get estConnecte => utilisateurCourant != null;

  // ---------------------------------------------------------------------------
  // Connexion par email / mot de passe
  // ---------------------------------------------------------------------------
  Future<UserCredential> connecter({
    required String email,
    required String motDePasse,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: motDePasse,
    );
  }

  // ---------------------------------------------------------------------------
  // Création d'un nouveau compte
  // ---------------------------------------------------------------------------
  Future<UserCredential> creerCompte({
    required String email,
    required String motDePasse,
  }) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: motDePasse,
    );
  }

  // ---------------------------------------------------------------------------
  // Déconnexion
  // ---------------------------------------------------------------------------
  Future<void> deconnecter() async {
    await _auth.signOut();
  }

  // ---------------------------------------------------------------------------
  // Récupère le token JWT Firebase (rafraîchi automatiquement si expiré)
  // Utilisé par ApiClient pour les appels backend authentifiés
  // ---------------------------------------------------------------------------
  Future<String?> obtenirToken() async {
    return await utilisateurCourant?.getIdToken();
  }

  // ---------------------------------------------------------------------------
  // Réinitialisation du mot de passe par email
  // ---------------------------------------------------------------------------
  Future<void> reinitialiserMotDePasse(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ---------------------------------------------------------------------------
  // Ré-authentification — requise par Firebase avant de changer l'email ou
  // le mot de passe, pour des raisons de sécurité
  // ---------------------------------------------------------------------------
  Future<void> reauthentifier(String motDePasseActuel) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: motDePasseActuel,
    );
    await user.reauthenticateWithCredential(credential);
  }

  // ---------------------------------------------------------------------------
  // Change l'email — envoie un email de confirmation à la nouvelle adresse ;
  // l'email Firebase Auth n'est mis à jour qu'après validation du lien
  // ---------------------------------------------------------------------------
  Future<void> changerEmail(String nouvelEmail) async {
    await _auth.currentUser?.verifyBeforeUpdateEmail(nouvelEmail);
  }

  // ---------------------------------------------------------------------------
  // Change le mot de passe
  // ---------------------------------------------------------------------------
  Future<void> changerMotDePasse(String nouveauMotDePasse) async {
    await _auth.currentUser?.updatePassword(nouveauMotDePasse);
  }
}
