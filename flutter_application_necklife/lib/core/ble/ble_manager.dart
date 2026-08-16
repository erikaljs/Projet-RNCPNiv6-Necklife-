// =============================================================================
// NeckLife — Gestionnaire BLE
// Scan, connexion au collier, réception des notifications de chute
// Package : flutter_blue_plus
// =============================================================================

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// UUID du service BLE du collier (doit correspondre au firmware ESP32)
const String uuidServiceNecklife = "12345678-1234-1234-1234-123456789abc";
const String uuidCaracAlerte     = "12345678-1234-1234-1234-123456789abd";
const String uuidCaracCommandes  = "12345678-1234-1234-1234-123456789abe";

// Nom BLE diffusé par le collier
const String nomCollier = "NeckLife-Collier";

class BleManager {
  // Appareil connecté
  BluetoothDevice? _appareilConnecte;

  // Caractéristique de notification d'alerte (NOTIFY)
  BluetoothCharacteristic? _caracAlerte;

  // Caractéristique de commandes envoyées au collier (WRITE)
  BluetoothCharacteristic? _caracCommandes;

  // Stream exposé à l'UI pour réagir aux alertes de chute
  final StreamController<String> _streamAlertes =
      StreamController<String>.broadcast();

  Stream<String> get alertes => _streamAlertes.stream;

  bool get estConnecte => _appareilConnecte != null;

  // ---------------------------------------------------------------------------
  // Démarrer le scan BLE — cherche le collier NeckLife
  // ---------------------------------------------------------------------------
  Future<void> demarrerScan() async {
    // Vérifie que le Bluetooth est activé
    if (await FlutterBluePlus.isSupported == false) {
      throw Exception('Bluetooth non supporté sur cet appareil');
    }

    // Arrêter tout scan en cours avant d'en démarrer un nouveau
    await FlutterBluePlus.stopScan();

    FlutterBluePlus.startScan(
      withServices: [Guid(uuidServiceNecklife)],
      timeout: const Duration(seconds: 10),
    );

    // Écoute des appareils découverts
    FlutterBluePlus.scanResults.listen((resultats) {
      for (final resultat in resultats) {
        if (resultat.device.platformName == nomCollier) {
          FlutterBluePlus.stopScan();
          _connecter(resultat.device);
          break;
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Démarre un balayage BLE sans connexion automatique — les appareils
  // trouvés sont exposés via [resultatsBalayage] pour laisser l'utilisateur
  // choisir lequel associer.
  // ---------------------------------------------------------------------------
  Future<void> demarrerBalayage({Duration timeout = const Duration(seconds: 10)}) async {
    if (await FlutterBluePlus.isSupported == false) {
      throw Exception('Bluetooth non supporté sur cet appareil');
    }
    await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(
      withServices: [Guid(uuidServiceNecklife)],
      timeout: timeout,
    );
  }

  Stream<List<ScanResult>> get resultatsBalayage => FlutterBluePlus.scanResults;

  // ---------------------------------------------------------------------------
  // Connecte l'appareil choisi parmi les résultats du balayage
  // ---------------------------------------------------------------------------
  Future<void> connecterAppareil(BluetoothDevice appareil) => _connecter(appareil);

  // ---------------------------------------------------------------------------
  // Connexion au collier et abonnement aux notifications
  // ---------------------------------------------------------------------------
  Future<void> _connecter(BluetoothDevice appareil) async {
    await appareil.connect(autoConnect: false);
    _appareilConnecte = appareil;

    // Découverte des services GATT
    final services = await appareil.discoverServices();
    for (final service in services) {
      if (service.serviceUuid == Guid(uuidServiceNecklife)) {
        for (final carac in service.characteristics) {
          if (carac.characteristicUuid == Guid(uuidCaracAlerte)) {
            _caracAlerte = carac;
            // Activation des notifications BLE pour recevoir les alertes de chute
            await carac.setNotifyValue(true);
            carac.lastValueStream.listen(_traiterNotification);
          }
          if (carac.characteristicUuid == Guid(uuidCaracCommandes)) {
            // Caractéristique WRITE pour envoyer des commandes au collier
            _caracCommandes = carac;
          }
        }
      }
    }

    // Gestion de la déconnexion
    appareil.connectionState.listen((etat) {
      if (etat == BluetoothConnectionState.disconnected) {
        _appareilConnecte = null;
        _caracAlerte = null;
        _caracCommandes = null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Traitement d'une notification reçue depuis le collier
  // ---------------------------------------------------------------------------
  void _traiterNotification(List<int> donnees) {
    final message = String.fromCharCodes(donnees);
    if (message == "CHUTE_DETECTEE") {
      _streamAlertes.add(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Envoie la commande TEST_BUZZER au collier pour tester l'alarme sonore
  // Lance une exception si le collier n'est pas connecté
  // ---------------------------------------------------------------------------
  Future<void> testerBuzzer() async {
    if (_caracCommandes == null) {
      throw Exception('Collier non connecté — connectez-le depuis l\'accueil');
    }
    final commande = 'TEST_BUZZER'.codeUnits;
    await _caracCommandes!.write(commande, withoutResponse: false);
  }

  // ---------------------------------------------------------------------------
  // Déconnexion propre
  // ---------------------------------------------------------------------------
  Future<void> deconnecter() async {
    await _appareilConnecte?.disconnect();
    _appareilConnecte = null;
    _caracAlerte = null;
    _caracCommandes = null;
  }

  void dispose() {
    _streamAlertes.close();
  }
}
