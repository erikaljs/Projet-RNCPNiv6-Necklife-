// =============================================================================
// NeckLife — Point d'entrée de l'application Flutter
// Initialise Firebase, lance l'arbre de widgets, route selon l'état de connexion
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/auth/auth_service.dart';
import 'core/notifications/push_service.dart';
import 'features/auth/email_verification_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/imu/imu_screen.dart';
import 'features/sos/sos_screen.dart';

// Couleurs de la charte graphique NeckLife
const Color couleurPrimaire = Color(0xFFF68FFA); // lavande
const Color couleurAlerte   = Color(0xFFD32F2F); // rouge SOS
const Color couleurFond     = Color(0xFFF5F5F5);

Future<void> main() async {
  // Initialisation obligatoire avant tout appel Firebase
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyA25-ssiWlqHvkTJRtxiwWFx7IkEOIVHEc",
      authDomain: "necklife-project.firebaseapp.com",
      projectId: "necklife-project",
      storageBucket: "necklife-project.firebasestorage.app",
      messagingSenderId: "596813751148",
      appId: "1:596813751148:web:a7fd7fb6af3508fd978949",
    ),
  );

  runApp(const NeckLifeApp());
}

class NeckLifeApp extends StatelessWidget {
  const NeckLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeckLife',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: couleurPrimaire),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: couleurPrimaire,
          // Le blanc n'offrait plus assez de contraste (≈2:1) sur la
          // lavande #F68FFA (WCAG AA exige 4.5:1) ; noir87 donne ≈9:1.
          foregroundColor: Colors.black87,
          elevation: 2,
        ),
      ),
      home: const PortailAuthentification(),
    );
  }
}

// ---------------------------------------------------------------------------
// Écoute l'état de connexion Firebase et affiche l'écran correspondant
// ---------------------------------------------------------------------------
class PortailAuthentification extends StatelessWidget {
  const PortailAuthentification({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().etatConnexion,
      builder: (context, snapshot) {
        // En attente de la première réponse Firebase
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        // Non connecté → connexion/inscription
        if (user == null) {
          return const LoginScreen();
        }

        // Connecté mais email non confirmé → écran de vérification
        if (!user.emailVerified) {
          return const EmailVerificationScreen();
        }

        // Demande la permission de notification et sauvegarde le token FCM
        PushService().initialiser();
        return const RacineNavigation();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation principale avec NavigationBar (3 onglets)
// ---------------------------------------------------------------------------
class RacineNavigation extends StatefulWidget {
  const RacineNavigation({super.key});

  @override
  State<RacineNavigation> createState() => _RacineNavigationState();
}

class _RacineNavigationState extends State<RacineNavigation> {
  // Accueil au centre par défaut
  int _indexOnglet = 1;

  // Liste des écrans accessibles via la barre de navigation :
  // SOS (gauche) / Accueil (centre) / Ma courbe (droite).
  // Le Profil n'est plus accessible depuis cette barre — uniquement via le
  // clic sur le nom en haut de l'accueil.
  final List<Widget> _ecrans = const [
    SosScreen(),
    HomeScreen(),
    ImuScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _ecrans[_indexOnglet],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexOnglet,
        onDestinationSelected: (index) => setState(() => _indexOnglet = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sos_outlined),
            selectedIcon: Icon(Icons.sos, color: couleurAlerte),
            label: 'SOS',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Ma courbe',
          ),
        ],
      ),
    );
  }
}
