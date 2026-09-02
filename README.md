# MacintoshHDisTooSmall

Application macOS (SwiftUI, macOS 14+) qui déplace des applications hors de `/Applications`
vers un autre volume — avec leurs caches et fichiers de configuration — et sait tout remettre
exactement où c'était.

## Ce que fait l'app

- Liste les apps de `/Applications` et `/Applications/Utilities` avec leur poids réel
  (bundle + caches + configurations), calculé en tâche de fond.
- Tri par nom (A→Z, Z→A) ou par poids total (croissant, décroissant), filtre et recherche.
- Déplace le bundle `.app` vers `<destination>/Applications/`, et les fichiers annexes vers
  `<destination>/<Dossier>/`, un dossier par type — miroir de `/Applications` et `~/Library` un
  niveau plus bas, partagé par toutes les apps envoyées vers cette destination — en laissant un
  lien symbolique à leur place pour que l'app continue de fonctionner :

  | Emplacement d'origine                  | Dossier de destination | Déplacé |
  |----------------------------------------|-------------------------|---------|
  | `/Applications/<App>.app`              | `Applications/`         | oui |
  | `~/Library/Application Support/<app>`  | `ApplicationSupport/`   | oui |
  | `~/Library/Caches/<app>`               | `Caches/`               | oui |
  | `~/Library/Containers/<bundle-id>`     | `Containers/`           | oui |
  | `~/Library/Logs/<app>`                 | `Logs/`                 | oui |
  | `~/Library/Saved Application State/…`  | `SavedApplicationState/`| oui |
  | `~/Library/HTTPStorages/<bundle-id>`   | `HTTPStorages/`         | oui |
  | `~/Library/WebKit/<bundle-id>`         | `WebKit/`               | oui |
  | `~/Library/Preferences/<bundle-id>.plist` | —                    | **non — voir plus bas** |

  Exemple, pour la destination `/Volumes/2To/Apps` :

  ```
  /Volumes/2To/Apps/
  ├── Applications/Toto.app
  ├── ApplicationSupport/Toto
  ├── Caches/Toto
  └── Logs/Toto
  ```

  Les apps déplacées avant la 0.2.2 gardent leur ancienne disposition (un dossier par app) ;
  seuls les nouveaux déplacements utilisent cette structure partagée.

- Restaure : retire les liens, remet chaque élément à son emplacement d'origine, nettoie le
  dossier de destination.
- Supprime : envoie à la corbeille le bundle et les fichiers annexes cochés, que l'app soit
  encore dans `/Applications` ou déjà déplacée (les liens laissés derrière sont retirés).
- Adopte : une app déjà déplacée par d'autres moyens (script, Finder…) apparaît « Non suivie »
  dans la liste. Le bouton « Considérer comme déplacée » l'ajoute au journal telle quelle — sans
  déplacer un seul fichier — pour pouvoir ensuite la restaurer ou la supprimer depuis l'app.
