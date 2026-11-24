// NeckLife : Cloud Functions
// Notifie les proches (liens acceptés) par push dès qu'un nouvel événement
// de chute est enregistré dans fallEvents

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

exports.notifierChuteDetectee = onDocumentCreated(
    {document: "fallEvents/{eventId}", region: "europe-west1"},
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) return;

      const donneesEvenement = snapshot.data();
      const uidPorteur = donneesEvenement.uid;
      if (!uidPorteur) return;

      const firestore = getFirestore();

      // Nom du porteur du collier pour le corps de la notification
      const porteurDoc = await firestore.collection("users").doc(uidPorteur).get();
      const nomPorteur = porteurDoc.data()?.nom || "Un proche";

      // Tous les liens acceptés où ce porteur est suivi
      const liensSnapshot = await firestore
          .collection("links")
          .where("followedUid", "==", uidPorteur)
          .where("status", "==", "accepted")
          .get();

      if (liensSnapshot.empty) return;

      const messaging = getMessaging();

      await Promise.all(liensSnapshot.docs.map(async (lienDoc) => {
        const followerUid = lienDoc.data().followerUid;
        const followerDoc = await firestore.collection("users").doc(followerUid).get();
        const fcmToken = followerDoc.data()?.fcmToken;
        if (!fcmToken) return;

        await messaging.send({
          token: fcmToken,
          notification: {
            title: "Alerte chute",
            body: `${nomPorteur} a peut-être fait une chute.`,
          },
          // Priorité haute + canal dédié : nécessaire pour un affichage fiable
          // côté Android quand l'app est en arrière-plan ou fermée (voir
          // firebaseMessagingBackgroundHandler dans main.dart et le canal
          // "necklife_alertes" déclaré dans AndroidManifest.xml)
          android: {
            priority: "high",
            notification: {
              channelId: "necklife_alertes",
              sound: "default",
            },
          },
        });
      }));
    },
);

// Agrège les événements de chute des 7 derniers jours de l'utilisateur
// appelant en un résumé chiffré (compétence RGPD : donnée dérivée calculée
// côté serveur à partir de données déjà consenties par l'utilisateur, jamais
// de nouvelle collecte). Le résultat est à la fois persisté (weeklyStats/{uid},
// pour un historique et une lecture par un aidant suivi) et renvoyé
// directement dans la réponse, pour un affichage immédiat côté app.
exports.genererResumeHebdomadaire = onCall({region: "europe-west1"}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }

  const firestore = getFirestore();
  const maintenant = new Date();
  const periodeDebut = new Date(maintenant.getTime() - 7 * 24 * 60 * 60 * 1000);

  const snapshot = await firestore
      .collection("fallEvents")
      .where("uid", "==", uid)
      .where("timestamp", ">=", Timestamp.fromDate(periodeDebut))
      .where("timestamp", "<=", Timestamp.fromDate(maintenant))
      .get();

  let nbFausses = 0;
  let nbReelles = 0;
  let nbEnAttente = 0;

  snapshot.forEach((doc) => {
    const statut = doc.data().statut || "en_attente";
    if (statut === "fausse_alerte") nbFausses++;
    else if (statut === "chute_reelle") nbReelles++;
    else nbEnAttente++;
  });

  const resume = {
    nbTotal: snapshot.size,
    nbFausses,
    nbReelles,
    nbEnAttente,
  };

  await firestore.collection("weeklyStats").doc(uid).set(
      {
        ...resume,
        periodeDebut: Timestamp.fromDate(periodeDebut),
        periodeFin: Timestamp.fromDate(maintenant),
        calculeLe: FieldValue.serverTimestamp(),
      },
      {merge: true},
  );

  // periodeDebut/periodeFin renvoyées en ISO : le protocole des Cloud
  // Functions callable ne sait pas sérialiser un Timestamp Firestore.
  return {
    ...resume,
    periodeDebut: periodeDebut.toISOString(),
    periodeFin: maintenant.toISOString(),
  };
});
