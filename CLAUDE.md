# CLAUDE.md — PointVirgule

Application Mac (Swift, AppKit, compilée avec `swiftc` sans Xcode) qui vit dans la barre
des menus et inverse la touche décimale du pavé numérique : virgule ⇄ point. Pour les
utilisateurs d'un clavier canadien-français qui veulent un point au pavé numérique.

Ce projet suit le standard commun des projets de Dany (`/standard-projet` le vérifie).

## Commandes

| Action | Commande |
| --- | --- |
| Construire | `./build.sh` (lance aussi les tests) |
| Construire et installer dans /Applications | `./build.sh --install` |
| Tester | `mkdir -p build && swiftc -swift-version 5 Sources/KeyRemapper.swift Sources/KeyboardLayout.swift Tests/main.swift -o build/tests && build/tests` |

Les fichiers produits vont dans `build/`, ignoré par git. Rien de compilé n'est commité.
`build.sh` assemble l'app dans un dossier temporaire, car iCloud Drive ajoute aux dossiers
des attributs que `codesign` refuse.

## Publier une version

Dans cet ordre :

1. Mettre le numéro à jour dans `Resources/Info.plist` (`CFBundleShortVersionString`, et
   incrémenter `CFBundleVersion`) et ajouter la section `## X.Y — date` dans `CHANGELOG.md`.
2. `git add -A && git commit -m "Version X.Y" && git push origin main`
3. `./build.sh` (produit `build/PointVirgule.dmg`, signé Developer ID et notarisé : attend la
   réponse d'Apple, quelques minutes)
4. `git tag -a vX.Y -m "Version X.Y" && git push origin vX.Y`
5. `gh release create vX.Y "build/PointVirgule.dmg" --title "PointVirgule X.Y" --notes "$(~/.claude/skills/standard-projet/scripts/notes-version.sh X.Y)"`

Le README pointe vers `releases/latest/download/PointVirgule.dmg`.

## Règles

- Répondre et écrire (commits, README, textes de l'interface) en français.
- `build.sh` signe avec le certificat « Developer ID Application » de Dany (trousseau) et
  notarise l'image disque (profil `notarisation` de `notarytool`) : l'autorisation
  Accessibilité survit alors aux mises à jour. Sans certificat, signature ad hoc : macOS
  exige de redonner l'autorisation après chaque mise à jour (bouton « Réinitialiser
  l'autorisation » dans l'app) ; le Lisez-moi et le README doivent continuer d'expliquer ce
  cas. `SKIP_NOTARIZE=1` pour un essai rapide ; ne jamais publier une image non notarisée.
- Les tests ne posent aucun événement clavier et n'installent aucun intercepteur : ils
  appellent `KeyRemapper.transform` sur des événements construits, pour chaque disposition
  installée. Toute modification de la conversion doit les faire passer.
- Ne jamais lancer `build.sh` pour vérifier une modification de l'app installée sans
  prévenir : `--install` remplace `/Applications/PointVirgule.app` et quitte l'app.
- Avant de pousser une fonctionnalité : README et CHANGELOG à jour, capture d'écran
  (`docs/capture.png`) refaite si l'interface a changé, et une nouvelle version si ce qu'on
  installe a changé.
- Pousser sur `main` directement.

## Organisation

- `Sources/` : code de l'app. `KeyRemapper.swift` intercepte et convertit la touche,
  `KeyboardLayout.swift` lit la disposition de clavier, `AppDelegate.swift` gère la barre
  des menus, `SettingsWindowController.swift` la fenêtre de réglages.
- `Tests/` : vérification de la conversion sur toutes les dispositions installées.
- `Resources/` : `Info.plist` et `Lisez-moi.txt` (inclus dans l'image disque).
- `scripts/make_icon.swift` : dessine l'icône de l'app.
- `docs/` : capture d'écran.
- `build/` : fichiers produits, ignoré par git.
