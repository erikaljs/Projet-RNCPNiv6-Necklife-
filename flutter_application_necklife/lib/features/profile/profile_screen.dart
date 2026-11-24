// =============================================================================
// NeckLife — Écran profil utilisateur
// Affiche/édite les infos du compte + code de liaison (si utilisateur) +
// gestion des contacts d'urgence
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/auth/link_code_service.dart';
import '../../core/validation/text_validators.dart';
import '../../shared/widgets/necklife_button.dart';
import 'manage_links_screen.dart';

// Modèle d'un contact d'urgence
class _ContactUrgence {
  final String nom;
  final String telephone;
  final String relation;

  const _ContactUrgence({
    required this.nom,
    required this.telephone,
    required this.relation,
  });

  Map<String, String> toMap() => {
        'nom':       nom,
        'telephone': telephone,
        'relation':  relation,
      };

  factory _ContactUrgence.fromMap(Map<String, dynamic> map) => _ContactUrgence(
        nom:       map['nom'] as String,
        telephone: map['telephone'] as String,
        relation:  map['relation'] as String,
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LinkCodeService _linkCodeService = LinkCodeService();

  List<_ContactUrgence> _contacts = [];
  String? _linkCode;       // code de liaison, généré automatiquement à l'inscription
  String? _telephone;      // numéro de contact du propriétaire du profil
  bool _locationConsent = false;
  bool _chargement = true;

  // --- Édition du profil ---
  final _formKeyEdition = GlobalKey<FormState>();
  final _controleurNomEdit = TextEditingController();
  final _controleurTelephoneEdit = TextEditingController();
  final _controleurEmailEdit = TextEditingController();
  final _controleurMotDePasseActuel = TextEditingController();
  final _controleurNouveauMotDePasse = TextEditingController();
  bool _modeEdition = false;
  bool _sauvegardeEnCours = false;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
  }

