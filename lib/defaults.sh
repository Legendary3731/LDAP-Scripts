#!/bin/bash
# defaults.sh - Valeurs par défaut de TOUS les paramètres de ldap-scripts.
#
# Ne pas éditer ce fichier : il est écrasé à chaque mise à jour.
# Pour changer un paramètre, utilise (par ordre de priorité croissante) :
#   1. ce fichier                       (défauts livrés)
#   2. <SYSCONFDIR>/ldap-scripts.conf   (configuration du site)
#   3. <SYSCONFDIR>/conf.d/*.conf       (fragments, ordre alphabétique)
#   4. ~/.config/ldap-scripts/ldap-scripts.conf
#   5. le fichier désigné par $LDAP_SCRIPTS_CONF ou par --config FICHIER
#   6. une variable d'environnement du même nom  (ex: BASE_DN=... ldapadduser ...)
#   7. une option de ligne de commande           (ex: -o BASE_DN=...)
#
# Chaque nom de variable défini ici est automatiquement surchargeable par
# l'environnement et par -o NOM=VALEUR : il n'y a rien d'autre à déclarer.

# ---------------------------------------------------------------------------
# Comportement général
# ---------------------------------------------------------------------------
# Répertoire des templates LDIF (vide = <répertoire de la config>/templates)
TEMPLATE_DIR=""
# 1 = n'exécute aucune modification, affiche seulement ce qui serait fait
DRY_RUN=0
# 1 = ne pose aucune question interactive de confirmation
ASSUME_YES=0
# 1 = trace les commandes externes exécutées
VERBOSE=0
# 1 = n'affiche que les erreurs
QUIET=0
# auto | always | never
COLOR="auto"
# auto | 1 | 0   (auto = root exigé seulement si le script touche aux homes
#                 ou pilote un KDC local)
REQUIRE_ROOT="auto"

# ---------------------------------------------------------------------------
# Connexion LDAP
# ---------------------------------------------------------------------------
LDAP_URI="ldap://localhost"
# Base de l'annuaire, ex: dc=example,dc=com  (obligatoire)
BASE_DN=""
# DN complets des branches. Laissés vides, ils valent <RDN>,<BASE_DN>
USERS_DN=""
GROUPS_DN=""
USERS_RDN="ou=people"
GROUPS_RDN="ou=groups"

# Méthode d'authentification au serveur :
#   prompt   : demande le mot de passe au clavier (défaut)
#   password : utilise LDAP_BIND_PASSWORD (déconseillé, mot de passe en clair)
#   file     : utilise le contenu de LDAP_BIND_PASSWORD_FILE
#   env      : utilise la variable nommée par LDAP_BIND_PASSWORD_ENV
#   sasl     : bind SASL (ex: EXTERNAL sur ldapi://, ou GSSAPI)
#   none     : bind anonyme
LDAP_AUTH="prompt"
BIND_DN=""
LDAP_BIND_PASSWORD=""
LDAP_BIND_PASSWORD_FILE=""
LDAP_BIND_PASSWORD_ENV="LDAP_BIND_PW"
LDAP_SASL_MECH="EXTERNAL"
LDAP_SASL_OPTS=""

# Chiffrement : none | starttls | ldaps
#   ldaps ne modifie pas LDAP_URI : utilise ldaps://... dans LDAP_URI
LDAP_TLS="none"
LDAP_TLS_CACERT=""
# never | allow | try | demand  (vide = laisse ldap.conf décider)
LDAP_TLS_REQCERT=""
# Options brutes ajoutées à toutes les commandes ldap* (ex: "-o nettimeout=5")
LDAP_EXTRA_OPTS=""

# Schéma : attributs et filtres utilisés pour retrouver les objets
UID_ATTR="uid"
USER_FILTER="(objectClass=posixAccount)"
GROUP_ATTR="cn"
GROUP_FILTER="(objectClass=posixGroup)"
GROUP_MEMBER_ATTR="memberUid"
# Attributs affichés par ldapfinger
FINGER_ATTRS="uidNumber gidNumber cn sn givenName mail homeDirectory loginShell"

# ---------------------------------------------------------------------------
# Comptes POSIX
# ---------------------------------------------------------------------------
UID_MIN=10000
UID_MAX=60000
# max   : plus grand uidNumber existant + 1
# first : premier uidNumber libre à partir de UID_MIN
UID_ALLOCATION="max"
DEFAULT_SHELL="/bin/bash"
# Validation du nom de compte (regex ERE). Vide = aucune validation.
USERNAME_PATTERN="^[a-z_][a-z0-9_-]{0,31}$"
# Construction du cn : %f prénom, %l nom, %u login
CN_PATTERN="%f %l"
# Adresse mail : %u login, %d domaine, %f prénom, %l nom. Vide = pas de mail.
MAIL_PATTERN="%u@%d"
# Domaine mail. Vide = déduit de BASE_DN (dc=example,dc=com -> example.com)
MAIL_DOMAIN=""
# Classes d'objets supplémentaires ajoutées à l'entrée utilisateur,
# séparées par des espaces. Ex: "ldapPublicKey sambaSamAccount"
USER_EXTRA_OBJECTCLASSES=""
# Attributs supplémentaires, "attr=valeur" séparés par des ';'.
# Ex: "departmentNumber=IT;o=ACME"  (%u %f %l %d sont interprétés)
USER_EXTRA_ATTRS=""

