# =============================================================================
# NeckLife — Tests unitaires du détecteur de chutes
# Framework : pytest
# Exécution  : pytest firmware_esp32/test/test_fall_detector.py -v
# =============================================================================

import math
import sys
import os

# Rendre le module firmware accessible depuis la racine du repo
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

# Stub MicroPython : time.ticks_ms / time.ticks_diff (non disponibles en CPython)
import types
import time as _time

_mock_time = types.ModuleType("time")
_mock_time.ticks_ms   = lambda: int(_time.time() * 1000)
_mock_time.ticks_diff = lambda a, b: a - b
sys.modules["time"] = _mock_time

from fall_detector import (
    calculate_vector_magnitude,
    is_free_fall,
    is_impact,
    FallDetector,
)

# ---------------------------------------------------------------------------
# TU-01 : vecteur vertical standard (gravité terrestre)
# ---------------------------------------------------------------------------
def test_tu01_magnitude_gravite():
    """calculate_vector_magnitude(0, 0, 9.81) doit retourner ≈ 9.81."""
    resultat = calculate_vector_magnitude(0, 0, 9.81)
    assert math.isclose(resultat, 9.81, rel_tol=1e-9), (
        f"Attendu ≈ 9.81, obtenu {resultat}"
    )


# ---------------------------------------------------------------------------
# TU-02 : chute libre détectée (magnitude < seuil 0.3)
# ---------------------------------------------------------------------------
def test_tu02_free_fall_vrai():
    """is_free_fall(0.1) → True : magnitude bien inférieure au seuil."""
    assert is_free_fall(0.1) is True


# ---------------------------------------------------------------------------
# TU-03 : pas de chute libre (magnitude ≥ seuil)
# ---------------------------------------------------------------------------
def test_tu03_free_fall_faux():
    """is_free_fall(1.0) → False : magnitude trop élevée pour une chute libre."""
    assert is_free_fall(1.0) is False


# ---------------------------------------------------------------------------
# TU-04 : impact détecté (magnitude > seuil 3.0)
# ---------------------------------------------------------------------------
def test_tu04_impact_vrai():
    """is_impact(3.5) → True : magnitude supérieure au seuil d'impact."""
    assert is_impact(3.5) is True


# ---------------------------------------------------------------------------
# TU-05 : pas d'impact (magnitude ≤ seuil)
# ---------------------------------------------------------------------------
def test_tu05_impact_faux():
    """is_impact(2.0) → False : magnitude insuffisante pour un impact."""
    assert is_impact(2.0) is False


# ---------------------------------------------------------------------------
# TU-06 : FSM — chute complète (chute libre + impact dans la fenêtre)
# ---------------------------------------------------------------------------
def test_tu06_fsm_chute_complete():
    """Chute libre suivie d'un impact < 500 ms → alerte déclenchée."""
    detecteur = FallDetector(fenetre_ms=500)

    # Simulation chute libre (magnitude quasi-nulle)
    alerte = detecteur.traiter_mesure(0.0, 0.0, 0.1)
    assert not alerte, "Pas d'alerte attendue sur la chute libre seule"
    assert detecteur.etat == FallDetector.ETAT_CHUTE

    # Simulation impact immédiat (dans la fenêtre)
    alerte = detecteur.traiter_mesure(0.0, 0.0, 4.0)
    assert alerte is True, "L'alerte doit être déclenchée après l'impact"
    assert detecteur.etat == FallDetector.ETAT_ALERTE


# ---------------------------------------------------------------------------
# TU-07 : FSM — impact seul sans chute libre préalable
# ---------------------------------------------------------------------------
def test_tu07_fsm_impact_seul():
    """Impact seul sans chute libre → aucune alerte (faux positif)."""
    detecteur = FallDetector()
    assert detecteur.etat == FallDetector.ETAT_IDLE

    # Impact brutal direct (choc accidentel, pas une chute)
    alerte = detecteur.traiter_mesure(0.0, 0.0, 5.0)
    assert alerte is False, "Aucune alerte sans chute libre préalable"
    assert detecteur.etat == FallDetector.ETAT_IDLE


# ---------------------------------------------------------------------------
# TU-08 : FSM — timeout (impact après la fenêtre de 500 ms)
# ---------------------------------------------------------------------------
def test_tu08_fsm_timeout():
    """Chute libre suivie d'un impact APRÈS 600 ms → pas d'alerte (timeout)."""
    detecteur = FallDetector(fenetre_ms=500)

    # Chute libre
    detecteur.traiter_mesure(0.0, 0.0, 0.1)
    assert detecteur.etat == FallDetector.ETAT_CHUTE

    # Forcer le timestamp à 601 ms dans le passé pour simuler le timeout
    detecteur._timestamp_chute = _mock_time.ticks_ms() - 600

    # Impact après timeout — doit retourner IDLE sans alerte
    alerte = detecteur.traiter_mesure(0.0, 0.0, 4.0)
    assert alerte is False, "Aucune alerte si l'impact survient après le timeout"
    assert detecteur.etat == FallDetector.ETAT_IDLE


# ---------------------------------------------------------------------------
# TU-09 : magnitude nulle (vecteur nul)
# ---------------------------------------------------------------------------
def test_tu09_magnitude_nulle():
    """calculate_vector_magnitude(0, 0, 0) → 0.0 exact."""
    assert calculate_vector_magnitude(0, 0, 0) == 0.0


# ---------------------------------------------------------------------------
# TU-10 : composantes négatives (quadrant négatif)
# ---------------------------------------------------------------------------
def test_tu10_valeurs_negatives():
    """calculate_vector_magnitude(-1, 0, 9.81) → sqrt(1 + 0 + 9.81²)."""
    attendu = math.sqrt((-1) ** 2 + 0 ** 2 + 9.81 ** 2)
    resultat = calculate_vector_magnitude(-1, 0, 9.81)
    assert math.isclose(resultat, attendu, rel_tol=1e-9), (
        f"Attendu {attendu}, obtenu {resultat}"
    )