  @override
  void dispose() {
    _controleurNomEdit.dispose();
    _controleurTelephoneEdit.dispose();
    _controleurEmailEdit.dispose();
    _controleurMotDePasseActuel.dispose();
    _controleurNouveauMotDePasse.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Charge le profil (dont le code de liaison) et les contacts d'urgence
  // ---------------------------------------------------------------------------
  Future<void> _chargerDonnees() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _chargement = false);
      return;
    }

    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      final liste = (data['contactsUrgence'] as List<dynamic>? ?? []);
      setState(() {
        _contacts = liste
            .map((c) => _ContactUrgence.fromMap(c as Map<String, dynamic>))
            .toList();
        _linkCode = data['linkCode'] as String?;
        _telephone = data['telephone'] as String?;
        _locationConsent = data['locationConsent'] as bool? ?? false;
      });
    }

    setState(() => _chargement = false);
  }

  // ---------------------------------------------------------------------------
  // Dialogue d'ajout d'un contact d'urgence
  // ---------------------------------------------------------------------------
  Future<void> _ajouterContact() async {
    final controleurNom       = TextEditingController();
    final controleurTel       = TextEditingController();
    final controleurRelation  = TextEditingController();
    final formKeyContact = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajouter un contact d\'urgence'),
        content: Form(
          key: formKeyContact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: controleurNom,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: validerNomPrenom,
              ),
              TextFormField(
                controller: controleurTel,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone'),
                validator: validerTelephone,
              ),
              TextField(
                controller: controleurRelation,
                decoration: const InputDecoration(labelText: 'Relation (enfant, médecin…)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKeyContact.currentState!.validate()) return;
              Navigator.pop(dialogContext);
              await _sauvegarderContact(_ContactUrgence(
                nom:       controleurNom.text.trim(),
                telephone: controleurTel.text.trim(),
                relation:  controleurRelation.text.trim(),
              ));
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sauvegarde le nouveau contact en Firestore
  // ---------------------------------------------------------------------------
  Future<void> _sauvegarderContact(_ContactUrgence contact) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _contacts.add(contact));

    await _firestore.collection('users').doc(uid).set(
      {'contactsUrgence': _contacts.map((c) => c.toMap()).toList()},
      SetOptions(merge: true),
    );
  }

  // ---------------------------------------------------------------------------
  // Supprime un contact
  // ---------------------------------------------------------------------------
  Future<void> _supprimerContact(int index) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _contacts.removeAt(index));

    await _firestore.collection('users').doc(uid).set(
      {'contactsUrgence': _contacts.map((c) => c.toMap()).toList()},
      SetOptions(merge: true),
    );
  }

  // ---------------------------------------------------------------------------
  // Bascule le consentement de partage de localisation en cas d'alerte —
  // n'écrit que ce booléen, aucune capture de position à ce stade
  // ---------------------------------------------------------------------------
  Future<void> _basculerConsentementLocalisation(bool valeur) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _locationConsent = valeur);

    await _firestore.collection('users').doc(uid).set(
      {'locationConsent': valeur},
      SetOptions(merge: true),
    );
  }

  // ---------------------------------------------------------------------------
  // Entre en mode édition, pré-remplit les champs avec les valeurs actuelles
  // ---------------------------------------------------------------------------
  void _entrerModeEdition() {
    final user = FirebaseAuth.instance.currentUser;
    _controleurNomEdit.text = user?.displayName ?? '';
    _controleurTelephoneEdit.text = _telephone ?? '';
    _controleurEmailEdit.text = user?.email ?? '';
    _controleurMotDePasseActuel.clear();
    _controleurNouveauMotDePasse.clear();
    setState(() => _modeEdition = true);
  }

  // ---------------------------------------------------------------------------
  // Enregistre les modifications du profil :
  // - nom/téléphone : écriture directe (Firestore + displayName Auth)
  // - email/mot de passe : ré-authentification requise par Firebase avant
  //   modification (voir auth_service.dart)
  // ---------------------------------------------------------------------------
  Future<void> _enregistrerModifications() async {
    if (!_formKeyEdition.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nouveauNom = _controleurNomEdit.text.trim();
    final nouveauTelephone = _controleurTelephoneEdit.text.trim();
    final nouvelEmail = _controleurEmailEdit.text.trim();
    final nouveauMotDePasse = _controleurNouveauMotDePasse.text;
    // N'estampille la date de modif. que si le numéro a réellement changé —
    // sert à départager avec le numéro local attribué par un aidant (voir
    // définition de priorité "dernier qui modifie gagne" dans home_screen.dart)
    final telephoneModifie = nouveauTelephone != (_telephone ?? '');

    final emailModifie = nouvelEmail != (user.email ?? '');
    final motDePasseModifie = nouveauMotDePasse.isNotEmpty;

    if ((emailModifie || motDePasseModifie) && _controleurMotDePasseActuel.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe actuel requis pour ce changement.')),
      );
      return;
    }

    setState(() => _sauvegardeEnCours = true);

    try {
      if (emailModifie || motDePasseModifie) {
        await _authService.reauthentifier(_controleurMotDePasseActuel.text);
      }

      await user.updateDisplayName(nouveauNom);
      await _firestore.collection('users').doc(user.uid).set(
        {
          'nom': nouveauNom,
          'telephone': nouveauTelephone,
          if (telephoneModifie) 'telephoneModifieLe': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (emailModifie) {
        await _authService.changerEmail(nouvelEmail);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Email de confirmation envoyé à la nouvelle adresse — '
                'votre email ne changera qu\'après validation du lien.',
              ),
            ),
          );
        }
      }

      if (motDePasseModifie) {
        await _authService.changerMotDePasse(nouveauMotDePasse);
      }

      if (!mounted) return;
      setState(() {
        _telephone = nouveauTelephone;
        _modeEdition = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour.')),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_traduireErreurAuth(e.code))),
        );
      }
    } finally {
      if (mounted) setState(() => _sauvegardeEnCours = false);
    }
  }

  String _traduireErreurAuth(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Mot de passe actuel incorrect.';
      case 'email-already-in-use':
        return 'Cet email est déjà utilisé.';
      case 'invalid-email':
        return 'Adresse email invalide.';
      case 'weak-password':
        return 'Le mot de passe doit contenir au moins 6 caractères.';
      case 'requires-recent-login':
        return 'Veuillez vous reconnecter puis réessayer.';
      default:
        return 'Erreur : $code';
    }
  }

  // ---------------------------------------------------------------------------
  // Déconnexion
  // ---------------------------------------------------------------------------
  Future<void> _seDeconnecter() async {
    await _authService.deconnecter();
    if (mounted) {
      // Retour à la racine — l'écran d'auth prend le relais via authStateChanges
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ---------------------------------------------------------------------------
  // Dialogue de confirmation de suppression définitive du compte —
  // redemande le mot de passe actuel (ré-authentification requise par
  // Firebase avant une opération sensible comme user.delete())
  // ---------------------------------------------------------------------------
  Future<void> _confirmerSuppressionCompte() async {
    final controleurMotDePasse = TextEditingController();
    final formKeySuppression = GlobalKey<FormState>();
    bool suppressionEnCours = false;
    String? erreur;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Supprimer définitivement mon compte ?'),
          content: SingleChildScrollView(
            child: Form(
              key: formKeySuppression,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cette action est irréversible. Toutes vos données '
                    'seront supprimées définitivement : profil, contacts '
                    'd\'urgence, code de liaison et historique.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controleurMotDePasse,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Mot de passe actuel'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
                  ),
                  if (erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(erreur!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: suppressionEnCours ? null : () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: suppressionEnCours
                  ? null
                  : () async {
                      if (!formKeySuppression.currentState!.validate()) return;
                      setDialogState(() {
                        suppressionEnCours = true;
                        erreur = null;
                      });
                      try {
                        await _supprimerCompteDefinitivement(controleurMotDePasse.text);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() {
                          suppressionEnCours = false;
                          erreur = _traduireErreurAuth(e.code);
                        });
                      } catch (e) {
                        setDialogState(() {
                          suppressionEnCours = false;
                          erreur = 'Erreur : $e';
                        });
                      }
                    },
              child: suppressionEnCours
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Supprimer définitivement'),
            ),
          ],
        ),
      ),
    );

    // Suppression réussie (le dialogue s'est fermé sans exception) → le
    // compte n'existe plus, on revient à l'écran de connexion.
    if (FirebaseAuth.instance.currentUser == null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ---------------------------------------------------------------------------
  // Supprime définitivement le compte et toutes ses données associées.
  // La ré-authentification est faite EN PREMIER : si le mot de passe est
  // incorrect, rien n'est supprimé.
  // ---------------------------------------------------------------------------
  Future<void> _supprimerCompteDefinitivement(String motDePasseActuel) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _authService.reauthentifier(motDePasseActuel);

    final uid = user.uid;

    // Libère le code de liaison pour réutilisation future
    if (_linkCode != null) {
      await _linkCodeService.libererCode(_linkCode!);
    }

    // Supprime tous les liens (follower ou followed) pour éviter les liens
    // fantômes vers un compte supprimé
    final liensFollower = await _firestore.collection('links').where('followerUid', isEqualTo: uid).get();
    final liensFollowed = await _firestore.collection('links').where('followedUid', isEqualTo: uid).get();
    final batch = _firestore.batch();
    for (final doc in liensFollower.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in liensFollowed.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    // Supprime le profil
    await _firestore.collection('users').doc(uid).delete();

    // Supprime le compte Firebase Auth lui-même — libère l'email pour une
    // future inscription et déconnecte automatiquement l'utilisateur
    await user.delete();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon profil'),
        actions: [
          if (!_modeEdition)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Modifier',
              onPressed: _entrerModeEdition,
            )
          else
            TextButton(
              onPressed: _sauvegardeEnCours ? null : () => setState(() => _modeEdition = false),
              // Noir (et non blanc) : fond d'AppBar lavande, voir main.dart
              child: const Text('Annuler', style: TextStyle(color: Colors.black87)),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: _seDeconnecter,
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- Informations du compte (affichage ou édition) ---
                _modeEdition ? _carteEditionProfil() : _carteInfosCompte(user),
                const SizedBox(height: 16),

                // --- Code de liaison ---
                if (_linkCode != null)
                  Card(
                    color: const Color(0xFFF89EFF),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.qr_code, color: Color(0xFFF68FFA)),
                              const SizedBox(width: 8),
                              const Text(
                                'Mon code de liaison',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Colors.grey (≈1.4:1 sur ce fond) était illisible ;
                          // grey[800] conserve la hiérarchie visuelle (plus
                          // clair que le titre) tout en passant WCAG AA (≈5:1)
                          Text(
                            'Donnez ce code à un proche pour qu\'il puisse '
                            'recevoir vos alertes.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              _linkCode!,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // --- Section contacts d'urgence ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Contacts d\'urgence',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Color(0xFFF68FFA)),
                      onPressed: _ajouterContact,
                      tooltip: 'Ajouter un contact',
                    ),
                  ],
                ),

                if (_contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Aucun contact d\'urgence configuré.\nAppuyez sur + pour en ajouter.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...List.generate(_contacts.length, (i) {
                    final contact = _contacts[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.contact_phone, color: Color(0xFFF68FFA)),
                        title: Text(contact.nom),
                        subtitle: Text('${contact.telephone} — ${contact.relation}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _supprimerContact(i),
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 24),

                // --- Consentement de partage de localisation en cas d'alerte ---
                Card(
                  child: SwitchListTile(
                    title: const Text('Partager ma localisation en cas d\'alerte'),
                    subtitle: const Text(
                      'Autorise l\'envoi de votre position au moment précis '
                      'd\'une alerte, pour vos proches suivis.',
                    ),
                    value: _locationConsent,
                    onChanged: _basculerConsentementLocalisation,
                  ),
                ),

                const SizedBox(height: 24),

                // --- Gestion des liaisons avec les proches suivis ---
                NecklifeButton(
                  label: 'Modifier les liaisons',
                  icone: Icons.people_outline,
                  couleur: Colors.grey[700]!,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ManageLinksScreen()),
                  ),
                ),

                const SizedBox(height: 12),

                // --- Bouton déconnexion ---
                NecklifeButton(
                  label: 'Se déconnecter',
                  icone: Icons.logout,
                  couleur: Colors.grey[700]!,
                  onPressed: _seDeconnecter,
                ),

                const SizedBox(height: 12),

                // --- Suppression définitive du compte ---
                NecklifeButton(
                  label: 'Supprimer définitivement mon compte',
                  icone: Icons.delete_forever,
                  couleur: Colors.red,
                  onPressed: _confirmerSuppressionCompte,
                ),
              ],
            ),
    );
  }

  Widget _carteInfosCompte(User? user) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user?.displayName ?? 'Utilisateur'),
            subtitle: Text(user?.email ?? ''),
          ),
          if (_telephone != null && _telephone!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(_telephone!),
            ),
        ],
      ),
    );
  }

  Widget _carteEditionProfil() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKeyEdition,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _controleurNomEdit,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: validerNomPrenom,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controleurTelephoneEdit,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  hintText: 'Optionnel',
                ),
                validator: validerTelephoneOptionnel,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controleurEmailEdit,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Champ requis';
                  if (!v.contains('@')) return 'Email invalide';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 4),
              const Text(
                'Requis uniquement pour changer l\'email ou le mot de passe :',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _controleurMotDePasseActuel,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe actuel'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controleurNouveauMotDePasse,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  hintText: 'Laisser vide pour ne pas changer',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  if (v.length < 6) return 'Minimum 6 caractères';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sauvegardeEnCours ? null : _enregistrerModifications,
                child: _sauvegardeEnCours
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
