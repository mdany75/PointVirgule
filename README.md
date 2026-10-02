# PointVirgule

Petite app macOS qui inverse la touche décimale du pavé numérique : si elle
tape une virgule, elle tapera un point; si elle tape un point, elle tapera une
virgule. Les autres touches du clavier ne changent pas.

<p align="center">
  <img src="docs/reglages.png" width="600" alt="Fenêtre de réglages de PointVirgule : inversion activée, ouverture automatique à l'ouverture de session et autorisation Accessibilité accordée">
</p>

- Verr. Maj n'a aucun effet sur cette touche.
- Sur les claviers où Majuscule change le caractère de la touche
  (Canadien – CSA, français…), Majuscule + la touche tape l'autre caractère.
- L'app vit dans la barre des menus; son icône peut être masquée.
- Elle peut s'ouvrir automatiquement à l'ouverture de session.

Requiert macOS 13 (Ventura) ou plus récent, sur Mac Apple Silicon ou Intel.

## Installation

1. Téléchargez [PointVirgule.dmg](build/PointVirgule.dmg) et ouvrez-le.
2. Glissez PointVirgule dans le dossier Applications, puis ouvrez-la.
3. macOS bloque la première ouverture, car l'app n'est pas distribuée par
   l'App Store : allez dans Réglages Système > Confidentialité et sécurité et
   cliquez sur « Ouvrir quand même ».
4. Accordez l'autorisation « Accessibilité » demandée par l'app. macOS l'exige
   pour qu'une app puisse modifier une touche.

Le détail de chaque étape, le dépannage et la désinstallation sont dans
[Lisez-moi.txt](Resources/Lisez-moi.txt), aussi inclus dans l'image disque.

Après une mise à jour de l'app, macOS exige de redonner l'autorisation : dans
la fenêtre de PointVirgule, cliquez sur « Réinitialiser l'autorisation », puis
accordez-la de nouveau.

## Construction

Seuls les outils de ligne de commande d'Apple sont requis
(`xcode-select --install`); Xcode n'est pas nécessaire.

```bash
./build.sh
```

lance les tests, compile l'app et crée `build/PointVirgule.dmg`.

```bash
./build.sh --install
```

fait la même chose, puis installe l'app dans `/Applications` et l'ouvre.

## Organisation

- `Sources/` : le code de l'app (Swift, AppKit).
  - `KeyRemapper.swift` : interception et conversion de la touche.
  - `KeyboardLayout.swift` : lecture de la disposition de clavier active.
- `Tests/` : vérifie la conversion sur toutes les dispositions de clavier
  installées sur le Mac.
- `Resources/` : `Info.plist` et le Lisez-moi inclus dans l'image disque.
- `scripts/make_icon.swift` : dessine l'icône de l'app.
