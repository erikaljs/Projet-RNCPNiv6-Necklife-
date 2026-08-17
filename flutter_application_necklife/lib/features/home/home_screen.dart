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
import '../profile/profile_screen.dart';

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

  // Demandes déjà affichées dans un dialogue, pour ne pas les répéter à
  // chaque mise à jour du stream
  final Set<String> _demandesAffichees = {};

  @override
  void initState() {
    super.initState();
    _subscriptionAlertes = _bleManager.alertes.listen(_afficherAlerteChute);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _subscriptionDemandes = _linkCodeService
          .ecouterDemandesEnAttente(uid)
          .listen(_traiterDemandesEnAttente);
    }
  }

  @override
  void dispose() {
    _subscriptionAlertes?.cancel();
    _subscriptionBalayage?.cancel();
    _subscriptionDemandes?.cancel();
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
  Future<void> _enregistrerFallEventAuto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final consentement = userDoc.data()?['locationConsent'] as bool? ?? false;
    final position = consentement ? await _locationService.obtenirPositionActuelle() : null;

    await _firestore.collection('fallEvents').add({
      'uid':       uid,
      'type':      'CHUTE_AUTO',
      'statut':    'en_attente',
      'timestamp': FieldValue.serverTimestamp(),
      if (position != null) 'lat': position.lat,
      if (position != null) 'lng': position.lng,
    });
  }

  // ---------------------------------------------------------------------------
  // Alerte de chute détectée sur SON PROPRE collier
  // ---------------------------------------------------------------------------
  void _afficherAlerteChute(String _) {
    if (!mounted) return;
    _enregistrerFallEventAuto();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('CHUTE DÉTECTÉE', style: TextStyle(color: Colors.red)),
        content: const Text('Une chute a été détectée. Êtes-vous en sécurité ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
          leading: const Icon(Icons.watch, color: Colors.green, size: 40),
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
            const Text('Collier non associé', style: TextStyle(fontWeight: FontWeight.bold)),
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

        final proches = [...snapshot.data!]..sort((a, b) {
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

  bool _etendu = false;
  Future<({double lat, double lng})?>? _futurePosition;
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _futureHistorique;

  // ---------------------------------------------------------------------------
  // Cherche le fallEvent le plus récent (<72h) de ce proche contenant une
  // position — lat/lng ne sont présents que si le proche avait consenti au
  // partage au moment de l'alerte
  // ---------------------------------------------------------------------------
  Future<({double lat, double lng})?> _chercherDernierePosition() async {
    final procheUid = widget.proche['uid'] as String;
    final depuis = DateTime.now().subtract(const Duration(hours: 72));

    final snap = await _firestore
        .collection('fallEvents')
        .where('uid', isEqualTo: procheUid)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(depuis))
        .orderBy('timestamp', descending: true)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final lat = data['lat'] as num?;
      final lng = data['lng'] as num?;
      if (lat != null && lng != null) {
        return (lat: lat.toDouble(), lng: lng.toDouble());
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Historique des chutes (<72h) de ce proche, triées par date décroissante —
  // même requête que _ImuScreenState dans imu_screen.dart, mais sur l'uid du
  // proche plutôt que celui de l'utilisateur connecté
  // ---------------------------------------------------------------------------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _chercherHistoriqueChutes() async {
    final procheUid = widget.proche['uid'] as String;
    final depuis = DateTime.now().subtract(const Duration(hours: 72));

    final snap = await _firestore
        .collection('fallEvents')
        .where('uid', isEqualTo: procheUid)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(depuis))
        .orderBy('timestamp', descending: true)
        .get();

    return snap.docs;
  }

  String _formaterDate(DateTime dt) {
    String deuxChiffres(int n) => n.toString().padLeft(2, '0');
    return '${deuxChiffres(dt.day)}/${deuxChiffres(dt.month)} '
        '${deuxChiffres(dt.hour)}:${deuxChiffres(dt.minute)}';
  }

  void _basculerExpansion() {
    setState(() {
      _etendu = !_etendu;
      _futurePosition ??= _chercherDernierePosition();
      _futureHistorique ??= _chercherHistoriqueChutes();
    });
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

  @override
  Widget build(BuildContext context) {
    final chuteActive = widget.proche['chuteActive'] == true;
    final nom = widget.proche['nom'] as String? ?? 'Proche';
    // Numéro de test tant qu'aucun numéro n'est stocké pour ce proche
    final numero = widget.proche['telephone'] as String? ?? '0600000000';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: chuteActive ? Colors.red[50] : null,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.person, color: chuteActive ? Colors.red : const Color(0xFFF68FFA)),
            title: Text(nom, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              chuteActive ? 'CHUTE DÉTECTÉE' : 'Statut du collier : non disponible',
              style: TextStyle(
                color: chuteActive ? Colors.red : Colors.grey,
                fontWeight: chuteActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.call, color: Colors.green),
              onPressed: () => widget.onAppeler(numero),
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
                  FutureBuilder<({double lat, double lng})?>(
                    future: _futurePosition,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final position = snapshot.data;
                      if (position == null) {
                        return const Text(
                          'Aucune localisation récente partagée.',
                          style: TextStyle(color: Colors.grey),
                        );
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 180,
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
                                  child: const Icon(Icons.location_pin,
                                      color: Colors.red, size: 40),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Historique de chutes', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                    future: _futureHistorique,
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
