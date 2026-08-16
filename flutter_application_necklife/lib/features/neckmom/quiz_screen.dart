// =============================================================================
// NeckLife / NeckMom — Quiz bien-être
// 5 questions, score sur 10, alerte envoyée si score < 4
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Structure d'une question du quiz
class _Question {
  final String texte;
  final List<String> reponses; // 3 réponses possibles
  // Scores associés aux réponses (index 0, 1, 2) — sur une échelle de 0 à 2
  final List<int> scores;

  const _Question({
    required this.texte,
    required this.reponses,
    required this.scores,
  });
}

// ---------------------------------------------------------------------------
// 5 questions bien-être adaptées aux seniors et femmes enceintes
// ---------------------------------------------------------------------------
const List<_Question> QUESTIONS_QUIZ = [
  _Question(
    texte: 'Comment vous sentez-vous physiquement aujourd\'hui ?',
    reponses: ['Très bien', 'Assez bien', 'Pas bien'],
    scores: [2, 1, 0],
  ),
  _Question(
    texte: 'Avez-vous bien dormi cette nuit ?',
    reponses: ['Oui, très bien', 'Moyennement', 'Non, mal dormi'],
    scores: [2, 1, 0],
  ),
  _Question(
    texte: 'Avez-vous pu vous lever et vous déplacer facilement ?',
    reponses: ['Sans difficulté', 'Avec un peu de mal', 'Difficilement'],
    scores: [2, 1, 0],
  ),
  _Question(
    texte: 'Avez-vous mangé correctement aujourd\'hui ?',
    reponses: ['Oui, normalement', 'Un peu moins que d\'habitude', 'Non, pas d\'appétit'],
    scores: [2, 1, 0],
  ),
  _Question(
    texte: 'Vous sentez-vous seul(e) ou isolé(e) ?',
    reponses: ['Non, pas du tout', 'Un peu', 'Oui, beaucoup'],
    scores: [2, 1, 0],
  ),
];

// Seuil d'alerte : score < 4 sur 10 → notification aux aidants
const int SEUIL_ALERTE_SCORE = 4;

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _indexQuestion = 0;
  final List<int> _reponsesChoisies = []; // scores accumulés

  bool _quizTermine = false;
  int _scoreFinal = 0;
  bool _enregistrementEnCours = false;

  // ---------------------------------------------------------------------------
  // L'utilisateur choisit une réponse
  // ---------------------------------------------------------------------------
  void _choisirReponse(int score) {
    _reponsesChoisies.add(score);

    if (_indexQuestion < QUESTIONS_QUIZ.length - 1) {
      // Passer à la question suivante
      setState(() => _indexQuestion++);
    } else {
      // Dernière question : calculer le score
      _terminerQuiz();
    }
  }

  // ---------------------------------------------------------------------------
  // Calcul du score et enregistrement en Firestore
  // Score brut = somme des points (max 10), converti sur 10
  // ---------------------------------------------------------------------------
  Future<void> _terminerQuiz() async {
    final somme = _reponsesChoisies.fold(0, (acc, s) => acc + s);
    // Max possible : 5 questions × 2 pts = 10
    final score = somme; // déjà sur 10

    setState(() {
      _scoreFinal = score;
      _quizTermine = true;
      _enregistrementEnCours = true;
    });

    await _enregistrerResultat(score);

    if (score < SEUIL_ALERTE_SCORE) {
      await _envoyerAlerteScore(score);
    }

    setState(() => _enregistrementEnCours = false);
  }

  // ---------------------------------------------------------------------------
  // Sauvegarde dans Firestore : collection wellbeingEntries
  // ---------------------------------------------------------------------------
  Future<void> _enregistrerResultat(int score) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('wellbeingEntries')
        .doc(uid)
        .collection('entrees')
        .add({
      'score':     score,
      'reponses':  _reponsesChoisies,
      'timestamp': FieldValue.serverTimestamp(),
      'alerte':    score < SEUIL_ALERTE_SCORE,
    });
  }

  // ---------------------------------------------------------------------------
  // Enregistre une alerte dans Firestore si le score est insuffisant
  // ---------------------------------------------------------------------------
  Future<void> _envoyerAlerteScore(int score) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('fallAlerts')
        .doc(uid)
        .collection('alertes')
        .add({
      'type':       'SCORE_BIENETRE_FAIBLE',
      'score':      score,
      'seuil':      SEUIL_ALERTE_SCORE,
      'timestamp':  FieldValue.serverTimestamp(),
      'acquittee':  false,
    });
  }

  // ---------------------------------------------------------------------------
  // Réinitialiser le quiz pour le repasser
  // ---------------------------------------------------------------------------
  void _recommencer() {
    setState(() {
      _indexQuestion = 0;
      _reponsesChoisies.clear();
      _quizTermine = false;
      _scoreFinal = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz bien-être NeckMom')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _quizTermine
            ? _construireResultat()
            : _construireQuestion(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Affichage d'une question
  // ---------------------------------------------------------------------------
  Widget _construireQuestion() {
    final question = QUESTIONS_QUIZ[_indexQuestion];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Indicateur de progression
        LinearProgressIndicator(
          value: (_indexQuestion + 1) / QUESTIONS_QUIZ.length,
          backgroundColor: Colors.grey[200],
          color: Colors.teal,
        ),
        const SizedBox(height: 8),
        Text(
          'Question ${_indexQuestion + 1} sur ${QUESTIONS_QUIZ.length}',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 32),

        // Texte de la question
        Text(
          question.texte,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),

        // Boutons de réponse
        ...List.generate(question.reponses.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => _choisirReponse(question.scores[i]),
              child: Text(question.reponses[i], textAlign: TextAlign.center),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Affichage du résultat
  // ---------------------------------------------------------------------------
  Widget _construireResultat() {
    final estAlerte = _scoreFinal < SEUIL_ALERTE_SCORE;
    final couleur = estAlerte ? Colors.red : Colors.teal;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            estAlerte ? Icons.warning_rounded : Icons.check_circle,
            size: 80,
            color: couleur,
          ),
          const SizedBox(height: 16),

          Text(
            'Votre score : $_scoreFinal / 10',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: couleur,
            ),
          ),
          const SizedBox(height: 16),

          Text(
            estAlerte
                ? 'Votre score est faible. Vos contacts d\'urgence ont été notifiés.'
                : 'Très bien ! Continuez à prendre soin de vous.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),

          if (_enregistrementEnCours) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const Text('Enregistrement en cours...'),
          ],

          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _recommencer,
            icon: const Icon(Icons.refresh),
            label: const Text('Refaire le quiz'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Retour à l\'accueil'),
          ),
        ],
      ),
    );
  }
}
