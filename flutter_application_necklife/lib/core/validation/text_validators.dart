// =============================================================================
// NeckLife — Validateurs de champs texte réutilisables
// Compatibles avec le paramètre `validator` de TextFormField
// =============================================================================

// Lettres (avec accents français), espaces, tirets et apostrophes — couvre
// des noms comme "Jean-Pierre", "O'Brien" ou "Élodie"
final RegExp _regexNomPrenom = RegExp(r"^[a-zA-ZÀ-ÖØ-öø-ÿ' -]+$");

// Chiffres, espaces, et un "+" optionnel en tête (numéros internationaux)
final RegExp _regexTelephone = RegExp(r'^\+?[0-9 ]+$');

// ---------------------------------------------------------------------------
// Valide un nom ou prénom : lettres, espaces, tirets et apostrophes
// uniquement — rejette chiffres et caractères spéciaux
// ---------------------------------------------------------------------------
String? validerNomPrenom(String? valeur) {
  if (valeur == null || valeur.trim().isEmpty) return 'Champ requis';
  if (!_regexNomPrenom.hasMatch(valeur.trim())) {
    return 'Lettres, espaces, tirets et apostrophes uniquement';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Valide un numéro de téléphone : chiffres et espaces, "+" optionnel en
// tête uniquement — rejette lettres et autres caractères
// ---------------------------------------------------------------------------
String? validerTelephone(String? valeur) {
  if (valeur == null || valeur.trim().isEmpty) return 'Champ requis';
  if (!_regexTelephone.hasMatch(valeur.trim())) {
    return 'Chiffres uniquement ("+" autorisé en début)';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Valide un numéro de téléphone optionnel : un champ vide est accepté,
// sinon le même format que validerTelephone s'applique
// ---------------------------------------------------------------------------
String? validerTelephoneOptionnel(String? valeur) {
  if (valeur == null || valeur.trim().isEmpty) return null;
  if (!_regexTelephone.hasMatch(valeur.trim())) {
    return 'Chiffres uniquement ("+" autorisé en début)';
  }
  return null;
}
