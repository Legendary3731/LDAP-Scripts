# Référence de configuration

Tous les paramètres, leur valeur par défaut et leur effet. La liste brute est
aussi disponible avec `ldapconfig params`, et la configuration réellement
appliquée avec `ldapconfig show`.

## Où écrire quoi

| Couche | Emplacement | Usage |
|---|---|---|
| Défauts | `<LIBDIR>/defaults.sh` | Livré, ne pas modifier |
| Site | `<SYSCONFDIR>/ldap-scripts.conf` | La configuration normale |
| Fragments | `<SYSCONFDIR>/conf.d/*.conf` | Ajouts par paquet ou par rôle |
| Utilisateur | `~/.config/ldap-scripts/ldap-scripts.conf` | Réglages personnels |
| Session | `$LDAP_SCRIPTS_CONF`, `--config` | Un autre annuaire ponctuellement |
| Appel | variables d'environnement, `-o NOM=VALEUR` | Un réglage le temps d'une commande |

Chaque couche ne surcharge que ce qu'elle définit. La syntaxe est celle de
bash : `NOM="valeur"`, et les variables déjà définies sont utilisables
(`BIND_DN="cn=admin,${BASE_DN}"`).

## Comportement général

| Paramètre | Défaut | Description |
|---|---|---|
| `DRY_RUN` | `0` | `1` : simulation, aucune écriture (`--dry-run`) |
| `ASSUME_YES` | `0` | `1` : aucune confirmation interactive (`--yes`) |
| `VERBOSE` | `0` | `1` : trace les commandes exécutées |
| `QUIET` | `0` | `1` : n'affiche que les erreurs |
| `COLOR` | `auto` | `auto`, `always`, `never` |
| `REQUIRE_ROOT` | `auto` | `auto` exige root seulement si les répertoires ou un KDC local sont gérés |
| `TEMPLATE_DIR` | `<SYSCONFDIR>/templates` | Répertoire des templates LDIF |
| `TEMPLATE_USER` / `TEMPLATE_GROUP` | `<TEMPLATE_DIR>/user.ldif`, `group.ldif` | Templates à utiliser |

## Connexion à l'annuaire

| Paramètre | Défaut | Description |
|---|---|---|
| `BASE_DN` | *(vide, obligatoire)* | Base de l'annuaire |
| `LDAP_URI` | `ldap://localhost` | URI du serveur (`ldap://`, `ldaps://`, `ldapi:///`) |
| `USERS_RDN` / `GROUPS_RDN` | `ou=people`, `ou=groups` | Branches, relatives à `BASE_DN` |
| `USERS_DN` / `GROUPS_DN` | *(dérivés)* | DN complets, si les branches ne suivent pas le schéma ci-dessus |
| `LDAP_AUTH` | `prompt` | `prompt`, `password`, `file`, `env`, `sasl`, `none` |
| `BIND_DN` | `cn=admin,<BASE_DN>` | DN de connexion |
| `LDAP_BIND_PASSWORD` | *(vide)* | Mot de passe en clair (`LDAP_AUTH=password`) |
| `LDAP_BIND_PASSWORD_FILE` | *(vide)* | Fichier contenant le mot de passe (`LDAP_AUTH=file`) |
| `LDAP_BIND_PASSWORD_ENV` | `LDAP_BIND_PW` | Variable d'environnement à lire (`LDAP_AUTH=env`) |
| `LDAP_SASL_MECH` | `EXTERNAL` | Mécanisme SASL (`EXTERNAL` sur `ldapi:///`, `GSSAPI`…) |
| `LDAP_SASL_OPTS` | *(vide)* | Options SASL supplémentaires |
| `LDAP_TLS` | `none` | `none`, `starttls`, `ldaps` |
| `LDAP_TLS_CACERT` | *(vide)* | Certificat d'autorité |
| `LDAP_TLS_REQCERT` | *(vide)* | `never`, `allow`, `try`, `demand` |
| `LDAP_EXTRA_OPTS` | *(vide)* | Options brutes ajoutées à chaque commande `ldap*` |

### Schéma

