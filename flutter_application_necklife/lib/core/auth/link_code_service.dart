// =============================================================================
// NeckLife — Service de liaison utilisateur / aidant par code
// Génère des codes uniques et gère les liens entre comptes
// =============================================================================

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

class LinkCodeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Caractères sans ambiguïté visuelle (pas de 0/O, 1/I/L)
  static const String _caracteres = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int _longueurCode = 6;

  String _genererCodeAleatoire() {
    final rnd = Random.secure();
    return List.generate(
      _longueurCode,
      (_) => _caracteres[rnd.nextInt(_caracteres.length)],
    ).join();
  }

  // ---------------------------------------------------------------------------
  // Génère un code unique et le réserve pour cet utilisateur (transaction
  // pour éviter deux comptes avec le même code en cas de collision rare)
  // ---------------------------------------------------------------------------
  Future<String> genererEtReserverCode(String uid) async {
    for (int tentative = 0; tentative < 5; tentative++) {
      final code = _genererCodeAleatoire();
      final ref = _firestore.collection('linkCodes').doc(code);

      final reserve = await _firestore.runTransaction<bool>((tx) async {
        final snapshot = await tx.get(ref);
        if (snapshot.exists) return false; // collision, on retente
        tx.set(ref, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
        return true;
      });

      if (reserve) return code;
    }
    throw Exception('Impossible de générer un code unique, réessayez.');
  }

  // ---------------------------------------------------------------------------
  // Vérifie qu'un code existe et retourne l'uid de l'utilisateur associé
  // ---------------------------------------------------------------------------
  Future<String?> verifierCode(String code) async {
    final doc = await _firestore
        .collection('linkCodes')
        .doc(code.trim().toUpperCase())
        .get();
    if (!doc.exists) return null;
    return doc.data()?['uid'] as String?;
  }

  // ---------------------------------------------------------------------------
  // Crée une demande de suivi en attente (followerUid veut suivre followedUid).
  // Doit être acceptée par followedUid avant de donner accès à ses alertes.
  //
  // ID de document déterministe ({followerUid}_{followedUid}) plutôt qu'un
  // ID auto-généré : les règles de sécurité Firestore ne peuvent vérifier
  // l'existence d'un lien accepté qu'avec exists()/get() sur un chemin
  // connu à l'avance (voir firebase_rules.json, fonction estSuiviAccepte).
  // ---------------------------------------------------------------------------
  Future<void> creerDemande({
    required String followerUid,
    required String followedUid,
    required String followerNom,
  }) async {
    await _firestore.collection('links').doc('${followerUid}_$followedUid').set({
      'followerUid': followerUid,
      'followedUid': followedUid,
      'followerNom': followerNom,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Accepte une demande de suivi reçue
  // ---------------------------------------------------------------------------
  Future<void> accepterLien(String linkId) async {
    await _firestore.collection('links').doc(linkId).update({'status': 'accepted'});
  }

  // ---------------------------------------------------------------------------
  // Refuse une demande de suivi reçue (suppression directe, plus simple
  // qu'un statut 'declined' à nettoyer plus tard)
  // ---------------------------------------------------------------------------
  Future<void> refuserLien(String linkId) async {
    await _firestore.collection('links').doc(linkId).delete();
  }

  // ---------------------------------------------------------------------------
  // Demandes de suivi en attente reçues par cet utilisateur
  // ---------------------------------------------------------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> ecouterDemandesEnAttente(String uid) {
    return _firestore
        .collection('links')
        .where('followedUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  // ---------------------------------------------------------------------------
  // Proches suivis par cet utilisateur (liens acceptés), enrichis des
  // infos de base du compte suivi
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> ecouterProchesSuivis(String uid) {
    return _firestore
        .collection('links')
        .where('followerUid', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .asyncMap((snap) async {
      final proches = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final followedUid = doc.data()['followedUid'] as String;
        final userDoc = await _firestore.collection('users').doc(followedUid).get();
        final data = userDoc.data();
        proches.add({
          'linkId': doc.id,
          'uid': followedUid,
          'nom': data?['nom'] as String? ?? 'Proche',
          'telephone': data?['telephone'] as String?,
          'contactsUrgence': data?['contactsUrgence'] as List<dynamic>? ?? [],
        });
      }
      return proches;
    });
  }

  // ---------------------------------------------------------------------------
  // fallEvents récents (<72h) des proches suivis, non encore confirmés par
  // leur porteur ("Je vais bien") — utilisé côté aidant pour la popup de
  // chute et pour garder la carte du proche en rouge tant que non confirmé.
  // La confirmation (confirmeParPorteur != true) est filtrée côté Dart plutôt
  // qu'en requête Firestore pour rester cohérent avec _ecouterHistoriqueChutes
  // (voir home_screen.dart) et éviter de combiner whereIn avec un opérateur !=.
  // ---------------------------------------------------------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> ecouterChutesNonConfirmees(
    List<String> uidsSuivis,
  ) {
    final depuis = DateTime.now().subtract(const Duration(hours: 72));
    return _firestore
        .collection('fallEvents')
        .where('uid', whereIn: uidsSuivis)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(depuis))
        .snapshots();
  }

  // ---------------------------------------------------------------------------
  // Libère un code (à appeler lors de la suppression d'un compte)
  // ---------------------------------------------------------------------------
  Future<void> libererCode(String code) async {
    await _firestore.collection('linkCodes').doc(code).delete();
  }
}
