import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'vibration_service.dart';

class PushService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Demande la permission de notification puis sauvegarde le token FCM à appeler une fois l'utilisateur connecté
  Future<void> initialiser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final autorisation = await _messaging.requestPermission();
    final accorde =
        autorisation.authorizationStatus == AuthorizationStatus.authorized ||
            autorisation.authorizationStatus == AuthorizationStatus.provisional;
    if (!accorde) return;

    final token = await _messaging.getToken();
    if (token != null) {
      await _sauvegarderToken(uid, token);
    }

    // Le token peut être renouvelé par le système on le resauvegarde
    _messaging.onTokenRefresh.listen((nouveauToken) => _sauvegarderToken(uid, nouveauToken));

    // App au premier plan : FCM n'affiche pas de notification système dans
    // ce cas, donc on déclenche nous-mêmes la vibration d'alerte. Le cas
    // arrière-plan/app fermée est couvert par firebaseMessagingBackgroundHandler
    // (voir main.dart).
    FirebaseMessaging.onMessage.listen((_) => declencherVibrationAlerte());
  }

  Future<void> _sauvegarderToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }
}
