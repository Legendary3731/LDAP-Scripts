# ldap-scripts

Suite de scripts shell pour administrer des comptes utilisateurs dans un
annuaire LDAP, avec gestion optionnelle de Kerberos et des répertoires
personnels. Une commande par opération, une seule configuration pour tout
l'ensemble, et rien de spécifique à un domaine ou à une infrastructure
donnée : tout ce qui varie d'un site à l'autre est un paramètre.

```
$ ldapadduser jdupont Jean Dupont

Compte à créer ---------------------------------------------------------
  Login                  jdupont
  Nom complet            Jean Dupont
  DN                     uid=jdupont,ou=people,dc=example,dc=com
  UID / GID              10007 / 10007
  Groupe primaire        jdupont (à créer)
  Mail                   jdupont@example.com
  Shell                  /bin/bash
  Répertoire             /srv/nfs/home/jdupont (vu comme /home/jdupont)
  Kerberos               jdupont@EXAMPLE.COM

Créer ce compte ? [o/N]
```

## Commandes

| Commande | Rôle |
|---|---|
| `ldapadduser <login> [prénom] [nom]` | Crée le compte : entrée LDAP, groupe, principal Kerberos, répertoire personnel |
| `ldapdeleteuser <login>...` | Supprime le compte et archive son répertoire (rien n'est détruit par défaut) |
| `ldapsetpasswd <login>` | Change le mot de passe, côté Kerberos et/ou côté annuaire |
| `ldapfinger <login>` | État complet d'un compte et diagnostic de cohérence |
| `lsldap [motif]` | Liste les comptes ou les groupes, avec contrôle de cohérence |
| `ldapconfig <show\|check\|init\|files\|params\|edit>` | Inspecte, teste et génère la configuration |

Chaque commande accepte `--help`, `--dry-run` (simulation complète sans rien
modifier) et `-o NOM=VALEUR` pour surcharger n'importe quel paramètre le temps
d'une exécution.

## Installation

À faire en root **sur la machine qui administre l'annuaire** : celle qui voit
le serveur LDAP, et qui héberge le KDC et les répertoires personnels quand ces
fonctions sont activées. Ce n'est pas un outil client ; le poste sur lequel tu
édites ces fichiers n'a rien à installer.

```bash
./install.sh                                   # PREFIX=/usr/local par défaut
./install.sh --sysconfdir /etc/ldap-scripts    # config dans /etc (usuel sous Debian)
./install.sh --prefix /opt/ldap-scripts
./install.sh --dry-run                         # voir ce qui serait écrit
./install.sh --uninstall

ldapconfig init                   # génère la configuration
ldapconfig check                  # vérifie qu'elle est utilisable
```

La complétion bash est installée par défaut (`--no-completion` pour s'en
passer), et `./install.sh --check` vérifie la syntaxe des scripts. Un
`Makefile` est fourni pour ceux qui tapent `make install` par habitude : il ne
fait que déléguer à `install.sh`, avec les variables `PREFIX`, `DESTDIR`,
`SYSCONFDIR` habituelles.

Les fichiers atterrissent dans `<PREFIX>/sbin`, `<PREFIX>/lib/ldap-scripts` et
`<SYSCONFDIR>` (par défaut `<PREFIX>/etc/ldap-scripts`). L'installation
n'écrase jamais une configuration existante et injecte les chemins réels dans
les scripts, qui n'ont donc besoin d'aucune variable d'environnement pour
fonctionner. Changer `--sysconfdir` après coup impose donc de relancer
l'installation, pas seulement de déplacer le fichier.

Prérequis : `bash` 4.1+, les clients OpenLDAP (`ldapsearch`, `ldapadd`, …) et,
selon la configuration, `slappasswd` et `kadmin.local`. Ni `make` ni aucun
outil de compilation ne sont nécessaires.

Les scripts fonctionnent aussi directement depuis l'arborescence source, sans
installation : ils retrouvent la bibliothèque relativement à leur propre
emplacement (`../lib/`), et `LDAP_SCRIPTS_CONF` désigne la configuration.
Pratique pour tester en `--dry-run` avant d'installer quoi que ce soit.

## Configuration

Un seul fichier suffit : `<SYSCONFDIR>/ldap-scripts.conf`. Tout paramètre
absent garde son défaut, listé dans `lib/defaults.sh` et consultable avec
`ldapconfig params`. La référence complète est dans
[CONFIGURATION.md](CONFIGURATION.md).

Le strict minimum pour un annuaire OpenLDAP classique :

```bash
BASE_DN="dc=example,dc=com"
LDAP_URI="ldap://ldap.example.com"
BIND_DN="cn=admin,dc=example,dc=com"
USER_PASSWORD_MODE="hash"   # mots de passe dans l'annuaire, pas de Kerberos
KRB5_ENABLED=0
```

Les valeurs se combinent par couches, de la moins prioritaire à la plus
prioritaire :

```
lib/defaults.sh  <  ldap-scripts.conf  <  conf.d/*.conf  <  ~/.config/...
                 <  $LDAP_SCRIPTS_CONF  <  variables d'environnement
                 <  options -o NOM=VALEUR
```

Concrètement :

```bash
# Une machine, plusieurs annuaires
ldapconfig check --config /etc/ldap-scripts/recette.conf
lsldap --config /etc/ldap-scripts/recette.conf

# Un réglage ponctuel, sans toucher au fichier
ldapadduser -o UID_MIN=20000 -o HOME_ROOT=/srv/exports/home invite Invité Temporaire

# Depuis un script, sans saisie interactive
LDAP_AUTH=file LDAP_BIND_PASSWORD_FILE=/etc/ldap-scripts/bind.secret \
    ldapadduser --yes --random-password jdupont Jean Dupont
```

### Ce qui est configurable

Tout ce qui varie d'un site à l'autre, notamment :

- **Annuaire** : URI, base, branches utilisateurs et groupes, attribut
  d'identifiant, filtres de recherche, TLS (StartTLS ou LDAPS), méthode
  d'authentification (saisie, fichier, variable d'environnement, SASL, anonyme).
