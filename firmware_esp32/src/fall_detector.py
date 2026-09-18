"""
NeckLife - Detecteur de chute
Module utilise pour le calcul de detection de chute (dossier RNCP).

Algorithme :
  1. Chute libre = magnitude de l'acceleration en dessous du seuil SEUIL_CHUTE_LIBRE
  2. Impact = magnitude au-dessus du seuil SEUIL_IMPACT, survenant dans la fenetre
     de temps (fenetre_ms) suivant la chute libre
  -> Si les deux surviennent dans la fenetre : ALERTE (chute confirmee)

Unites : les valeurs ax, ay, az sont attendues en m/s^2 (gravite au repos = 9.81)
"""

import time
import math

SEUIL_CHUTE_LIBRE = 3.0  # m/s^2 - en dessous = quasi apesanteur (chute libre)
SEUIL_IMPACT = 15.0      # m/s^2 - au-dessus = choc / impact


def calculate_vector_magnitude(ax, ay, az):
    return math.sqrt(ax ** 2 + ay ** 2 + az ** 2)


def is_free_fall(magnitude, seuil=SEUIL_CHUTE_LIBRE):
    return magnitude < seuil


def is_impact(magnitude, seuil=SEUIL_IMPACT):
    return magnitude > seuil


class FallDetector:
    ETAT_IDLE = 0
    ETAT_CHUTE = 1
    ETAT_ALERTE = 2

    def __init__(self, fenetre_ms=500):
        self.fenetre_ms = fenetre_ms
        self.etat = self.ETAT_IDLE
        self._timestamp_chute = None

    def traiter_mesure(self, ax, ay, az):
        """
        A appeler a chaque nouvelle mesure IMU.
        Retourne True uniquement au moment ou l'alerte se declenche
        (transition CHUTE -> ALERTE).
        """
        magnitude = calculate_vector_magnitude(ax, ay, az)
        maintenant = time.ticks_ms()

        if self.etat == self.ETAT_IDLE:
            if is_free_fall(magnitude):
                self.etat = self.ETAT_CHUTE
                self._timestamp_chute = maintenant
            return False

        if self.etat == self.ETAT_CHUTE:
            delta = time.ticks_diff(maintenant, self._timestamp_chute)
            if delta > self.fenetre_ms:
                # Fenetre expiree sans impact -> on repart de zero
                self.etat = self.ETAT_IDLE
                self._timestamp_chute = None
                return False
            if is_impact(magnitude):
                self.etat = self.ETAT_ALERTE
                return True
            return False

        # ETAT_ALERTE : reste en alerte tant qu'on n'appelle pas reinitialiser()
        return False

    def reinitialiser(self):
        """Remet le detecteur en veille. A appeler apres traitement de l'alerte
        (typiquement quand l'utilisateur coupe le buzzer)."""
        self.etat = self.ETAT_IDLE
        self._timestamp_chute = None
