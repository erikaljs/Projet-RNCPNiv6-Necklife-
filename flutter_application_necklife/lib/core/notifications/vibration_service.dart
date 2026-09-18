// =============================================================================
// NeckLife — Vibration à la réception d'une alerte de chute
// Fonction top-level (pas de dépendance à un état d'app) pour rester
// appelable depuis firebaseMessagingBackgroundHandler (main.dart), qui
// s'exécute dans un isolate séparé sans accès au reste de l'application.
// =============================================================================

import 'package:vibration/vibration.dart';

// Motif distinct d'une simple notification : plusieurs pulsations pour
// signaler clairement une alerte de chute (attente, vibre, attente, vibre...)
const List<int> motifVibrationAlerteChute = [0, 400, 200, 400, 200, 400];

Future<void> declencherVibrationAlerte() async {
  final dispositifVibrant = await Vibration.hasVibrator();
  if (dispositifVibrant != true) return;
  await Vibration.vibrate(pattern: motifVibrationAlerteChute);
}