- **Comptes** : plage et mode d'attribution des UID, shell, forme du `cn`, de
  l'adresse mail et du chemin du répertoire, validation des logins, classes
  d'objets et attributs supplémentaires.
- **Groupes** : un groupe par compte, un groupe partagé, ou aucun.
- **Mots de passe** : délégation SASL/Kerberos, hachage `slappasswd`, ou aucun.
- **Kerberos** : activable, commande `kadmin` et options `addprinc`, realm,
  clé aléatoire ou mot de passe saisi, caractère bloquant ou non des échecs.
- **Répertoires personnels** : activables, emplacement réel et chemin vu par
  les clients (utile en NFS), squelette, permissions.
- **Suppression** : archivage (déplacement ou tar.gz), purge ou conservation.
- **Intégrations** : hooks avant/après chaque opération, invalidation de cache
  NSS, templates LDIF entièrement réécrivables.

### Templates LDIF

Les entrées sont produites à partir de `<SYSCONFDIR>/templates/user.ldif` et
`group.ldif`. Toute variable de configuration s'y utilise sous la forme
`{{NOM}}`, y compris celles que tu ajoutes toi-même :

```bash
# dans ldap-scripts.conf
ETABLISSEMENT="Lycée Jean Moulin"
```

```ldif
# dans templates/user.ldif
o: {{ETABLISSEMENT}}
```

Une ligne dont la valeur est vide après substitution est automatiquement
supprimée : les attributs optionnels ne produisent jamais de LDIF invalide.

## Points de conception

- **Aucun mot de passe sur la ligne de commande.** Les mots de passe transitent
  par un fichier temporaire en `0600` passé à `-y`, supprimé par un `trap` en
  sortie ; côté Kerberos, ils sont envoyés sur l'entrée standard de `kadmin`
  plutôt qu'avec `cpw -pw`, qui les exposerait dans `ps`.
- **Vérification réelle du succès de `kadmin`.** Son code de retour vaut 0 même
  quand la saisie du mot de passe échoue : le script contrôle le message
  `Principal "..." created` et réessaie (`KRB5_MAX_RETRIES`).
- **Rollback.** Si la création du principal Kerberos échoue alors que
  `KRB5_REQUIRED=1`, l'entrée LDAP déjà créée est supprimée.
- **Rien n'est détruit par défaut.** À la suppression d'un compte, le
  répertoire personnel est archivé, pas effacé.
- **Simulation intégrale.** `--dry-run` affiche le LDIF et toutes les commandes
  qui seraient exécutées, sans aucune écriture.
- **Diagnostic.** `ldapconfig check` teste la configuration de bout en bout ;
  `ldapfinger` et `lsldap` signalent les comptes dont le principal Kerberos ou
  le répertoire manquent.

## Limites connues

- Pas de gestion des groupes secondaires au-delà de l'appartenance au groupe
  partagé (`GROUP_MODE=shared`).
- Pas de renommage de compte (`ldaprenameuser`).
- Le calcul du prochain UID n'est pas protégé contre deux créations
  simultanées ; sans conséquence pour un usage d'administration manuel.
- Les modifications d'attributs d'un compte existant passent encore par
  `ldapmodify`.
