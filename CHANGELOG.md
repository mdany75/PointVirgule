# Changements

## 1.1 — 2026-10-02
### Corrigé
- Verr. Maj n'influence plus la touche décimale : sur les dispositions comme
  « Canadien – CSA », elle changeait nativement la virgule en point, et l'app
  inversait alors dans le mauvais sens.
- Les répétitions et le relâchement d'une touche suivent la décision prise à
  l'appui, même si Majuscule change entre-temps.
### Modifié
- Les tests vérifient la conversion sur toutes les dispositions de clavier
  installées sur le Mac.
- `build.sh` assemble l'app hors du dossier du projet et offre `--install`.

## 1.0 — 2026-10-01
Première version publiée.
