"""
NeckLife - main.py
Point d'entree du firmware. Relie l'IMU (MPU6050), le buzzer, le bouton
et le module fall_detector.py (deja valide par les tests unitaires).
Comportement :
  - Detection de chute (chute libre + impact) -> le buzzer sonne
  - Appui bouton -> coupe le buzzer, reinitialise le detecteur, pause 10 secondes
  - Apres 10 secondes -> surveillance reprise
"""

from machine import Pin, I2C, PWM
import time
from fall_detector import FallDetector, calculate_vector_magnitude
from ble_server import BleServer
# --- Configuration pins ---
SCL_PIN = 7
SDA_PIN = 6
BUZZER_PIN = 10
BOUTON_PIN = 3

# --- Configuration IMU (MPU6050) ---
MPU_ADDR = 0x68
PWR_MGMT_1 = 0x6B
ACCEL_XOUT_H = 0x3B
G = 9.81  # conversion g -> m/s^2 (unite attendue par fall_detector.py)

# --- Configuration buzzer/bouton ---
FREQUENCE_BUZZER = 2500
PAUSE_APRES_ARRET_MS = 10000  # 10 secondes
INTERVALLE_AFFICHAGE_MS = 200  # frequence d'affichage debug dans le terminal

# --- Initialisation IMU ---
i2c = I2C(0, scl=Pin(SCL_PIN), sda=Pin(SDA_PIN), freq=400000)
print("Scan I2C :", [hex(a) for a in i2c.scan()])
i2c.writeto_mem(MPU_ADDR, PWR_MGMT_1, b'\x00')
time.sleep_ms(100)

# --- Initialisation buzzer/bouton ---
buzzer = PWM(Pin(BUZZER_PIN))
buzzer.freq(FREQUENCE_BUZZER)
buzzer.duty(0)  # force le buzzer eteint des l'init

bouton = Pin(BOUTON_PIN, Pin.IN, Pin.PULL_UP)


def buzzer_on():
    buzzer.duty(512)


def buzzer_off():
    buzzer.duty(0)


def lire_word_signe(data, offset):
    valeur = (data[offset] << 8) | data[offset + 1]
    if valeur >= 0x8000:
        valeur -= 0x10000
    return valeur


def lire_acceleration_ms2():
    """Retourne ax, ay, az en m/s^2 (unite attendue par fall_detector.py)."""
    data = i2c.readfrom_mem(MPU_ADDR, ACCEL_XOUT_H, 6)
    ax = (lire_word_signe(data, 0) / 16384.0) * G
    ay = (lire_word_signe(data, 2) / 16384.0) * G
    az = (lire_word_signe(data, 4) / 16384.0) * G
    return ax, ay, az


NOMS_ETAT = {0: "IDLE", 1: "CHUTE", 2: "ALERTE"}

# --- Etats systeme (au-dessus de la logique interne du FallDetector) ---
MODE_SURVEILLANCE = 0
MODE_ALARME = 1
MODE_PAUSE = 2
NOMS_MODE = {0: "SURVEILLANCE", 1: "ALARME", 2: "PAUSE"}

def gerer_commande_ble(commande):
    if commande == "TEST_BUZZER":
        buzzer_on()
        time.sleep_ms(300)
        buzzer_off()

detecteur = FallDetector(fenetre_ms=500)
ble = BleServer(sur_commande=gerer_commande_ble)
mode = MODE_SURVEILLANCE
debut_pause = None
etat_bouton_precedent = 1
dernier_affichage = 0
magnitude_min_periode = 9999.0
magnitude_max_periode = 0.0

print("Systeme NeckLife demarre. Surveillance en cours...")

while True:
    maintenant = time.ticks_ms()

    # --- Lecture bouton (edge detection, TOUJOURS active) ---
    etat_bouton_actuel = bouton.value()
    appui_detecte = (etat_bouton_precedent == 1 and etat_bouton_actuel == 0)
    etat_bouton_precedent = etat_bouton_actuel

    if appui_detecte:
        print(">>> Bouton appuye (mode actuel :", NOMS_MODE[mode], ")")
        buzzer_off()
        detecteur.reinitialiser()
        debut_pause = maintenant
        mode = MODE_PAUSE
        print("Alarme coupee. Pause de 10 secondes...")
        time.sleep_ms(200)  # anti-rebond

    # --- Lecture IMU ---
    ax, ay, az = lire_acceleration_ms2()
    magnitude = calculate_vector_magnitude(ax, ay, az)

    if magnitude < magnitude_min_periode:
        magnitude_min_periode = magnitude
    if magnitude > magnitude_max_periode:
        magnitude_max_periode = magnitude

    # --- Affichage debug periodique ---
    if time.ticks_diff(maintenant, dernier_affichage) >= INTERVALLE_AFFICHAGE_MS:
        print("magnitude={:.2f} | min={:.2f} | max={:.2f} | mode={} | etat={}".format(
            magnitude, magnitude_min_periode, magnitude_max_periode,
            NOMS_MODE[mode], NOMS_ETAT[detecteur.etat]))
        dernier_affichage = maintenant
        magnitude_min_periode = 9999.0
        magnitude_max_periode = 0.0

    if mode == MODE_SURVEILLANCE:
        alerte = detecteur.traiter_mesure(ax, ay, az)
        if alerte:
            print("!!! CHUTE DETECTEE !!! Declenchement de l'alarme.")
            buzzer_on()
            mode = MODE_ALARME
            ble.notifier_chute()
    elif mode == MODE_PAUSE:
        if time.ticks_diff(maintenant, debut_pause) >= PAUSE_APRES_ARRET_MS:
            mode = MODE_SURVEILLANCE
            print("Pause terminee : surveillance reprise.")

    time.sleep_ms(20)

