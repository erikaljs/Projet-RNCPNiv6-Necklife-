// =============================================================================
// NeckLife — Écran d'accueil
// Salutation (accès profil) + association du collier + suivi des proches
// (demandes reçues, liste des proches acceptés, alertes de chute)
// =============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/link_code_service.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/location/location_service.dart';
import '../../core/validation/text_validators.dart';
import '../profile/profile_screen.dart';

// ---------------------------------------------------------------------------
// Résout le numéro à utiliser entre celui du profil d'un proche et celui
// attribué localement par l'aidant — le plus récemment modifié des deux
// l'emporte. Partagée entre _CarteProche (bouton d'appel de la fiche) et
// _HomeScreenState (bouton "Appeler" de la popup de chute, voir
// _traiterChutesNonConfirmees) : même logique de priorité, une seule
// implémentation.
// ---------------------------------------------------------------------------
({String? numero, String source}) _resoudreNumeroProche(
  Map<String, dynamic>? profil,
  Map<String, dynamic>? contactLocal,
) {
  final numeroProfil = profil?['telephone'] as String?;
  final modifieLeProfil = profil?['telephoneModifieLe'] as Timestamp?;

  final numeroLocal = contactLocal?['telephoneLocal'] as String?;
  final modifieLeLocal = contactLocal?['dernierModifieLe'] as Timestamp?;

  final profilValide = numeroProfil != null && numeroProfil.isNotEmpty;
  final localValide = numeroLocal != null && numeroLocal.isNotEmpty;

  if (!profilValide && !localValide) return (numero: null, source: 'aucun');
  if (!localValide) return (numero: numeroProfil, source: 'profil');
  if (!profilValide) return (numero: numeroLocal, source: 'local');

  // Les deux existent : le plus récemment modifié gagne. Sans timestamp sur
  // l'un des deux (donnée historique), on privilégie celui qui en a un.
  if (modifieLeProfil == null && modifieLeLocal == null) {
    return (numero: numeroLocal, source: 'local');
  }
  if (modifieLeProfil == null) return (numero: numeroLocal, source: 'local');
  if (modifieLeLocal == null) return (numero: numeroProfil, source: 'profil');
  return modifieLeLocal.compareTo(modifieLeProfil) >= 0
      ? (numero: numeroLocal, source: 'local')
      : (numero: numeroProfil, source: 'profil');
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BleManager _bleManager = BleManager.instance;
  final LinkCodeService _linkCodeService = LinkCodeService();
  final LocationService _locationService = LocationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _estConnecte = false;
  bool _balayageEnCours = false;
  List<ScanResult> _appareilsTrouves = [];

  StreamSubscription<String>? _subscriptionAlertes;
  StreamSubscription<List<ScanResult>>? _subscriptionBalayage;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscriptionDemandes;
  StreamSubscription<List<Map<String, dynamic>>>? _subscriptionProchesSuivis;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscriptionChutesProches;

  // Demandes déjà affichées dans un dialogue, pour ne pas les répéter à
  // chaque mise à jour du stream
  final Set<String> _demandesAffichees = {};

  // Idem pour les popups de chute côté aidant : un seul déclenchement par
  // fallEvent
  final Set<String> _chutesAffichees = {};

  // UIDs actuellement suivis, pour savoir quand se réabonner à
  // _subscriptionChutesProches (la liste change si un lien est accepté)
  List<String> _uidsSuivisPourChutes = [];
  Map<String, String> _nomsProches = {};

  // Chute active (non confirmée) par uid de proche, alimenté par
  // _subscriptionChutesProches — utilisé pour garder la carte du proche en
  // rouge tant que le porteur n'a pas confirmé "Je vais bien"
  Map<String, bool> _chuteActiveParUid = {};

  @override
  void initState() {
    super.initState();
    _subscriptionAlertes = _bleManager.alertes.listen(_afficherAlerteChute);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _subscriptionDemandes = _linkCodeService
          .ecouterDemandesEnAttente(uid)
          .listen(_traiterDemandesEnAttente);
      _subscriptionProchesSuivis = _linkCodeService
          .ecouterProchesSuivis(uid)
          .listen(_reabonnerChutesProches);
    }
  }

  @override
  void dispose() {
    _subscriptionAlertes?.cancel();
    _subscriptionBalayage?.cancel();
    _subscriptionDemandes?.cancel();
    _subscriptionProchesSuivis?.cancel();
    _subscriptionChutesProches?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Message de salutation selon l'heure du téléphone
  // ---------------------------------------------------------------------------
  String _messageSalutation() {
    final heure = DateTime.now().hour;
    final salutation = heure < 18 ? 'Bonjour' : 'Bonsoir';
    final prenom =
        FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? '';
    return prenom.isEmpty ? salutation : '$salutation $prenom';
  }

  // ---------------------------------------------------------------------------
  // Démarre le balayage BLE et écoute les appareils trouvés
  // ---------------------------------------------------------------------------
  Future<void> _demarrerAssociation() async {
    final statuts = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (statuts.values.any((s) => !s.isGranted)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions Bluetooth refusées.')),
        );
      }
      return;
    }

    setState(() {
      _balayageEnCours = true;
      _appareilsTrouves = [];
    });

    try {
      await _bleManager.demarrerBalayage();
      _subscriptionBalayage = _bleManager.resultatsBalayage.listen((resultats) {
        setState(() => _appareilsTrouves = resultats);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _balayageEnCours = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur BLE : $e')),
        );
      }
    }
  }

  Future<void> _connecterAppareil(BluetoothDevice appareil) async {
    await _subscriptionBalayage?.cancel();
    try {
      await _bleManager.connecterAppareil(appareil);
      if (!mounted) return;
      setState(() {
        _estConnecte = true;
        _balayageEnCours = false;
        _appareilsTrouves = [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de connexion : $e')),
        );
      }
    }
  }

  Future<void> _deconnecterCollier() async {
    await _bleManager.deconnecter();
    if (mounted) setState(() => _estConnecte = false);
  }

  // ---------------------------------------------------------------------------
  // Enregistre l'événement de chute auto-détectée par le collier (BLE) —
  // déclenche la notification push aux proches (Cloud Function
  // notifierChuteDetectee) et alimente l'historique "Ma courbe".
  // lat/lng : voir TODO de purge DPIA dans imu_screen.dart.
  // ---------------------------------------------------------------------------
  Future<String?> _enregistrerFallEventAuto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final consentement = userDoc.data()?['locationConsent'] as bool? ?? false;
    final position = consentement ? await _locationService.obtenirPositionActuelle() : null;

    final ref = await _firestore.collection('fallEvents').add({
      'uid':       uid,
      'type':      'CHUTE_AUTO',
      'statut':    'en_attente',
      'timestamp': FieldValue.serverTimestamp(),
      if (position != null) 'lat': position.lat,
      if (position != null) 'lng': position.lng,
    });
    return ref.id;
  }

  // ---------------------------------------------------------------------------
  // Persiste la confirmation "Je vais bien" du porteur sur son fallEvent —
  // c'est ce qui fait repasser chuteActive à false côté aidant (voir
  // _traiterChutesNonConfirmees). Indépendant de la labellisation
  // chute_reelle/fausse_alerte faite a posteriori depuis imu_screen.dart.
  // ---------------------------------------------------------------------------
  Future<void> _confirmerJeVaisBien(String fallEventId) async {
    await _firestore.collection('fallEvents').doc(fallEventId).update({
      'confirmeParPorteur': true,
      'confirmeAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Alerte de chute détectée sur SON PROPRE collier
  // ---------------------------------------------------------------------------
  Future<void> _afficherAlerteChute(String _) async {
    if (!mounted) return;
    final fallEventId = await _enregistrerFallEventAuto();
    if (!mounted || fallEventId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('CHUTE DÉTECTÉE', style: TextStyle(color: Colors.red)),
        content: const Text('Une chute a été détectée. Êtes-vous en sécurité ?'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _confirmerJeVaisBien(fallEventId);
            },
            child: const Text('Je vais bien'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context),
            child: const Text('Appeler à l\'aide', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Réabonnement à _subscriptionChutesProches quand l'ensemble des proches
  // suivis change (nouveau lien accepté, proche retiré, etc.)
  // ---------------------------------------------------------------------------
  void _reabonnerChutesProches(List<Map<String, dynamic>> proches) {
    final uids = proches.map((p) => p['uid'] as String).toList();
    _nomsProches = {
      for (final p in proches) p['uid'] as String: p['nom'] as String? ?? 'Un proche',
    };

    final memeEnsemble = _uidsSuivisPourChutes.length == uids.length &&
        _uidsSuivisPourChutes.toSet().containsAll(uids);
    if (memeEnsemble) return;

    _uidsSuivisPourChutes = uids;
    _subscriptionChutesProches?.cancel();
    _subscriptionChutesProches = null;

    if (uids.isEmpty) {
      if (_chuteActiveParUid.isNotEmpty && mounted) {
        setState(() => _chuteActiveParUid = {});
      }
      return;
    }

    _subscriptionChutesProches = _linkCodeService
        .ecouterChutesNonConfirmees(uids)
        .listen(_traiterChutesNonConfirmees);
  }

  // ---------------------------------------------------------------------------
  // Résout le numéro du porteur ayant déclenché l'alerte, pour le bouton
  // "Appeler" de la popup de chute — même logique de priorité que pour la
  // fiche proche (voir _resoudreNumeroProche), fetch ponctuel puisque la
  // popup n'a besoin du numéro qu'au moment de son affichage
  // ---------------------------------------------------------------------------
  Future<String?> _resoudreNumeroPorteur(String uidPorteur) async {
    final aidantUid = FirebaseAuth.instance.currentUser?.uid;
    if (aidantUid == null) return null;

    final profilDoc = await _linkCodeService.ecouterProfil(uidPorteur).first;
    final contactLocal =
        await _linkCodeService.ecouterContactLocal(aidantUid, uidPorteur).first;

    return _resoudreNumeroProche(profilDoc.data(), contactLocal).numero;
  }

  // ---------------------------------------------------------------------------
  // Chutes non confirmées des proches suivis : met à jour l'état "carte
  // rouge" (_chuteActiveParUid) et affiche une popup une seule fois par
  // fallEvent (voir _chutesAffichees)
  // ---------------------------------------------------------------------------
  Future<void> _traiterChutesNonConfirmees(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final actifs = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final statut = data['statut'] as String? ?? 'en_attente';
      final estActif = statut == 'en_attente' && data['confirmeParPorteur'] != true;
      if (!estActif) continue;

      final uidPorteur = data['uid'] as String;
      actifs.add(uidPorteur);

      if (_chutesAffichees.contains(doc.id)) continue;
      // Marqué avant le fetch async du numéro pour éviter un double
      // traitement si le stream refire pendant l'attente
      _chutesAffichees.add(doc.id);

      final nom = _nomsProches[uidPorteur] ?? 'Un proche';
      final numero = await _resoudreNumeroPorteur(uidPorteur);
      if (!mounted) continue;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('CHUTE DÉTECTÉE — $nom', style: const TextStyle(color: Colors.red)),
          content: Text(
            '$nom a peut-être fait une chute. Consultez sa localisation '
            'et ses contacts d\'urgence si besoin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
            if (numero != null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  Navigator.pop(context);
                  await _appelerNumero(numero);
                },
                child: Text('Appeler $numero', style: const TextStyle(color: Colors.white)),
              ),
          ],
        ),
      );
    }

    if (mounted) setState(() => _chuteActiveParUid = {for (final u in actifs) u: true});
  }

  // ---------------------------------------------------------------------------
  // Affiche une boîte de dialogue pour chaque nouvelle demande de suivi reçue
  // ---------------------------------------------------------------------------
  Future<void> _traiterDemandesEnAttente(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    for (final doc in snapshot.docs) {
      if (_demandesAffichees.contains(doc.id)) continue;
      _demandesAffichees.add(doc.id);

      final nomDemandeur = doc.data()['followerNom'] as String? ?? 'Un proche';

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Demande de suivi'),
          content: Text('$nomDemandeur souhaite suivre vos alertes NeckLife.'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _linkCodeService.refuserLien(doc.id);
              },
              child: const Text('Refuser'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _linkCodeService.accepterLien(doc.id);
              },
              child: const Text('Accepter'),
            ),
          ],
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Dialogue de saisie du code pour envoyer une demande de suivi
  // ---------------------------------------------------------------------------
  Future<void> _demanderSuiviProche() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final controleurCode = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Suivre un proche'),
        content: TextField(
          controller: controleurCode,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Code à 6 caractères',
            hintText: 'Ex : AB3K9Q',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = controleurCode.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(dialogContext);
              await _envoyerDemandeSuivi(uid, code);
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  Future<void> _envoyerDemandeSuivi(String monUid, String code) async {
    final followedUid = await _linkCodeService.verifierCode(code);
    if (!mounted) return;

    if (followedUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce code ne correspond à aucun compte.')),
      );
      return;
    }
    if (followedUid == monUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous ne pouvez pas vous suivre vous-même.')),
      );
      return;
    }

    final monNom = FirebaseAuth.instance.currentUser?.displayName ?? 'Un proche';
    await _linkCodeService.creerDemande(
      followerUid: monUid,
      followedUid: followedUid,
      followerNom: monNom,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande envoyée.')),
      );
    }
  }

  Future<void> _appelerNumero(String numero) async {
    final uri = Uri(scheme: 'tel', path: numero);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: Text(_messageSalutation()),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _carteCollier(),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Suivre un proche ?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.person_add, color: Color(0xFFF68FFA)),
                tooltip: 'Suivre un proche',
                onPressed: _demanderSuiviProche,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (uid != null) _listeProchesSuivis(uid),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Carte d'association / statut du collier
  // ---------------------------------------------------------------------------
  Widget _carteCollier() {
    if (_estConnecte) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.bluetooth_connected, color: Colors.green, size: 40),
          title: const Text('Collier connecté', style: TextStyle(fontWeight: FontWeight.bold)),
          // TODO: le firmware n'expose pas encore de caractéristique BLE de
          // charge batterie — quand disponible, remplacer cette ligne par
          // une LinearProgressIndicator basée sur la valeur lue.
          subtitle: const Text('Surveillance active'),
          trailing: TextButton(
            onPressed: _deconnecterCollier,
            child: const Text('Déconnecter'),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.bluetooth, color: Colors.grey),
                SizedBox(width: 8),
                Text('Collier non associé', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (!_balayageEnCours)
              ElevatedButton.icon(
                onPressed: _demarrerAssociation,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Associer un collier'),
              )
            else if (_appareilsTrouves.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._appareilsTrouves.map((r) => ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(
                      r.device.platformName.isEmpty
                          ? r.device.remoteId.str
                          : r.device.platformName,
                    ),
                    onTap: () => _connecterAppareil(r.device),
                  )),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Liste des proches suivis (liens acceptés) ; les chutes actives
  // remontent en haut
  // ---------------------------------------------------------------------------
  Widget _listeProchesSuivis(String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _linkCodeService.ecouterProchesSuivis(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final proches = snapshot.data!
            .map((p) => {
                  ...p,
                  'chuteActive': _chuteActiveParUid[p['uid']] == true,
                })
            .toList()
          ..sort((a, b) {
            final chuteA = a['chuteActive'] == true ? 1 : 0;
            final chuteB = b['chuteActive'] == true ? 1 : 0;
            return chuteB.compareTo(chuteA);
          });

        if (proches.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Aucun proche suivi pour l\'instant.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return Column(
          children: proches
              .map((proche) => _CarteProche(proche: proche, onAppeler: _appelerNumero))
              .toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Carte dépliable d'un proche suivi
// ---------------------------------------------------------------------------
class _CarteProche extends StatefulWidget {
  final Map<String, dynamic> proche;
  final Future<void> Function(String numero) onAppeler;

  const _CarteProche({required this.proche, required this.onAppeler});

  @override
  State<_CarteProche> createState() => _CarteProcheState();
}

class _CarteProcheState extends State<_CarteProche> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LinkCodeService _linkCodeService = LinkCodeService();

  bool _etendu = false;

  // Position du dernier fallEvent (<72h) avec sa date — toujours actif (pas
  // seulement en mode déplié) car nécessaire pour décider, dès la fiche
  // repliée, si la position de secours "batterie faible" doit prendre le
  // pas sur celle de la chute (voir _resoudreEtatLocalisation)
  Stream<({double lat, double lng, DateTime eventTime})?>? _streamPosition;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _streamHistorique;

  // Numéro local attribué par cet aidant à ce proche — écouté en continu
  // (pas seulement en mode déplié) car il conditionne la couleur du bouton
  // d'appel toujours visible sur la fiche repliée
  Stream<Map<String, dynamic>?>? _streamContactLocal;

  // Profil du proche en flux continu — nécessaire pour réagir en direct à
  // un numéro que LUI ajoute/efface sur sa propre page profil (voir bug
  // "le bouton ne repasse pas à l'état orange" : ecouterProchesSuivis ne
  // suffit pas, elle ne se redéclenche pas quand users/{procheUid} change)
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _streamProfilProche;

  @override
  void initState() {
    super.initState();
    final aidantUid = FirebaseAuth.instance.currentUser?.uid;
    final procheUid = widget.proche['uid'] as String;
    _streamProfilProche = _linkCodeService.ecouterProfil(procheUid);
    _streamPosition = _ecouterDernierePosition();
    if (aidantUid != null) {
      _streamContactLocal = _linkCodeService.ecouterContactLocal(aidantUid, procheUid);
    }
  }

  // ---------------------------------------------------------------------------
  // Écoute le fallEvent le plus récent (<72h) de ce proche contenant une
  // position, avec sa date — lat/lng ne sont présents que si le proche avait
  // consenti au partage au moment de l'alerte
  // ---------------------------------------------------------------------------
  Stream<({double lat, double lng, DateTime eventTime})?> _ecouterDernierePosition() {
    final procheUid = widget.proche['uid'] as String;
    final depuis = DateTime.now().subtract(const Duration(hours: 72));

    return _firestore
        .collection('fallEvents')
        .where('uid', isEqualTo: procheUid)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(depuis))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) {
      for (final doc in snap.docs) {
        final data = doc.data();
        final lat = data['lat'] as num?;
        final lng = data['lng'] as num?;
        final timestamp = data['timestamp'] as Timestamp?;
        if (lat != null && lng != null && timestamp != null) {
          return (lat: lat.toDouble(), lng: lng.toDouble(), eventTime: timestamp.toDate());
        }
      }
      return null;
    });
  }

  // ---------------------------------------------------------------------------
  // Écoute l'historique des chutes (<72h) de ce proche, triées par date
  // décroissante — même requête que _ImuScreenState dans imu_screen.dart,
  // mais sur l'uid du proche plutôt que celui de l'utilisateur connecté
  // ---------------------------------------------------------------------------
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _ecouterHistoriqueChutes() {
    final procheUid = widget.proche['uid'] as String;
    final depuis = DateTime.now().subtract(const Duration(hours: 72));

    return _firestore
        .collection('fallEvents')
        .where('uid', isEqualTo: procheUid)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(depuis))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs);
  }

  String _formaterDate(DateTime dt) {
    String deuxChiffres(int n) => n.toString().padLeft(2, '0');
    return '${deuxChiffres(dt.day)}/${deuxChiffres(dt.month)} '
        '${deuxChiffres(dt.hour)}:${deuxChiffres(dt.minute)}';
  }

  void _basculerExpansion() {
    setState(() {
      _etendu = !_etendu;
      // _streamPosition reste actif en permanence (voir initState) — seul
      // l'historique des chutes est chargé à la demande
      _streamHistorique = _etendu ? _ecouterHistoriqueChutes() : null;
    });
  }

  // ---------------------------------------------------------------------------
  // Décide si la position "batterie faible" (users/{uid}.lastKnown*) doit
  // prendre le pas sur celle du dernier fallEvent, et prépare l'avertissement
  // rouge associé. Une seule règle avec sous-cas, plutôt que 3 branches
  // indépendantes :
  //   - phoneBatteryLow == true ET (pas de fallEvent récent OU lastKnownAt
  //     plus récent que eventTime) → la position batterie gagne
  //     - avec lastKnownLat/Lng → carte centrée dessus (marqueur distinct,
  //       orange, pour ne pas la confondre avec une position de chute)
  //     - sans lastKnownLat/Lng (consentement refusé à ce moment-là) →
  //       avertissement seul, pas de carte
  //   - sinon → comportement actuel inchangé (position du fallEvent, ou
  //     rien si aucune des deux n'est disponible)
  // ---------------------------------------------------------------------------
  ({({double lat, double lng, bool depuisBatterie})? position, String? avertissementBatterie})
      _resoudreEtatLocalisation(
    ({double lat, double lng, DateTime eventTime})? positionChute,
    Map<String, dynamic>? profil,
  ) {
    final phoneBatteryLow = profil?['phoneBatteryLow'] == true;
    final lastKnownLat = profil?['lastKnownLat'] as num?;
    final lastKnownLng = profil?['lastKnownLng'] as num?;
    final lastKnownAt = profil?['lastKnownAt'] as Timestamp?;

    final batteryWins = phoneBatteryLow &&
        (positionChute == null ||
            (lastKnownAt != null && lastKnownAt.toDate().isAfter(positionChute.eventTime)));

    if (!batteryWins) {
      final position = positionChute == null
          ? null
          : (lat: positionChute.lat, lng: positionChute.lng, depuisBatterie: false);
      return (position: position, avertissementBatterie: null);
    }

    final nom = widget.proche['nom'] as String? ?? 'Proche';
    final prenom = nom.split(' ').first;

    if (lastKnownLat == null || lastKnownLng == null) {
      return (
        position: null,
        avertissementBatterie: 'Téléphone de $prenom déchargé — position non disponible',
      );
    }

    final dateFormatee = lastKnownAt != null ? _formaterDate(lastKnownAt.toDate()) : null;
    return (
      position: (lat: lastKnownLat.toDouble(), lng: lastKnownLng.toDouble(), depuisBatterie: true),
      avertissementBatterie: dateFormatee != null
          ? 'Téléphone de $prenom déchargé — dernière position enregistrée le $dateFormatee'
          : 'Téléphone de $prenom déchargé — position non disponible',
    );
  }

  // ---------------------------------------------------------------------------
  // Une ligne de l'historique de chutes du proche, en lecture seule — pas de
  // boutons de labellisation ici : cette action reste réservée au propriétaire
  // du collier lui-même, depuis imu_screen.dart
  // ---------------------------------------------------------------------------
  Widget _carteEvenementHistorique(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final imuPeakG = data['imuPeakG'] as num?;
    final statut = data['statut'] as String? ?? 'en_attente';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timestamp != null ? _formaterDate(timestamp) : 'Date inconnue',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (imuPeakG != null) Text('Pic IMU : ${imuPeakG.toStringAsFixed(2)} g'),
              ],
            ),
          ),
          _badgeStatut(statut),
        ],
      ),
    );
  }

  Widget _badgeStatut(String statut) {
    Color couleur;
    String libelle;
    switch (statut) {
      case 'chute_reelle':
        couleur = Colors.red;
        libelle = 'Chute réelle';
        break;
      case 'fausse_alerte':
        couleur = Colors.grey;
        libelle = 'Fausse alerte';
        break;
      default:
        couleur = Colors.orange;
        libelle = 'En attente';
    }
    return Chip(
      label: Text(libelle, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: couleur,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ---------------------------------------------------------------------------
  // Contacts d'urgence du proche, en lecture seule — aucune modification
  // possible depuis ici, uniquement depuis le profil du proche lui-même
  // ---------------------------------------------------------------------------
  Widget _listeContactsUrgence() {
    final contacts = widget.proche['contactsUrgence'] as List<dynamic>? ?? [];
    if (contacts.isEmpty) {
      return const Text(
        'Aucun contact d\'urgence configuré.',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Column(
      children: contacts.map((c) {
        final contact = c as Map<String, dynamic>;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Icon(Icons.contact_phone, size: 18, color: Color(0xFFF68FFA)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${contact['nom']} — ${contact['telephone']} (${contact['relation']})',
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogue affiché quand aucun numéro n'est disponible pour ce proche —
  // permet à l'aidant d'en attribuer un localement (voir _resoudreNumero)
  // ---------------------------------------------------------------------------
  Future<void> _proposerNumeroLocal() async {
    final aidantUid = FirebaseAuth.instance.currentUser?.uid;
    if (aidantUid == null) return;
    final procheUid = widget.proche['uid'] as String;

    final controleur = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Numéro non renseigné'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cet utilisateur n\'a pas renseigné de numéro. '
                'Si vous souhaitez en lier un :',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controleur,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Numéro'),
                validator: validerTelephone,
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
              if (!formKey.currentState!.validate()) return;
              final numero = controleur.text.trim();
              Navigator.pop(dialogContext);
              await _linkCodeService.definirTelephoneLocal(
                followerUid: aidantUid,
                followedUid: procheUid,
                telephone: numero,
              );
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Ouvre Google Maps en mode itinéraire (app installée si disponible, sinon
  // navigateur), prêt à démarrer la navigation vers le point de localisation
  // reçu. Format universel "dir" (fonctionne Android/iOS), contrairement à
  // google.navigation: qui est Android uniquement.
  // ---------------------------------------------------------------------------
  Future<void> _ouvrirDansMaps(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------------------------------------------------------------------
  // Section "Localisation" de la fiche dépliée — position du dernier
  // fallEvent (marqueur rouge, comme avant) ou position de secours batterie
  // faible (marqueur orange distinct, voir _resoudreEtatLocalisation), ou
  // avertissement seul sans carte si aucune position n'est disponible.
  // ---------------------------------------------------------------------------
  Widget _construireSectionLocalisation(
    ({({double lat, double lng, bool depuisBatterie})? position, String? avertissementBatterie})
        etatLocalisation,
  ) {
    final avertissement = etatLocalisation.avertissementBatterie;
    final position = etatLocalisation.position;

    if (position == null) {
      return Text(
        avertissement ?? 'Aucune localisation récente partagée.',
        style: TextStyle(
          color: avertissement != null ? Colors.red : Colors.grey,
          fontWeight: avertissement != null ? FontWeight.bold : FontWeight.normal,
        ),
      );
    }

    final couleurMarqueur = position.depuisBatterie ? Colors.orange : Colors.red;
    final iconeMarqueur = position.depuisBatterie ? Icons.battery_alert : Icons.location_pin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (avertissement != null) ...[
          Text(
            avertissement,
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          onTap: () => _ouvrirDansMaps(position.lat, position.lng),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 180,
              child: IgnorePointer(
                // La carte elle-même ne doit pas intercepter le tap (pas de
                // pan/zoom souhaité ici) — tap = ouverture directe dans Maps
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(position.lat, position.lng),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.necklife.app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(position.lat, position.lng),
                        width: 40,
                        height: 40,
                        child: Icon(iconeMarqueur, color: couleurMarqueur, size: 40),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Bouton explicite en plus du tap sur la carte — à retrouver
        // rapidement en situation d'urgence
        OutlinedButton.icon(
          onPressed: () => _ouvrirDansMaps(position.lat, position.lng),
          icon: const Icon(Icons.directions),
          label: const Text('Itinéraire'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _streamProfilProche,
      builder: (context, snapshotProfil) {
        return StreamBuilder<Map<String, dynamic>?>(
          stream: _streamContactLocal,
          builder: (context, snapshotContactLocal) {
            return StreamBuilder<({double lat, double lng, DateTime eventTime})?>(
              stream: _streamPosition,
              builder: (context, snapshotPosition) {
                final profilData = snapshotProfil.data?.data();
                final resolution = _resoudreNumeroProche(profilData, snapshotContactLocal.data);
                final etatLocalisation = _resoudreEtatLocalisation(
                  snapshotPosition.data,
                  profilData,
                );
                return _construireCarte(resolution, etatLocalisation);
              },
            );
          },
        );
      },
    );
  }

  Widget _construireCarte(
    ({String? numero, String source}) resolution,
    ({({double lat, double lng, bool depuisBatterie})? position, String? avertissementBatterie})
        etatLocalisation,
  ) {
    final numero = resolution.numero;
    // Vert = numéro du profil du proche, bleu = numéro attribué localement
    // par cet aidant, orange = aucun numéro disponible (tap = pop-up de saisie)
    final couleurAppel = switch (resolution.source) {
      'profil' => Colors.green,
      'local' => Colors.blue,
      _ => Colors.orange,
    };
    final chuteActive = widget.proche['chuteActive'] == true;
    final nom = widget.proche['nom'] as String? ?? 'Proche';
    final avertissementBatterie = etatLocalisation.avertissementBatterie;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: chuteActive ? Colors.red[50] : null,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.person, color: chuteActive ? Colors.red : const Color(0xFFF68FFA)),
            title: Text(nom, style: const TextStyle(fontWeight: FontWeight.bold)),
            // Colonne plutôt qu'un Text unique : la chute active ET
            // l'avertissement batterie peuvent être vrais en même temps, et
            // aucun des deux ne doit masquer l'autre
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chuteActive ? 'CHUTE DÉTECTÉE' : 'Statut du collier : non disponible',
                  style: TextStyle(
                    color: chuteActive ? Colors.red : Colors.grey,
                    fontWeight: chuteActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (avertissementBatterie != null)
                  Text(
                    avertissementBatterie,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: Icon(Icons.call, color: couleurAppel),
              onPressed: numero != null
                  ? () => widget.onAppeler(numero)
                  : _proposerNumeroLocal,
            ),
            onTap: _basculerExpansion,
          ),
          if (_etendu)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const Text('Localisation', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  _construireSectionLocalisation(etatLocalisation),
                  const SizedBox(height: 12),
                  const Text('Historique de chutes', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                    stream: _streamHistorique,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final docs = snapshot.data ?? [];
                      if (docs.isEmpty) {
                        return const Text(
                          'Aucune chute enregistrée sur les 72 dernières heures.',
                          style: TextStyle(color: Colors.grey),
                        );
                      }
                      return Column(
                        children: docs.map(_carteEvenementHistorique).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Contacts d\'urgence', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  _listeContactsUrgence(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