# ---------------------------------------------------------------------------
# Groupes
# ---------------------------------------------------------------------------
# per-user : un posixGroup par utilisateur (gidNumber = uidNumber)
# shared   : tous les comptes dans DEFAULT_GROUP
# none     : aucune gestion de groupe (DEFAULT_GID doit être renseigné)
GROUP_MODE="per-user"
DEFAULT_GROUP=""
DEFAULT_GID=""
# 1 = crée le groupe partagé s'il n'existe pas
GROUP_AUTOCREATE=1
# 1 = ajoute/retire l'utilisateur dans GROUP_MEMBER_ATTR du groupe partagé
GROUP_ADD_MEMBER=1

# ---------------------------------------------------------------------------
# Mot de passe stocké dans l'annuaire (attribut userPassword)
# ---------------------------------------------------------------------------
# sasl : userPassword: {SASL}user@REALM  (authentification déléguée à Kerberos)
# hash : hachage calculé par slappasswd
# none : pas d'attribut userPassword
USER_PASSWORD_MODE="sasl"
# Schéma de hachage passé à slappasswd -h (mode hash)
USER_PASSWORD_HASH="{SSHA}"
SLAPPASSWD_CMD="slappasswd"
# prompt : demande le mot de passe initial ; random : en génère un et l'affiche
USER_PASSWORD_INITIAL="prompt"
USER_PASSWORD_RANDOM_LENGTH=16

# ---------------------------------------------------------------------------
# Kerberos (optionnel)
# ---------------------------------------------------------------------------
# auto | 1 | 0   (auto = activé si KRB5_ADMIN_CMD est disponible)
KRB5_ENABLED="auto"
# Vide = déduit de BASE_DN en majuscules (dc=example,dc=com -> EXAMPLE.COM)
KRB5_REALM=""
KRB5_ADMIN_CMD="kadmin.local"
KRB5_ADMIN_OPTS=""
# Options passées à addprinc, ex: "-policy users -maxlife 1d"
KRB5_ADDPRINC_OPTS=""
# prompt : mot de passe saisi au clavier ; random : clé aléatoire (-randkey)
KRB5_PASSWORD_MODE="prompt"
KRB5_MAX_RETRIES=3
# 1 = un échec Kerberos annule la création (rollback de l'entrée LDAP)
KRB5_REQUIRED=0

# ---------------------------------------------------------------------------
# Répertoires personnels
# ---------------------------------------------------------------------------
HOME_ENABLED=1
# Emplacement réel des répertoires sur cette machine (export NFS, /home, ...)
HOME_ROOT="/home"
# Chemin tel qu'il doit apparaître dans homeDirectory côté client.
# Vide = identique à HOME_ROOT.
HOME_LOGICAL_ROOT=""
# Motif du sous-répertoire : %u login, %f prénom, %l nom, %U uid, %i initiale
HOME_PATTERN="%u"
HOME_MODE="0700"
# Répertoire squelette copié dans le home (vide = aucune copie)
HOME_SKEL="/etc/skel"
HOME_CHOWN=1

# ---------------------------------------------------------------------------
# Suppression de compte
# ---------------------------------------------------------------------------
# archive | purge | keep
DELETE_HOME_ACTION="archive"
ARCHIVE_DIR="/var/backups/ldap-scripts"
# move : déplace le répertoire ; tar : crée une archive tar.gz
ARCHIVE_FORMAT="move"
# %u login, %t horodatage
ARCHIVE_NAME_PATTERN="%u-%t"
# 1 = demande confirmation avant de supprimer
DELETE_CONFIRM=1

# ---------------------------------------------------------------------------
# Vérifications et intégrations
# ---------------------------------------------------------------------------
# 1 = vérifie la résolution NSS (getent) après création
NSS_CHECK=1
# Commande lancée pour invalider un cache (sssd, nscd...). Vide = aucune.
CACHE_FLUSH_CMD=""

# ---------------------------------------------------------------------------
# Hooks : commandes shell exécutées aux différentes étapes.
# Variables exportées : LS_ACTION LS_USERNAME LS_FIRSTNAME LS_LASTNAME
#                       LS_UID LS_GID LS_HOME LS_USER_DN LS_GROUP
# ---------------------------------------------------------------------------
HOOK_PRE_ADD=""
HOOK_POST_ADD=""
HOOK_PRE_DELETE=""
HOOK_POST_DELETE=""
HOOK_POST_PASSWD=""

# ---------------------------------------------------------------------------
# Templates LDIF (vide = <TEMPLATE_DIR>/user.ldif et group.ldif)
# ---------------------------------------------------------------------------
TEMPLATE_USER=""
TEMPLATE_GROUP=""
