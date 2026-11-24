// =============================================================================
// NeckLife — Surveillance de la batterie du téléphone porteur
// Capture une position de secours quand la batterie devient faible, pour
// éviter qu'une position de chute périmée (potentiellement vieille de
// plusieurs heures) induise l'aidant en erreur sur l'emplacement actuel du
// porteur (voir home_screen.dart côté aidant pour l'affichage).
// =============================================================================

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../location/location_service.dart';

class BatteryService {
  BatteryService._internal();

  // Instance unique — le Timer doit survivre à la navigation entre écrans,
  // comme BleManager.instance
  static final BatteryService instance = BatteryService._internal();

  final Battery _battery = Battery();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();

  Timer? _timer;

  // Dernier état connu localement (null = pas encore évalué). Sert à ne
  // déclencher l'écriture Firestore qu'au FRANCHISSEMENT d'un seuil, pas à
  // chaque vérification tant que le niveau reste bas.
  bool? _etatFaibleActuel;

  static const int _seuilBas = 10;
  static const int _seuilRetourNormal = 15;
  static const Duration _intervalleVerification = Duration(minutes: 3);

  // ---------------------------------------------------------------------------
  // Démarre la vérification périodique. Idempotent : un second appel (ex.
  // rebuild de PortailAuthentification) ne recrée pas de second Timer.
  // ---------------------------------------------------------------------------
  void demarrerSurveillance() {
    if (_timer != null) return;
    _timer = Timer.periodic(_intervalleVerification, (_) => _verifierNiveau());
    _verifierNiveau();
  }

  Future<void> _verifierNiveau() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final niveau = await _battery.batteryLevel;

    if (niveau <= _seuilBas && _etatFaibleActuel != true) {
      _etatFaibleActuel = true;
      await _signalerBatterieFaible(uid);
    } else if (niveau > _seuilRetourNormal && _etatFaibleActuel != false) {
      _etatFaibleActuel = false;
      await _firestore.collection('users').doc(uid).set(
        {'phoneBatteryLow': false},
        SetOptions(merge: true),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Capture une position de secours si le consentement de localisation est
  // accordé, puis écrit l'état sur le profil. lastKnownAt est écrit même
  // sans consentement (position absente) : ça permet à l'aidant de savoir
  // QUAND la batterie est devenue faible, même sans savoir OÙ.
  // ---------------------------------------------------------------------------
  Future<void> _signalerBatterieFaible(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final consentement = userDoc.data()?['locationConsent'] as bool? ?? false;
    final position = consentement ? await _locationService.obtenirPositionActuelle() : null;

    await _firestore.collection('users').doc(uid).set({
      'phoneBatteryLow': true,
      'lastKnownAt': FieldValue.serverTimestamp(),
      if (position != null) 'lastKnownLat': position.lat,
      if (position != null) 'lastKnownLng': position.lng,
    }, SetOptions(merge: true));
  }
}