| Paramètre | Défaut | Description |
|---|---|---|
| `UID_ATTR` | `uid` | Attribut portant le login |
| `USER_FILTER` | `(objectClass=posixAccount)` | Filtre identifiant un compte |
| `GROUP_ATTR` | `cn` | Attribut portant le nom du groupe |
| `GROUP_FILTER` | `(objectClass=posixGroup)` | Filtre identifiant un groupe |
| `GROUP_MEMBER_ATTR` | `memberUid` | Attribut d'appartenance |
| `FINGER_ATTRS` | `uidNumber gidNumber cn sn givenName mail homeDirectory loginShell` | Attributs affichés par `ldapfinger` |

## Comptes POSIX

| Paramètre | Défaut | Description |
|---|---|---|
| `UID_MIN` / `UID_MAX` | `10000` / `60000` | Plage d'attribution |
| `UID_ALLOCATION` | `max` | `max` (plus grand + 1) ou `first` (premier libre) |
| `DEFAULT_SHELL` | `/bin/bash` | Shell de connexion |
| `USERNAME_PATTERN` | `^[a-z_][a-z0-9_-]{0,31}$` | Validation du login, vide pour désactiver |
| `CN_PATTERN` | `%f %l` | Construction du `cn` |
| `MAIL_PATTERN` | `%u@%d` | Adresse mail, vide pour ne pas en créer |
| `MAIL_DOMAIN` | *(déduit de `BASE_DN`)* | Domaine utilisé par `%d` |
| `USER_EXTRA_OBJECTCLASSES` | *(vide)* | Classes ajoutées, séparées par des espaces |
| `USER_EXTRA_ATTRS` | *(vide)* | `attr=valeur` séparés par `;`, motifs `%x` interprétés |

Motifs disponibles : `%u` login, `%f` prénom, `%l` nom, `%i` initiale du login,
`%d` domaine, `%U` uid, `%G` gid, `%r` realm, `%g` groupe, `%t` horodatage.

## Groupes

| Paramètre | Défaut | Description |
|---|---|---|
| `GROUP_MODE` | `per-user` | `per-user` (un groupe par compte), `shared`, `none` |
| `DEFAULT_GROUP` | *(vide)* | Groupe partagé (`GROUP_MODE=shared`) |
| `DEFAULT_GID` | *(vide)* | GID imposé (`GROUP_MODE=none`, ou groupe partagé à créer) |
| `GROUP_AUTOCREATE` | `1` | Crée le groupe partagé s'il manque |
| `GROUP_ADD_MEMBER` | `1` | Ajoute/retire le login dans `GROUP_MEMBER_ATTR` |

## Mots de passe

