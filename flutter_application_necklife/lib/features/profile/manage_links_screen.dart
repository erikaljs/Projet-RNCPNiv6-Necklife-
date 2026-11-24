// =============================================================================
// NeckLife — Écran "Modifier les liaisons"
// Liste des proches suivis par l'aidant : retrait du lien et modification
// du numéro de téléphone attribué localement (voir link_code_service.dart)
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/link_code_service.dart';
import '../../core/validation/text_validators.dart';

class ManageLinksScreen extends StatefulWidget {
  const ManageLinksScreen({super.key});

  @override
  State<ManageLinksScreen> createState() => _ManageLinksScreenState();
}

class _ManageLinksScreenState extends State<ManageLinksScreen> {
  final LinkCodeService _linkCodeService = LinkCodeService();

  // ---------------------------------------------------------------------------
  // Confirme puis retire le lien de suivi — le proche disparaît de l'accueil
  // tant qu'un nouveau code de liaison n'est pas utilisé
  // ---------------------------------------------------------------------------
  Future<void> _confirmerSuppression(String linkId, String nom) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retirer ce proche ?'),
        content: Text(
          'Vous ne suivrez plus les alertes de $nom. Un nouveau code de '
          'liaison sera nécessaire pour le suivre à nouveau.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Retirer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirme == true) {
      await _linkCodeService.supprimerLienSuivi(linkId);
    }
  }

  // ---------------------------------------------------------------------------
  // Dialogue de modification du numéro local attribué à ce proche
  // ---------------------------------------------------------------------------
  Future<void> _modifierNumeroLocal(String followedUid, String nom) async {
    final aidantUid = FirebaseAuth.instance.currentUser?.uid;
    if (aidantUid == null) return;

    final contactActuel =
        await _linkCodeService.ecouterContactLocal(aidantUid, followedUid).first;
    final controleur = TextEditingController(
      text: contactActuel?['telephoneLocal'] as String? ?? '',
    );
    final formKey = GlobalKey<FormState>();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Numéro local pour $nom'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controleur,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Numéro'),
            validator: validerTelephone,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final numero = controleur.text.trim();
              Navigator.pop(dialogContext);
              await _linkCodeService.definirTelephoneLocal(
                followerUid: aidantUid,
                followedUid: followedUid,
                telephone: numero,
              );
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Modifier les liaisons')),
      body: uid == null
          ? const SizedBox.shrink()
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _linkCodeService.ecouterProchesSuivis(uid),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final proches = snapshot.data!;
                if (proches.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucun proche suivi pour l\'instant.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: proches.length,
                  itemBuilder: (context, index) {
                    final proche = proches[index];
                    final nom = proche['nom'] as String? ?? 'Proche';
                    final procheUid = proche['uid'] as String;
                    final linkId = proche['linkId'] as String;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.person, color: Color(0xFFF68FFA)),
                        title: Text(nom),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.phone_forwarded_outlined),
                              tooltip: 'Numéro local',
                              onPressed: () => _modifierNumeroLocal(procheUid, nom),
                            ),
                            IconButton(
                              icon: const Icon(Icons.link_off, color: Colors.red),
                              tooltip: 'Retirer',
                              onPressed: () => _confirmerSuppression(linkId, nom),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
