// Smoke test minimal, sans dépendance Firebase.
//
// NeckLifeApp (et tous les écrans en dessous) touchent FirebaseAuth/
// FirebaseFirestore.instance dès leur construction, ce qui nécessite
// Firebase.initializeApp() — non disponible dans un `flutter test` classique
// sans mocking dédié. On se limite donc ici à vérifier que le thème NeckLife
// (couleurPrimaire) s'applique correctement à un Scaffold basique.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_necklife/main.dart';

void main() {
  testWidgets('Le thème NeckLife (lavande) est appliqué à l\'AppBar',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: couleurPrimaire),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: couleurPrimaire,
            foregroundColor: Colors.black87,
          ),
        ),
        home: Scaffold(appBar: AppBar(title: const Text('NeckLife'))),
      ),
    );

    final context = tester.element(find.byType(AppBar));
    expect(Theme.of(context).appBarTheme.backgroundColor, couleurPrimaire);
    expect(find.text('NeckLife'), findsOneWidget);
  });
}
