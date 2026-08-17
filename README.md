# NeckLife
 
Collier connecté de détection de chute.
Le collier détecte une chute en temps réel via un accéléromètre, déclenche une alarme sonore locale, et prévient les proches aidants via l'application mobile associée.
 
Projet réalisé dans le cadre de la certification RNCP 36463 (Concepteur Développeur d'Applications Numériques).
 
## Architecture
 
Le projet est structuré en 3 briques principales :
 
- **`firmware_esp32/`** — Firmware MicroPython pour ESP32-C3, gérant la lecture de l'accéléromètre (MPU6050), l'algorithme de détection de chute, le buzzer d'alarme, le bouton d'arrêt, et la diffusion Bluetooth Low Energy (BLE) vers l'application mobile.
- **`flutter_application_necklife/`** — Application mobile Flutter (Android/iOS), permettant l'authentification, l'association au collier via BLE, le suivi en temps réel de l'état du porteur, et la gestion des liens entre utilisateurs et proches aidants.
- **`functions/`** — Cloud Functions Firebase, notamment `notifierChuteDetectee` pour l'envoi de notifications push aux proches aidants en cas de chute.
## Fonctionnement de la détection de chute
 
L'accéléromètre du collier mesure en continu l'accélération sur ses trois axes. Ces valeurs brutes sont converties en m/s², puis combinées en une magnitude unique (norme du vecteur d'accélération). L'algorithme surveille cette magnitude pour repérer la signature caractéristique d'une chute : une phase de chute libre (magnitude proche de 0) suivie d'un pic d'impact. Si ce motif est détecté, l'alarme se déclenche et l'app est notifiée via BLE.
 
## Liaison utilisateur / proche aidant
 
Chaque compte dispose d'un code unique à 6 caractères. Un proche aidant peut saisir ce code pour envoyer une demande de suivi ; une fois acceptée, il peut voir en temps réel le statut du collier, la localisation en cas de chute (sous consentement), et l'historique des alertes.
 
## Stack technique
 
- **Firmware** : MicroPython, ESP32-C3
- **Application mobile** : Flutter, Dart
- **Backend** : Firebase (Authentication, Firestore, Cloud Functions)
- **Communication collier ↔ app** : Bluetooth Low Energy (BLE)
## Démarrage rapide
 
### Firmware
1. Flasher MicroPython sur l'ESP32-C3
2. Copier les fichiers du dossier `firmware_esp32/` sur la carte via l'extension MicroPico (VS Code)
3. Lancer `main.py` depuis le REPL
### Application Flutter
```
cd flutter_application_necklife
flutter pub get
flutter run
```
 
### Backend Firebase
```
firebase login
firebase deploy --only firestore:rules
firebase deploy --only functions
```
 