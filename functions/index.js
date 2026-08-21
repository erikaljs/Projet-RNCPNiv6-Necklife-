// NeckLife : Cloud Functions
// Notifie les proches (liens acceptés) par push dès qu'un nouvel événement
// de chute est enregistré dans fallEvents

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

exports.notifierChuteDetectee = onDocumentCreated("fallEvents/{eventId}", async (event) => {
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
    });
  }));
});
