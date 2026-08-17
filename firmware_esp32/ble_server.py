"""
NeckLife ble_server.py
Serveur BLE (peripherique GATT) pour le collier NeckLife.
Diffuse le service NeckLife et permet a l'app Flutter de :
  - recevoir une notification "CHUTE_DETECTEE" (caracteristique alerte)
  - envoyer des commandes comme "TEST_BUZZER" (caracteristique commandes)

UUID et format alignes sur flutter_application_necklife/lib/core/ble/ble_manager.dart
"""

import bluetooth
from micropython import const
import struct

# --- Evenements IRQ BLE ---
_IRQ_CENTRAL_CONNECT = const(1)
_IRQ_CENTRAL_DISCONNECT = const(2)
_IRQ_GATTS_WRITE = const(3)

# --- UUID (doivent correspondre exactement a ble_manager.dart) ---
_UUID_SERVICE_NECKLIFE = bluetooth.UUID("12345678-1234-1234-1234-123456789abc")
_UUID_CARAC_ALERTE = bluetooth.UUID("12345678-1234-1234-1234-123456789abd")
_UUID_CARAC_COMMANDES = bluetooth.UUID("12345678-1234-1234-1234-123456789abe")

# --- Flags des caracteristiques (norme BLE GATT) ---
_FLAG_READ = const(0x0002)
_FLAG_WRITE = const(0x0008)
_FLAG_NOTIFY = const(0x0010)

_CARAC_ALERTE = (
    _UUID_CARAC_ALERTE,
    _FLAG_READ | _FLAG_NOTIFY,
)
_CARAC_COMMANDES = (
    _UUID_CARAC_COMMANDES,
    _FLAG_WRITE,
)
_SERVICE_NECKLIFE = (
    _UUID_SERVICE_NECKLIFE,
    (_CARAC_ALERTE, _CARAC_COMMANDES),
)

NOM_COLLIER = "NeckLife-Collier"


def _construire_payload(champs):
    """Construit un payload BLE (liste de tuples (type_champ, valeur))."""
    payload = bytearray()
    for type_champ, valeur in champs:
        payload.extend(struct.pack("BB", len(valeur) + 1, type_champ) + valeur)
    return payload


def _construire_adv_data(uuids=None):
    """Paquet d'advertising principal : flags + UUID service (max 31 octets)."""
    champs = [(0x01, struct.pack("B", 0x06))]  # flags : BLE uniquement, decouvrable
    if uuids:
        for uuid in uuids:
            champs.append((0x07, bytes(uuid)))  # UUID service complet (128 bits)
    return _construire_payload(champs)


def _construire_resp_data(nom):
    """Paquet de scan response : le nom du collier (paquet separe, max 31 octets)."""
    return _construire_payload([(0x09, nom.encode())])


class BleServer:
    def __init__(self, nom=NOM_COLLIER, sur_commande=None):
        """
        sur_commande : fonction callback(commande: str) appelee quand une
        commande est recue depuis l'app (ex: "TEST_BUZZER")
        """
        self._ble = bluetooth.BLE()
        self._ble.active(True)
        self._ble.irq(self._irq)

        ((self._handle_alerte, self._handle_commandes),) = self._ble.gatts_register_services(
            (_SERVICE_NECKLIFE,)
        )

        self._connexions = set()
        self._sur_commande = sur_commande
        self._nom = nom

        self._demarrer_advertising()
        print("BLE demarre, diffusion en tant que", nom)

    def _demarrer_advertising(self):
        adv_data = _construire_adv_data(uuids=[_UUID_SERVICE_NECKLIFE])
        resp_data = _construire_resp_data(self._nom)
        self._ble.gap_advertise(100000, adv_data=adv_data, resp_data=resp_data)  # intervalle ~100ms

    def _irq(self, event, data):
        if event == _IRQ_CENTRAL_CONNECT:
            conn_handle, _, _ = data
            self._connexions.add(conn_handle)
            print("App connectee, handle =", conn_handle)

        elif event == _IRQ_CENTRAL_DISCONNECT:
            conn_handle, _, _ = data
            self._connexions.discard(conn_handle)
            print("App deconnectee, handle =", conn_handle)
            self._demarrer_advertising()  # relancer pour permettre une reconnexion

        elif event == _IRQ_GATTS_WRITE:
            conn_handle, attr_handle = data
            if attr_handle == self._handle_commandes:
                valeur = self._ble.gatts_read(self._handle_commandes)
                commande = valeur.decode().strip()
                print("Commande recue :", commande)
                if self._sur_commande:
                    self._sur_commande(commande)

    def notifier_chute(self):
        """A appeler quand fall_detector.py detecte une chute."""
        message = b"CHUTE_DETECTEE"
        self._ble.gatts_write(self._handle_alerte, message)
        for conn_handle in self._connexions:
            self._ble.gatts_notify(conn_handle, self._handle_alerte, message)

    def est_connecte(self):
        return len(self._connexions) > 0