| Paramètre | Défaut | Description |
|---|---|---|
| `USER_PASSWORD_MODE` | `sasl` | `sasl` (délégué à Kerberos), `hash` (dans l'annuaire), `none` |
| `USER_PASSWORD_HASH` | `{SSHA}` | Schéma passé à `slappasswd -h` |
| `SLAPPASSWD_CMD` | `slappasswd` | Commande de hachage |
| `USER_PASSWORD_INITIAL` | `prompt` | `prompt` ou `random` (généré puis affiché) |
| `USER_PASSWORD_RANDOM_LENGTH` | `16` | Longueur des mots de passe générés |

## Kerberos

| Paramètre | Défaut | Description |
|---|---|---|
| `KRB5_ENABLED` | `auto` | `auto` (actif si `kadmin.local` est présent), `1`, `0` |
| `KRB5_REALM` | *(BASE_DN en majuscules)* | Realm |
| `KRB5_ADMIN_CMD` | `kadmin.local` | Commande d'administration, ex. `kadmin -p admin/admin` |
| `KRB5_ADMIN_OPTS` | *(vide)* | Options ajoutées à cette commande |
| `KRB5_ADDPRINC_OPTS` | *(vide)* | Options de `addprinc`, ex. `-policy users` |
| `KRB5_PASSWORD_MODE` | `prompt` | `prompt` ou `random` (`-randkey`) |
| `KRB5_MAX_RETRIES` | `3` | Tentatives avant abandon |
| `KRB5_REQUIRED` | `0` | `1` : un échec annule la création du compte |

## Répertoires personnels

| Paramètre | Défaut | Description |
|---|---|---|
| `HOME_ENABLED` | `1` | `0` : les scripts ne touchent à aucun répertoire |
| `HOME_ROOT` | `/home` | Emplacement réel sur la machine qui exécute le script |
| `HOME_LOGICAL_ROOT` | *(= `HOME_ROOT`)* | Chemin écrit dans `homeDirectory`, vu par les clients |
| `HOME_PATTERN` | `%u` | Sous-chemin, ex. `%i/%u` pour `/home/j/jdupont` |
| `HOME_MODE` | `0700` | Permissions |
| `HOME_SKEL` | `/etc/skel` | Squelette copié, vide pour ne rien copier |
| `HOME_CHOWN` | `1` | Applique le propriétaire après création |

`HOME_ROOT` et `HOME_LOGICAL_ROOT` diffèrent typiquement sur un serveur NFS :
les répertoires sont créés dans `/srv/nfs/home` mais montés en `/home` côté
clients.

## Suppression

| Paramètre | Défaut | Description |
|---|---|---|
| `DELETE_HOME_ACTION` | `archive` | `archive`, `purge`, `keep` |
| `ARCHIVE_DIR` | `/var/backups/ldap-scripts` | Destination des archives |
| `ARCHIVE_FORMAT` | `move` | `move` (déplacement) ou `tar` (tar.gz) |
| `ARCHIVE_NAME_PATTERN` | `%u-%t` | Nom de l'archive |
| `DELETE_CONFIRM` | `1` | Demande confirmation avant suppression |

## Intégrations

| Paramètre | Défaut | Description |
|---|---|---|
| `NSS_CHECK` | `1` | Vérifie `getent passwd` après création |
| `CACHE_FLUSH_CMD` | *(vide)* | Commande d'invalidation de cache, ex. `sss_cache -E` |
| `HOOK_PRE_ADD` | *(vide)* | Avant la création |
| `HOOK_POST_ADD` | *(vide)* | Après la création |
| `HOOK_PRE_DELETE` | *(vide)* | Avant la suppression |
| `HOOK_POST_DELETE` | *(vide)* | Après la suppression |
| `HOOK_POST_PASSWD` | *(vide)* | Après un changement de mot de passe |

Les hooks sont des commandes shell. Elles reçoivent dans leur environnement :
`LS_ACTION`, `LS_USERNAME`, `LS_FIRSTNAME`, `LS_LASTNAME`, `LS_UID`, `LS_GID`,
`LS_HOME`, `LS_USER_DN`, `LS_GROUP`.

```bash
HOOK_POST_ADD='logger -t ldap-scripts "compte $LS_USERNAME (uid $LS_UID) créé"'
HOOK_POST_DELETE='/usr/local/sbin/revoke-vpn "$LS_USERNAME"'
```

## Exemples complets

### OpenLDAP seul, mots de passe dans l'annuaire

```bash
BASE_DN="dc=example,dc=com"
LDAP_URI="ldaps://ldap.example.com"
LDAP_TLS="ldaps"
BIND_DN="cn=admin,dc=example,dc=com"
USER_PASSWORD_MODE="hash"
USER_PASSWORD_HASH="{SSHA}"
KRB5_ENABLED=0
HOME_ENABLED=0          # les homes sont créés par pam_mkhomedir
```

### LDAP + Kerberos + homes NFS

```bash
BASE_DN="dc=example,dc=com"
LDAP_URI="ldap://annuaire.example.com"
LDAP_TLS="starttls"
USER_PASSWORD_MODE="sasl"
KRB5_ENABLED=1
KRB5_REALM="EXAMPLE.COM"
KRB5_REQUIRED=1
HOME_ROOT="/srv/nfs4/home"
HOME_LOGICAL_ROOT="/home"
ARCHIVE_DIR="/srv/nfs4/archive"
```

### Administration locale sans mot de passe (socket ldapi)

```bash
BASE_DN="dc=example,dc=com"
LDAP_URI="ldapi:///"
LDAP_AUTH="sasl"
LDAP_SASL_MECH="EXTERNAL"
```

### Groupe partagé et comptes temporaires

```bash
GROUP_MODE="shared"
DEFAULT_GROUP="etudiants"
DEFAULT_GID=20000
UID_MIN=20000
UID_MAX=29999
UID_ALLOCATION="first"        # réutilise les UID libérés
DELETE_HOME_ACTION="purge"
```
