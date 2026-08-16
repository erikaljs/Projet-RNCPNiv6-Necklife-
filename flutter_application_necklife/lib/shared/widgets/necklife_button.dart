// =============================================================================
// NeckLife — Widget bouton primaire réutilisable
// Utilisé dans toutes les features pour assurer une cohérence visuelle
// =============================================================================

import 'package:flutter/material.dart';

class NecklifeButton extends StatelessWidget {
  final String label;
  final IconData? icone;
  final VoidCallback? onPressed;
  final Color couleur;
  final bool enChargement;

  const NecklifeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icone,
    this.couleur = const Color(0xFFF68FFA), // lavande NeckLife par défaut
    this.enChargement = false,
  });

  // ---------------------------------------------------------------------------
  // Choisit noir ou blanc pour le texte/l'icône selon lequel offre le
  // meilleur contraste WCAG sur la couleur de fond fournie — le bouton
  // acceptant n'importe quelle couleur (rouge, gris, lavande…), un choix
  // fixe de blanc ne suffit plus (ex : blanc sur lavande ≈ 2:1, trop faible).
  // ---------------------------------------------------------------------------
  static Color _couleurTexteLisible(Color fond) {
    double contraste(Color texte) {
      final lFond = fond.computeLuminance();
      final lTexte = texte.computeLuminance();
      final plusClair = lFond > lTexte ? lFond : lTexte;
      final plusFonce = lFond > lTexte ? lTexte : lFond;
      return (plusClair + 0.05) / (plusFonce + 0.05);
    }

    return contraste(Colors.black87) >= contraste(Colors.white)
        ? Colors.black87
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final couleurTexte = _couleurTexteLisible(couleur);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: couleur,
          foregroundColor: couleurTexte,
          disabledBackgroundColor: couleur.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 2,
        ),
        // Désactive le bouton pendant le chargement
        onPressed: enChargement ? null : onPressed,
        icon: enChargement
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: couleurTexte,
                  strokeWidth: 2,
                ),
              )
            : (icone != null ? Icon(icone) : const SizedBox.shrink()),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
