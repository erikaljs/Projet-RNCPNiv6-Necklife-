// =============================================================================
// NeckLife — Écran "Ma courbe"
// Courbe IMU temps réel de SON PROPRE collier + historique de SES propres
// chutes sur 72h, avec possibilité de les labelliser (chute réelle / fausse
// alerte) pour alimenter le futur affinage de la détection
// =============================================================================

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ImuScreen extends StatefulWidget {
  const ImuScreen({super.key});

  @override
  State<ImuScreen> createState() => _ImuScreenState();
}

class _ImuScreenState extends State<ImuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Historique des 50 dernières magnitudes IMU pour la courbe
  final List<double> _historiqueImu = List.filled(50, 1.0);

  // TODO: le firmware ESP32 ne diffuse pour l'instant qu'une notification
  // BLE discrète "CHUTE_DETECTEE" (voir ble_manager.dart), pas un flux IMU
  // continu. En attendant une caractéristique BLE de streaming, on simule
  // des données de démonstration pour visualiser le graphique.
  Timer? _timerSimulation;

  @override
  void initState() {
    super.initState();
    _demarrerSimulationImu();
  }

  void _demarrerSimulationImu() {
    final rng = Random();
    _timerSimulation = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _historiqueImu.removeAt(0);
        _historiqueImu.add(1.0 + (rng.nextDouble() - 0.5) * 0.2);
      });
    });
  }

  @override
  void dispose() {
    _timerSimulation?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Labellise un événement de chute (retour terrain pour affiner la détection)
  // ---------------------------------------------------------------------------
  Future<void> _labelliser(String docId, String statut) async {
    await _firestore.collection('fallEvents').doc(docId).update({'statut': statut});
  }

  String _formaterDate(DateTime dt) {
    String deuxChiffres(int n) => n.toString().padLeft(2, '0');
    return '${deuxChiffres(dt.day)}/${deuxChiffres(dt.month)} '
        '${deuxChiffres(dt.hour)}:${deuxChiffres(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final depuis = DateTime.now().subtract(const Duration(hours: 72));

    return Scaffold(
      appBar: AppBar(title: const Text('Ma courbe')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Accélération temps réel (g)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: _GraphiqueImu(donnees: _historiqueImu),
          ),
          const SizedBox(height: 24),
          const Text('Historique de mes chutes (72 dernières heures)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (uid == null)
            const Text('Non connecté.', style: TextStyle(color: Colors.grey))
          else
            // NB : cette requête (égalité + inégalité + tri) nécessite un
            // index composite Firestore ; la console affichera un lien de
            // création automatique au premier lancement si besoin.
            //
            // TODO (DPIA) : les documents fallEvents peuvent contenir des
            // champs lat/lng (position capturée au moment d'une alerte, sous
            // consentement — voir profile_screen.dart, sos_screen.dart et
            // home_screen.dart). Conformément à l'analyse d'impact (DPIA),
            // ces coordonnées sont des données sensibles à durée de vie
            // limitée : une Cloud Function planifiée (scheduled function,
            // non implémentée ici) devrait purger les champs lat/lng de tout
            // fallEvent de plus de 72h. Le reste du document (uid, timestamp,
            // statut) peut être conservé au-delà pour l'historique.
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('fallEvents')
                  .where('uid', isEqualTo: uid)
                  .where('timestamp', isGreaterThan: Timestamp.fromDate(depuis))
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Aucune chute enregistrée sur les 72 dernières heures.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return Column(
                  children: docs.map((doc) => _carteEvenement(doc)).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _carteEvenement(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final imuPeakG = data['imuPeakG'] as num?;
    final statut = data['statut'] as String? ?? 'en_attente';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              timestamp != null ? _formaterDate(timestamp) : 'Date inconnue',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (imuPeakG != null) Text('Pic IMU : ${imuPeakG.toStringAsFixed(2)} g'),
            const SizedBox(height: 8),
            if (statut == 'en_attente')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _labelliser(doc.id, 'fausse_alerte'),
                      child: const Text('Fausse alerte'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => _labelliser(doc.id, 'chute_reelle'),
                      child: const Text('Chute réelle', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              )
            else
              Chip(
                label: Text(statut == 'chute_reelle' ? 'Chute réelle' : 'Fausse alerte'),
                backgroundColor: statut == 'chute_reelle' ? Colors.red[100] : Colors.grey[300],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget : graphique IMU simple avec CustomPainter
// ---------------------------------------------------------------------------
class _GraphiqueImu extends StatelessWidget {
  final List<double> donnees;

  const _GraphiqueImu({required this.donnees});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        painter: _PainterImu(donnees: donnees),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PainterImu extends CustomPainter {
  final List<double> donnees;

  _PainterImu({required this.donnees});

  @override
  void paint(Canvas canvas, Size size) {
    final peinture = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (donnees.isEmpty) return;

    // Normalisation : 0 g → bas, 5 g → haut
    double normaliser(double valeur) =>
        1.0 - ((valeur.clamp(0.0, 5.0)) / 5.0);

    final path = Path();
    final largeurPas = size.width / (donnees.length - 1);

    path.moveTo(0, normaliser(donnees[0]) * size.height);
    for (int i = 1; i < donnees.length; i++) {
      path.lineTo(i * largeurPas, normaliser(donnees[i]) * size.height);
    }

    canvas.drawPath(path, peinture);

    // Ligne de référence à 1 g (repos)
    final peintureRef = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    final yRef = normaliser(1.0) * size.height;
    canvas.drawLine(Offset(0, yRef), Offset(size.width, yRef), peintureRef);
  }

  @override
  bool shouldRepaint(_PainterImu ancien) => ancien.donnees != donnees;
}
