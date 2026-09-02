# MacintoshHDisTooSmall

Application macOS (SwiftUI, macOS 14+) qui déplace des applications hors de `/Applications`
vers un autre volume — avec leurs caches et fichiers de configuration — et sait tout remettre
exactement où c'était.

## Ce que fait l'app

- Liste les apps de `/Applications` et `/Applications/Utilities` avec leur taille sur disque.
- Déplace le bundle `.app` vers `<destination>/<NomDeLApp>/`.
- Trouve et déplace les fichiers annexes vers `<destination>/<NomDeLApp>/Support/`, en laissant
  un lien symbolique à leur place pour que l'app continue de fonctionner :

  | Emplacement d'origine                  | Déplacé |
  |----------------------------------------|---------|
  | `~/Library/Application Support/<app>`  | oui |
  | `~/Library/Caches/<app>`               | oui |
  | `~/Library/Containers/<bundle-id>`     | oui |
  | `~/Library/Logs/<app>`                 | oui |
  | `~/Library/Saved Application State/…`  | oui |
  | `~/Library/HTTPStorages/<bundle-id>`   | oui |
  | `~/Library/WebKit/<bundle-id>`         | oui |
  | `~/Library/Preferences/<bundle-id>.plist` | **non — voir plus bas** |

- Restaure : retire les liens, remet chaque élément à son emplacement d'origine, nettoie le
  dossier de destination.

## Réglages

- **Destination** : n'importe quel dossier hors de `/Applications`, `/System` et `/Library`.
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
  pour cause de permissions, tout le reste du lot est rejoué en une seule fois via
  `osascript … with administrator privileges` : le mot de passe n'est demandé qu'une fois.
- **Détection des fichiers annexes.** Le rapprochement se fait sur le nom exact du dossier
  (identifiant de bundle, puis nom de l'app) — jamais de correspondance approximative. La
  liste est présentée avec cases à cocher : rien n'est déplacé sans validation.
- **Accès disque complet.** Quelques sous-dossiers de `~/Library` sont protégés par TCC. Si un
  déplacement échoue là-dessus, accorder « Accès complet au disque » à l'app dans
  Réglages Système → Confidentialité et sécurité.
- L'app n'est pas sandboxée (elle doit écrire dans `/Applications` et `~/Library`).

Le journal des déplacements est stocké dans
`~/Library/Application Support/MacintoshHDisTooSmall/ledger.json`, et une copie du manifeste
est déposée dans chaque dossier de destination (`.macintoshhd-manifest.json`).

## Compiler

```bash
./build.sh 0.1
```

Produit `.dist/MacintoshHDisTooSmall.app` (universel arm64 + x86_64) et son zip.
Nécessite Xcode / les Command Line Tools (Swift 5.9+).

## Installer depuis une release

Le binaire est signé ad hoc, pas notarisé — macOS le met en quarantaine au téléchargement :

```bash
xattr -dr com.apple.quarantine /Applications/MacintoshHDisTooSmall.app
```

## Licence

MIT.