- Répartition (bouton dans la barre d'outils) : camembert de l'espace occupé par les apps sur
  le disque contre celles déplacées (suivies ou simplement orphelines), avec le détail par
  volume de destination et un filtre pour n'en isoler qu'un.

## Réglages

- **Destination par défaut** : n'importe quel dossier hors de `/Applications`, `/System` et
  `/Library`. C'est celle que propose le bouton « Déplacer » ; le menu à côté du bouton permet
  d'envoyer une app précise ailleurs sans changer le réglage.
- **Lien symbolique dans `/Applications`** (activé par défaut) : l'app reste visible et
  lançable depuis le Dock, Spotlight et le Launchpad. Désactivé, `/Applications` est
  réellement vidé et l'app se lance depuis son nouvel emplacement. Les caches et
  configurations sont eux **toujours** remplacés par un lien — sans ça l'app les recrée
  immédiatement et rien n'est gagné.

## Points d'attention

- **Les préférences ne sont jamais déplacées.** `cfprefsd` réécrit les `.plist` de
  `~/Library/Preferences` et remplace un lien symbolique par un vrai fichier, ce qui perdrait
  la configuration. Ces fichiers font quelques kilo-octets, le gain serait nul.
- **Volume démonté = app cassée.** Si la destination est un disque externe non monté, le lien
  dans `/Applications` pointe dans le vide. L'app le signale dans le panneau de détail.
- **Droits administrateur.** Certaines apps appartiennent à `root`. Quand une opération échoue
  pour cause de permissions, l'app corrige d'abord la propriété de l'élément concerné
  (`chown -R <toi>:<groupe déjà utilisé à cet endroit>`, par exemple `joe:admin` pour une app
  de `/Applications`) puis rejoue la même opération normalement. C'est la seule chose qui
  s'exécute en root ; le déplacement lui-même se fait ensuite sous ton compte, donc le résultat
  t'appartient — pas de dossier ou de lien fantôme appartenant à `root` à traiter à nouveau la
  prochaine fois. Si cette correction ne suffit pas, tout le reste du lot est rejoué en une
  seule fois via `osascript … with administrator privileges`, comme avant.
- **Détection des fichiers annexes.** Le rapprochement se fait sur le nom exact du dossier
  (identifiant de bundle, puis nom de l'app) — jamais de correspondance approximative. La
  liste est présentée avec cases à cocher : rien n'est déplacé sans validation.
- **Accès disque complet.** Quelques sous-dossiers de `~/Library` sont protégés par TCC. Si un
  déplacement échoue là-dessus, accorder « Accès complet au disque » à l'app dans
  Réglages Système → Confidentialité et sécurité.
- **Le déplacement inter-volumes ne préserve ni le propriétaire ni les attributs étendus.**
  Une app de `/Applications` appartient souvent à `root:wheel` : la recopier à l'identique
  demanderait des droits root, et échouerait quand même sur `com.apple.provenance`, un
  attribut étendu que macOS refuse d'écrire même à root. La copie se fait donc sans eux
  (`cp -RX`) — l'app t'appartiendra et se lancera normalement. À l'intérieur d'un même
  volume, c'est un simple renommage.
- **Oublier une entrée.** Si le journal ne décrit plus la réalité (app remise en place à la
  main, déplacement interrompu), le menu « … » du panneau d'une app déplacée permet d'oublier
  son entrée sans toucher au moindre fichier.
- **Adopter une app orpheline.** L'inverse d'oublier une entrée : une app déjà symlinkée dans
  `/Applications` mais absente du journal (déplacée par un autre outil, ou après une
  réinstallation de MacintoshHDisTooSmall) se voit proposer « Considérer comme déplacée », avec
  la liste des fichiers annexes eux-mêmes déjà symlinkés ailleurs. Un lien mort (cible
  disparue) n'est jamais proposé. Rien n'est déplacé : seul le journal change. Tant que l'app
  n'est pas adoptée, la supprimer ne retire que le lien dans `/Applications` — le bundle réel,
  ailleurs, n'est pas touché.
- **Suppression et droits root.** La suppression passe par la corbeille, donc reste réversible.
  Exception : si l'opération réclame les droits administrateur, elle est rejouée en `rm -rf` —
  la corbeille n'est pas utilisable en root. Le dialogue de confirmation le rappelle.
- L'app n'est pas sandboxée (elle doit écrire dans `/Applications` et `~/Library`).

Le journal des déplacements est stocké dans
`~/Library/Application Support/MacintoshHDisTooSmall/ledger.json`, et une copie du manifeste
de chaque app est déposée dans `<destination>/.macintoshhd/<NomDeLApp>.json` — un fichier par
app, puisque plusieurs apps partagent désormais les mêmes dossiers de destination.

## Compiler

```bash
./build.sh 0.2.5
```

Produit `dist/MacintoshHDisTooSmall.app` (universel arm64 + x86_64) et son zip.
Nécessite Xcode / les Command Line Tools (Swift 5.9+).

## Installer depuis une release

Le binaire est signé ad hoc, pas notarisé — macOS le met en quarantaine au téléchargement :

```bash
xattr -dr com.apple.quarantine /Applications/MacintoshHDisTooSmall.app
```

## Licence

MIT.
