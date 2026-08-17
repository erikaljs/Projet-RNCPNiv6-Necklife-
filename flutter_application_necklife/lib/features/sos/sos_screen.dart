// =============================================================================
// NeckLife — Écran SOS
// Gros bouton rouge d'urgence + bouton test du buzzer du collier
// =============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ble/ble_manager.dart';
import '../../core/location/location_service.dart';
import '../../core/validation/text_validators.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool _sosEnCours = false;
  final BleManager _bleManager = BleManager.instance;
  final LocationService _locationService = LocationService();

  // Numéro d'urgence par défaut, utilisé tant qu'aucun n'est configuré
  static const String numeroUrgenceParDefaut = "15"; // SAMU

  String _numeroUrgence = numeroUrgenceParDefaut;

  @override
  void initState() {
    super.initState();
    _chargerNumeroUrgence();
  }

  // ---------------------------------------------------------------------------
  // Charge le numéro d'urgence configuré (users/{uid}.emergencyNumber)
  // ---------------------------------------------------------------------------
  Future<void> _chargerNumeroUrgence() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final numero = doc.data()?['emergencyNumber'] as String?;
    if (mounted && numero != null && numero.isNotEmpty) {
      setState(() => _numeroUrgence = numero);
    }
  }

  // ---------------------------------------------------------------------------
  // Dialogue de modification du numéro d'urgence
  // ---------------------------------------------------------------------------
  Future<void> _modifierNumeroUrgence() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final controleur = TextEditingController(text: _numeroUrgence);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Numéro d\'urgence'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controleur,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Numéro'),
            validator: validerTelephone,
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
              final nouveauNumero = controleur.text.trim();
              Navigator.pop(dialogContext);

              await FirebaseFirestore.instance.collection('users').doc(uid).set(
                {'emergencyNumber': nouveauNumero},
                SetOptions(merge: true),
              );
              if (mounted) setState(() => _numeroUrgence = nouveauNumero);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Déclenchement de l'alerte SOS
  // Enregistre en Firestore et propose d'appeler les contacts d'urgence
  // ---------------------------------------------------------------------------
  Future<void> _declencherSos() async {
    setState(() => _sosEnCours = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Enregistrement de l'alerte SOS dans Firestore (journal existant)
      await FirebaseFirestore.instance
          .collection('fallAlerts')
          .doc(uid)
          .collection('alertes')
          .add({
        'type':       'SOS_MANUEL',
        'timestamp':  FieldValue.serverTimestamp(),
        'acquittee':  false,
      });

      // Événement fallEvents : déclenche la notification push aux proches
      // (Cloud Function notifierChuteDetectee) et alimente l'historique
      // "Ma courbe". lat/lng : voir TODO de purge DPIA dans imu_screen.dart.
      final position = await _positionSiConsentie(uid);
      await FirebaseFirestore.instance.collection('fallEvents').add({
        'uid':       uid,
        'type':      'SOS_MANUEL',
        'statut':    'en_attente',
        'timestamp': FieldValue.serverTimestamp(),
        if (position != null) 'lat': position.lat,
        if (position != null) 'lng': position.lng,
      });

      if (!mounted) return;

      // Dialogue de confirmation avant d'appeler
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Appeler les secours ?'),
          content: Text(
            'L\'alerte a été enregistrée. Voulez-vous appeler le $_numeroUrgence ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                await _appelerNumero(_numeroUrgence);
              },
              child: Text('Appeler le $_numeroUrgence', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _sosEnCours = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Capture la position actuelle uniquement si l'utilisateur a donné son
  // consentement dans son profil (users/{uid}.locationConsent)
  // ---------------------------------------------------------------------------
  Future<({double lat, double lng})?> _positionSiConsentie(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final consentement = doc.data()?['locationConsent'] as bool? ?? false;
    if (!consentement) return null;
    return _locationService.obtenirPositionActuelle();
  }

  // ---------------------------------------------------------------------------
  // Lance un appel téléphonique via le numéroteur natif
  // ---------------------------------------------------------------------------
  Future<void> _appelerNumero(String numero) async {
    final uri = Uri(scheme: 'tel', path: numero);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ---------------------------------------------------------------------------
  // Test du buzzer du collier — envoie la commande BLE TEST_BUZZER
  // ---------------------------------------------------------------------------
  Future<void> _testerBuzzer() async {
    try {
      await _bleManager.testerBuzzer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Signal buzzer envoyé au collier',
            style: TextStyle(color: Colors.black87),
          ),
          backgroundColor: Color(0xFFF68FFA),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS — Urgence'),
        backgroundColor: Colors.red[800],
        // Fond rouge foncé propre à cet écran : override explicite car le
        // thème global utilise désormais un texte sombre (fond lavande).
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.red[50],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- Texte d'instruction ---
              const Text(
                'En cas de chute ou de danger,\nappuyez sur le bouton SOS',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 48),

              // --- Grand bouton SOS rouge ---
              GestureDetector(
                onTap: _sosEnCours ? null : _declencherSos,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _sosEnCours ? Colors.red[300] : Colors.red[700],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: _sosEnCours
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sos, size: 80, color: Colors.white),
                            Text(
                              'SOS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 48),

              // --- Bouton test buzzer ---
              OutlinedButton.icon(
                onPressed: _testerBuzzer,
                icon: const Icon(Icons.volume_up),
                label: const Text('Tester le buzzer du collier'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[800],
                  side: BorderSide(color: Colors.red[800]!),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),

              const SizedBox(height: 16),

              // --- Numéro d'urgence, modifiable ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Numéro d\'urgence configuré : $_numeroUrgence',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    tooltip: 'Modifier',
                    onPressed: _modifierNumeroUrgence,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
