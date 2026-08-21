import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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
  }

  Future<void> _sauvegarderToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }
}
