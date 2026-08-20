// NeckLife : Service de géolocalisation
// Capture la position actuelle au moment d'une alerte sous réserve du
// consentement de l'utilisateur (voir profile_screen.dart) 

import 'package:geolocator/geolocator.dart';

class LocationService {
  // Demande la permission de localisation si nécessaire puis retourne la
  // position actuelle. Retourne null si le service est désactivé la
  // permission refusée ou en cas d'erreur ne lance jamais d'exception.
  Future<({double lat, double lng})?> obtenirPositionActuelle() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition();
      return (lat: position.latitude, lng: position.longitude);
    } catch (_) {
      return null;
    }
  }
}
