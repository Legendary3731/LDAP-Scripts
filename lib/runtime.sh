#!/bin/bash
# runtime.sh - Bibliothèque partagée de ldap-scripts.
# Ce fichier est sourcé par les scripts de sbin/, il ne s'exécute pas seul.
#
# Il fournit : le chargement en couches de la configuration, l'analyse des
# options communes, les helpers LDAP / Kerberos / home, le rendu des
# templates LDIF et les hooks.

LDAP_SCRIPTS_VERSION="2.0"

# Emplacements substitués à l'installation par le Makefile.
LDAP_SCRIPTS_SYSCONFDIR_BUILTIN="@SYSCONFDIR@"

# ---------------------------------------------------------------------------
# Sorties
# ---------------------------------------------------------------------------
C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""

setup_colors() {
    local mode="${COLOR:-auto}"
    if [ "$mode" = "never" ] || { [ "$mode" = "auto" ] && [ ! -t 1 ]; }; then
        C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
        return
    fi
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
}

log()  { [ "${QUIET:-0}" = "1" ] || echo "${C_BLUE}==>${C_RESET} $*"; }
info() { [ "${QUIET:-0}" = "1" ] || echo "    $*"; }
ok()   { [ "${QUIET:-0}" = "1" ] || echo "${C_GREEN}  ok${C_RESET} $*"; }
warn() { echo "${C_YELLOW}Attention:${C_RESET} $*" >&2; }

# Titre de section encadré, pour les sorties de ldapfinger / ldapconfig.
section() {
    [ "${QUIET:-0}" = "1" ] && return 0
    local title="$1" width="${SECTION_WIDTH:-72}" stripped len line
    stripped="${title//[$'\x80'-$'\xbf']/}"
    len=${#stripped}
    line=$(printf '%*s' "$((width - len - 3))" '' | tr ' ' '-')
    printf '\n%s%s %s%s\n' "$C_BLUE" "$title" "$line" "$C_RESET"
}

# Complète une chaîne à N caractères. printf "%-Ns" compte les octets, ce qui
# décale les colonnes dès qu'un libellé est accentué : on aligne donc à la main.
pad() {
    local text="$1" width="$2" stripped len
    # On retire les octets de continuation UTF-8 (0x80-0xBF) pour obtenir un
    # nombre de caractères correct, quelle que soit la locale du serveur.
    stripped="${text//[$'\x80'-$'\xbf']/}"
    len=${#stripped}
    if [ "$len" -ge "$width" ]; then
        printf '%s' "$text"
    else
        printf '%s%*s' "$text" $((width - len)) ''
    fi
}

# Couple clé/valeur aligné : kv "Nom du champ" "valeur"
kv() {
    [ "${QUIET:-0}" = "1" ] && return 0
    printf '  %s %s\n' "$(pad "$1" 22)" "$2"
}

# État coloré : status ok|warn|ko "texte"
status() {
    [ "${QUIET:-0}" = "1" ] && return 0
    case "$1" in
        ok)   printf '  %s%s%s %s\n' "$C_GREEN"  "$(pad "OK" 22)"         "$C_RESET" "$2" ;;
        warn) printf '  %s%s%s %s\n' "$C_YELLOW" "$(pad "À VÉRIFIER" 22)" "$C_RESET" "$2" ;;
        *)    printf '  %s%s%s %s\n' "$C_RED"    "$(pad "ÉCHEC" 22)"      "$C_RESET" "$2" ;;
    esac
}
# Les traces passent par un descripteur dédié, dupliqué depuis stderr au
# chargement : elles restent visibles même quand l'appelant redirige le stderr
# de la commande vers /dev/null (bash >= 4.1).
exec {LDAP_SCRIPTS_TRACE_FD}>&2
debug() {
    [ "${VERBOSE:-0}" = "1" ] || return 0
    echo "${C_BLUE}+${C_RESET} $*" >&"$LDAP_SCRIPTS_TRACE_FD"
}

die() {
    echo "${C_RED}Erreur:${C_RESET} $*" >&2
    exit 1
}

# Exécute une commande, ou l'affiche seulement si DRY_RUN=1.
run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "${C_YELLOW}[dry-run]${C_RESET} $*"
        return 0
    fi
    debug "$*"
    "$@"
}

confirm() {
    local prompt="$1"
    [ "${ASSUME_YES:-0}" = "1" ] && return 0
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    local answer
    read -rp "${prompt} [o/N] " answer
    case "$answer" in
        o|O|y|Y|oui|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Nettoyage
# ---------------------------------------------------------------------------
LDAP_SCRIPTS_TMPFILES=()

cleanup() {
    local rc=$?
    local f
    for f in "${LDAP_SCRIPTS_TMPFILES[@]:-}"; do
        [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
    done
    # Le trap ne doit pas modifier le code de sortie du script.
    return $rc
}
trap cleanup EXIT
# Une interruption doit terminer le script : le trap EXIT fera le ménage.
trap 'echo; exit 130' INT
trap 'exit 143' TERM

mktemp_tracked() {
    local f
    f=$(mktemp "${TMPDIR:-/tmp}/.ldap-scripts.XXXXXX")
    chmod 600 "$f"
    LDAP_SCRIPTS_TMPFILES+=("$f")
    echo "$f"
}

# ---------------------------------------------------------------------------
# Analyse des options communes à tous les scripts
# ---------------------------------------------------------------------------
ARGS=()
CLI_CONFIG=""
CLI_OVERRIDES=()

common_options_help() {
    cat <<'HELP'
Options communes :
  -c, --config FICHIER   Fichier de configuration à utiliser
  -o NOM=VALEUR          Surcharge un paramètre (répétable)
  -H, --uri URI          URI du serveur LDAP
  -b, --base-dn DN       Base de l'annuaire
  -D, --bind-dn DN       DN de connexion
  -w, --bind-password M  Mot de passe de connexion (visible dans ps)
      --bind-password-file F   Fichier contenant ce mot de passe
  -Y, --sasl MÉCANISME   Bind SASL (EXTERNAL, GSSAPI, ...)
      --no-kerberos      Désactive les opérations Kerberos
      --no-home          Désactive la gestion des répertoires personnels
  -n, --dry-run          Affiche les actions sans rien modifier
      --yes              Répond oui à toutes les confirmations
  -q, --quiet            N'affiche que les erreurs
  -v, --verbose          Trace les commandes exécutées
  -V, --version          Affiche la version
  -h, --help             Affiche cette aide
HELP
}

# usage() doit être définie par le script appelant.
parse_common_args() {
    ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -c|--config)        CLI_CONFIG="$2"; shift 2 ;;
            --config=*)         CLI_CONFIG="${1#*=}"; shift ;;
            -o)                 CLI_OVERRIDES+=("$2"); shift 2 ;;
            -o*)                CLI_OVERRIDES+=("${1#-o}"); shift ;;
            -H|--uri)           CLI_OVERRIDES+=("LDAP_URI=$2"); shift 2 ;;
            --uri=*)            CLI_OVERRIDES+=("LDAP_URI=${1#*=}"); shift ;;
            -b|--base-dn)       CLI_OVERRIDES+=("BASE_DN=$2"); shift 2 ;;
            --base-dn=*)        CLI_OVERRIDES+=("BASE_DN=${1#*=}"); shift ;;
            -D|--bind-dn)       CLI_OVERRIDES+=("BIND_DN=$2"); shift 2 ;;
            --bind-dn=*)        CLI_OVERRIDES+=("BIND_DN=${1#*=}"); shift ;;
            -w|--bind-password) CLI_OVERRIDES+=("LDAP_AUTH=password" "LDAP_BIND_PASSWORD=$2"); shift 2 ;;
            --bind-password=*)  CLI_OVERRIDES+=("LDAP_AUTH=password" "LDAP_BIND_PASSWORD=${1#*=}"); shift ;;
            --bind-password-file)   CLI_OVERRIDES+=("LDAP_AUTH=file" "LDAP_BIND_PASSWORD_FILE=$2"); shift 2 ;;
            --bind-password-file=*) CLI_OVERRIDES+=("LDAP_AUTH=file" "LDAP_BIND_PASSWORD_FILE=${1#*=}"); shift ;;
            -Y|--sasl)          CLI_OVERRIDES+=("LDAP_AUTH=sasl" "LDAP_SASL_MECH=$2"); shift 2 ;;
            --sasl=*)           CLI_OVERRIDES+=("LDAP_AUTH=sasl" "LDAP_SASL_MECH=${1#*=}"); shift ;;
            --no-kerberos)      CLI_OVERRIDES+=("KRB5_ENABLED=0"); shift ;;
            --kerberos)         CLI_OVERRIDES+=("KRB5_ENABLED=1"); shift ;;
            --no-home)          CLI_OVERRIDES+=("HOME_ENABLED=0"); shift ;;
            -n|--dry-run)       CLI_OVERRIDES+=("DRY_RUN=1"); shift ;;
            --yes|--assume-yes) CLI_OVERRIDES+=("ASSUME_YES=1"); shift ;;
            -q|--quiet)         CLI_OVERRIDES+=("QUIET=1"); shift ;;
            -v|--verbose)       CLI_OVERRIDES+=("VERBOSE=1"); shift ;;
            -V|--version)       echo "ldap-scripts ${LDAP_SCRIPTS_VERSION}"; exit 0 ;;
            -h|--help)          usage; exit 0 ;;
            --)                 shift; ARGS+=("$@"); break ;;
            -*)
                # Le script appelant peut gérer ses propres options en
                # définissant handle_extra_arg() et en fixant EXTRA_SHIFT.
                EXTRA_SHIFT=0
                if declare -F handle_extra_arg >/dev/null; then
                    handle_extra_arg "$@"
                fi
                if [ "${EXTRA_SHIFT:-0}" -gt 0 ]; then
                    shift "$EXTRA_SHIFT"
                else
                    die "option inconnue : $1 (voir --help)"
                fi
                ;;
            *)                  ARGS+=("$1"); shift ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Chargement de la configuration
# ---------------------------------------------------------------------------
CONFIG_FILES_LOADED=()

# Liste des paramètres connus, extraite de defaults.sh.
config_known_vars() {
    grep -oE '^[A-Z_][A-Z0-9_]*=' "${LDAP_SCRIPTS_LIB}/defaults.sh" | tr -d '='
}

config_load() {
    local sysconfdir="$1"
    local var value

    # 1. Mémorise ce qui vient déjà de l'environnement : ces valeurs seront
    #    réappliquées après les fichiers, pour rester prioritaires.
    declare -gA CONFIG_ENV_OVERRIDES=()
    while read -r var; do
        [ -n "$var" ] || continue
        if [ -n "${!var+x}" ]; then
            CONFIG_ENV_OVERRIDES["$var"]="${!var}"
        fi
    done < <(config_known_vars)

    # 2. Défauts livrés.
    # shellcheck source=/dev/null
    source "${LDAP_SCRIPTS_LIB}/defaults.sh"

    # 3. Fichiers de configuration, du plus général au plus spécifique.
    local candidates=()
    [ -n "$sysconfdir" ] && candidates+=("${sysconfdir}/ldap-scripts.conf")
    if [ -n "$sysconfdir" ] && [ -d "${sysconfdir}/conf.d" ]; then
        local frag
        for frag in "${sysconfdir}"/conf.d/*.conf; do
            [ -f "$frag" ] && candidates+=("$frag")
        done
    fi
    candidates+=("${XDG_CONFIG_HOME:-$HOME/.config}/ldap-scripts/ldap-scripts.conf")
    [ -n "${LDAP_SCRIPTS_CONF:-}" ] && candidates+=("$LDAP_SCRIPTS_CONF")
    [ -n "$CLI_CONFIG" ] && candidates+=("$CLI_CONFIG")

    local f
    for f in "${candidates[@]}"; do
        if [ -f "$f" ]; then
            # shellcheck source=/dev/null
            source "$f"
            CONFIG_FILES_LOADED+=("$f")
        fi
    done

    # Un fichier demandé explicitement doit exister.
    if [ -n "$CLI_CONFIG" ] && [ ! -f "$CLI_CONFIG" ]; then
        die "fichier de configuration introuvable : $CLI_CONFIG"
    fi
    if [ -n "${LDAP_SCRIPTS_CONF:-}" ] && [ ! -f "$LDAP_SCRIPTS_CONF" ]; then
        die "fichier de configuration introuvable : $LDAP_SCRIPTS_CONF"
    fi

    # 4. Variables d'environnement.
    for var in "${!CONFIG_ENV_OVERRIDES[@]}"; do
        printf -v "$var" '%s' "${CONFIG_ENV_OVERRIDES[$var]}"
    done

    # 5. Surcharges -o NOM=VALEUR.
    local ov
    for ov in "${CLI_OVERRIDES[@]:-}"; do
        [ -n "$ov" ] || continue
        [[ "$ov" == *=* ]] || die "surcharge invalide : '$ov' (attendu NOM=VALEUR)"
        var="${ov%%=*}"
        value="${ov#*=}"
        [[ "$var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "nom de paramètre invalide : '$var'"
        printf -v "$var" '%s' "$value"
    done

    config_track_origins
}

# Retient d'où vient chaque paramètre, pour 'ldapconfig show'.
config_track_origins() {
    declare -gA CONFIG_ORIGIN=()
    local f var ov
    for f in "${CONFIG_FILES_LOADED[@]:-}"; do
        [ -n "$f" ] || continue
        while read -r var; do
            [ -n "$var" ] && CONFIG_ORIGIN["$var"]="$(basename "$f")"
        done < <(grep -oE '^[[:space:]]*[A-Z_][A-Z0-9_]*=' "$f" | tr -d ' =')
    done
    for var in "${!CONFIG_ENV_OVERRIDES[@]}"; do
        CONFIG_ORIGIN["$var"]="environnement"
    done
    for ov in "${CLI_OVERRIDES[@]:-}"; do
        [ -n "$ov" ] || continue
        CONFIG_ORIGIN["${ov%%=*}"]="option -o"
    done
    return 0
}

# Anciens noms de variables (versions < 2.0) encore acceptés.
config_apply_legacy_aliases() {
    [ -n "${PEOPLE_OU:-}" ] && USERS_DN="$PEOPLE_OU"
    [ -n "${GROUPS_OU:-}" ] && GROUPS_DN="$GROUPS_OU"
    [ -n "${REALM:-}" ] && KRB5_REALM="$REALM"
    [ -n "${KADMIN_MAX_RETRIES:-}" ] && KRB5_MAX_RETRIES="$KADMIN_MAX_RETRIES"
    [ -n "${UID_GID_START:-}" ] && UID_MIN="$UID_GID_START"
    [ -n "${HOME_ROOT_PHYSICAL:-}" ] && HOME_ROOT="$HOME_ROOT_PHYSICAL"
    [ -n "${HOME_ROOT_LOGICAL:-}" ] && HOME_LOGICAL_ROOT="$HOME_ROOT_LOGICAL"
    [ -n "${ARCHIVE_ROOT:-}" ] && ARCHIVE_DIR="$ARCHIVE_ROOT"
    if [ -n "${USE_STARTTLS:-}" ]; then
        [ "$USE_STARTTLS" = "1" ] && LDAP_TLS="starttls" || LDAP_TLS="none"
    fi
    return 0
}

# Calcule les valeurs dérivées et vérifie la cohérence de l'ensemble.
config_finalize() {
    config_apply_legacy_aliases
    setup_colors

    [ -n "$BASE_DN" ] || die "BASE_DN n'est pas défini. Crée une configuration avec 'ldapconfig init' ou passe --base-dn."

    [ -n "$USERS_DN" ]  || USERS_DN="${USERS_RDN},${BASE_DN}"
    [ -n "$GROUPS_DN" ] || GROUPS_DN="${GROUPS_RDN},${BASE_DN}"

    # Domaine DNS déduit de la base : dc=example,dc=com -> example.com
    if [ -z "$MAIL_DOMAIN" ]; then
        MAIL_DOMAIN=$(echo "$BASE_DN" | tr -d ' ' | tr 'A-Z' 'a-z' \
            | sed -e 's/dc=//g' -e 's/,/./g')
    fi

    [ -n "$KRB5_REALM" ] || KRB5_REALM=$(echo "$MAIL_DOMAIN" | tr 'a-z' 'A-Z')
    [ -n "$HOME_LOGICAL_ROOT" ] || HOME_LOGICAL_ROOT="$HOME_ROOT"

    if [ -z "$BIND_DN" ] && [ "$LDAP_AUTH" != "sasl" ] && [ "$LDAP_AUTH" != "none" ]; then
        BIND_DN="cn=admin,${BASE_DN}"
    fi

    # Kerberos : résolution du mode auto.
    if [ "$KRB5_ENABLED" = "auto" ]; then
        if command -v "${KRB5_ADMIN_CMD%% *}" >/dev/null 2>&1; then
            KRB5_ENABLED=1
        else
            KRB5_ENABLED=0
        fi
    fi

    # Templates.
    if [ -z "$TEMPLATE_DIR" ]; then
        if [ ${#CONFIG_FILES_LOADED[@]} -gt 0 ]; then
            TEMPLATE_DIR="$(dirname "${CONFIG_FILES_LOADED[0]}")/templates"
        else
            TEMPLATE_DIR="${LDAP_SCRIPTS_LIB}/../etc/templates"
        fi
    fi
    [ -n "$TEMPLATE_USER" ]  || TEMPLATE_USER="${TEMPLATE_DIR}/user.ldif"
    [ -n "$TEMPLATE_GROUP" ] || TEMPLATE_GROUP="${TEMPLATE_DIR}/group.ldif"

    case "$GROUP_MODE" in
        per-user) ;;
        shared)
            [ -n "$DEFAULT_GROUP" ] || die "GROUP_MODE=shared nécessite DEFAULT_GROUP"
            ;;
        none)
            [ -n "$DEFAULT_GID" ] || die "GROUP_MODE=none nécessite DEFAULT_GID"
            ;;
        *) die "GROUP_MODE invalide : '$GROUP_MODE' (per-user|shared|none)" ;;
    esac

    case "$LDAP_TLS" in none|starttls|ldaps) ;; *) die "LDAP_TLS invalide : '$LDAP_TLS'" ;; esac
    case "$LDAP_AUTH" in prompt|password|file|env|sasl|none) ;; *) die "LDAP_AUTH invalide : '$LDAP_AUTH'" ;; esac
    case "$USER_PASSWORD_MODE" in sasl|hash|none) ;; *) die "USER_PASSWORD_MODE invalide : '$USER_PASSWORD_MODE'" ;; esac
    case "$DELETE_HOME_ACTION" in archive|purge|keep) ;; *) die "DELETE_HOME_ACTION invalide : '$DELETE_HOME_ACTION'" ;; esac

    ldap_build_common_opts
}

# Point d'entrée appelé par chaque script : analyse les options puis charge
# la configuration. Les arguments restants sont dans ${ARGS[@]}.
ldap_scripts_init() {
    parse_common_args "$@"
    local sysconfdir="$LDAP_SCRIPTS_SYSCONFDIR_BUILTIN"
    case "$sysconfdir" in
        @*@|"") sysconfdir="$(cd "${LDAP_SCRIPTS_LIB}/../etc" 2>/dev/null && pwd)" ;;
    esac
    [ -n "${LDAP_SCRIPTS_SYSCONFDIR:-}" ] && sysconfdir="$LDAP_SCRIPTS_SYSCONFDIR"
    LDAP_SCRIPTS_SYSCONFDIR="$sysconfdir"
    config_load "$sysconfdir"
    config_finalize
}

require_root() {
    local need="${REQUIRE_ROOT:-auto}"
    if [ "$need" = "auto" ]; then
        if [ "${HOME_ENABLED:-0}" = "1" ] || [ "${KRB5_ENABLED:-0}" = "1" ]; then
            need=1
        else
            need=0
        fi
    fi
    [ "$need" = "1" ] || return 0
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    [ "$(id -u)" -eq 0 ] || die "ce script doit être lancé en root (ou REQUIRE_ROOT=0 si ton administration est distante)"
}

# ---------------------------------------------------------------------------
# Motifs %x
#   %u login   %f prénom   %l nom   %d domaine   %U uid   %G gid
#   %i initiale du login   %r realm   %g groupe   %t horodatage   %% littéral
# ---------------------------------------------------------------------------
expand_pattern() {
    local p="$1"
    p="${p//%u/${USERNAME:-}}"
    p="${p//%f/${FIRSTNAME:-}}"
    p="${p//%l/${LASTNAME:-}}"
    p="${p//%d/${MAIL_DOMAIN:-}}"
    p="${p//%U/${UID_NUMBER:-}}"
    p="${p//%G/${GID_NUMBER:-}}"
    p="${p//%i/${USERNAME:0:1}}"
    p="${p//%r/${KRB5_REALM:-}}"
    p="${p//%g/${GROUP_NAME:-}}"
    p="${p//%t/$(date +%Y%m%d-%H%M%S)}"
    p="${p//%%/%}"
    printf '%s' "$p"
}

# ---------------------------------------------------------------------------
# Rendu d'un template LDIF.
# Les motifs {{NOM}} (et <NOM>, syntaxe historique) sont remplacés par la
# valeur de la variable shell NOM : n'importe quel paramètre de configuration
# est donc utilisable dans un template, y compris ceux que tu ajoutes.
# Une ligne dont l'attribut est vide après substitution est supprimée.
# ---------------------------------------------------------------------------
render_template() {
    local tpl="$1"
    [ -f "$tpl" ] || die "template introuvable : $tpl"
    local line var val guard had_placeholder
    while IFS= read -r line || [ -n "$line" ]; do
        # Les lignes commençant par '#' documentent le template ; elles ne
        # font pas partie du LDIF produit.
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        guard=0
        had_placeholder=0
        [[ "$line" == *"{{"* || "$line" == *"<"* ]] && had_placeholder=1
        while [ $guard -lt 50 ]; do
            if [[ "$line" =~ \{\{([A-Za-z_][A-Za-z0-9_]*)\}\} ]]; then
                var="${BASH_REMATCH[1]}"
                val="${!var-}"
                line="${line//\{\{$var\}\}/$val}"
            elif [[ "$line" =~ \<([A-Za-z_][A-Za-z0-9_]*)\> ]]; then
                var="${BASH_REMATCH[1]}"
                val="${!var-}"
                line="${line//<$var>/$val}"
            else
                break
            fi
            guard=$((guard + 1))
        done
        # Attribut sans valeur, ou bloc optionnel vide : on ne l'écrit pas.
        [[ "$line" =~ ^[A-Za-z][A-Za-z0-9-]*:[[:space:]]*$ ]] && continue
        [ "$had_placeholder" = "1" ] && [ -z "$line" ] && continue
        printf '%s\n' "$line"
    done < "$tpl"
    return 0
}

# Ajoute au LDIF les objectClass et attributs supplémentaires configurés.
render_extra_attrs() {
    local oc attr
    for oc in $USER_EXTRA_OBJECTCLASSES; do
        printf 'objectClass: %s\n' "$oc"
    done
    local IFS=';'
    for attr in $USER_EXTRA_ATTRS; do
        [ -n "$attr" ] || continue
        printf '%s: %s\n' "${attr%%=*}" "$(expand_pattern "${attr#*=}")"
    done
}

# ---------------------------------------------------------------------------
# LDAP
# ---------------------------------------------------------------------------
LDAP_COMMON_OPTS=()
LDAP_BIND_OPTS=()
LDAP_AUTH_READY=0
LDAP_PWFILE=""

ldap_build_common_opts() {
    LDAP_COMMON_OPTS=(-H "$LDAP_URI")
    [ "$LDAP_TLS" = "starttls" ] && LDAP_COMMON_OPTS+=(-ZZ)
    # Les réglages TLS passent par l'environnement : l'option -o des clients
    # OpenLDAP ne les accepte pas, alors que LDAPTLS_* surcharge ldap.conf.
    [ -n "$LDAP_TLS_CACERT" ] && export LDAPTLS_CACERT="$LDAP_TLS_CACERT"
    [ -n "$LDAP_TLS_REQCERT" ] && export LDAPTLS_REQCERT="$LDAP_TLS_REQCERT"
    if [ -n "$LDAP_EXTRA_OPTS" ]; then
        # shellcheck disable=SC2206
        local extra=($LDAP_EXTRA_OPTS)
        LDAP_COMMON_OPTS+=("${extra[@]}")
    fi
}

ldap_auth_prepare() {
    [ "$LDAP_AUTH_READY" = "1" ] && return 0
    LDAP_BIND_OPTS=()
    case "$LDAP_AUTH" in
        none)
            LDAP_BIND_OPTS=(-x)
            ;;
        sasl)
            LDAP_BIND_OPTS=(-Y "$LDAP_SASL_MECH")
            [ -n "$BIND_DN" ] && LDAP_BIND_OPTS+=(-D "$BIND_DN")
            if [ -n "$LDAP_SASL_OPTS" ]; then
                # shellcheck disable=SC2206
                local sopts=($LDAP_SASL_OPTS)
                LDAP_BIND_OPTS+=("${sopts[@]}")
            fi
            ;;
        file)
            [ -f "$LDAP_BIND_PASSWORD_FILE" ] || die "LDAP_BIND_PASSWORD_FILE introuvable : $LDAP_BIND_PASSWORD_FILE"
            LDAP_BIND_OPTS=(-x -D "$BIND_DN" -y "$LDAP_BIND_PASSWORD_FILE")
            ;;
        env)
            local envvar="$LDAP_BIND_PASSWORD_ENV"
            [ -n "${!envvar:-}" ] || die "la variable d'environnement ${envvar} est vide"
            LDAP_PWFILE=$(mktemp_tracked)
            printf '%s' "${!envvar}" > "$LDAP_PWFILE"
            LDAP_BIND_OPTS=(-x -D "$BIND_DN" -y "$LDAP_PWFILE")
            ;;
        password)
            [ -n "$LDAP_BIND_PASSWORD" ] || die "LDAP_BIND_PASSWORD est vide"
            LDAP_PWFILE=$(mktemp_tracked)
            printf '%s' "$LDAP_BIND_PASSWORD" > "$LDAP_PWFILE"
            LDAP_BIND_OPTS=(-x -D "$BIND_DN" -y "$LDAP_PWFILE")
            ;;
        prompt)
            local pw
            LDAP_PWFILE=$(mktemp_tracked)
            read -rsp "Mot de passe LDAP (${BIND_DN}) : " pw
            echo
            printf '%s' "$pw" > "$LDAP_PWFILE"
            unset pw
            LDAP_BIND_OPTS=(-x -D "$BIND_DN" -y "$LDAP_PWFILE")
            ;;
    esac
    LDAP_AUTH_READY=1
}

# ldap_run <commande ldap*> [arguments...]
ldap_run() {
    local bin="$1"; shift
    ldap_auth_prepare
    debug "$bin ${LDAP_COMMON_OPTS[*]} <bind> $*"
    "$bin" "${LDAP_COMMON_OPTS[@]}" "${LDAP_BIND_OPTS[@]}" "$@"
}

ldap_check_connection() {
    ldap_run ldapsearch -LLL -b "$BASE_DN" -s base dn >/dev/null 2>&1
}

ldap_user_dn() {
    printf '%s=%s,%s' "$UID_ATTR" "$1" "$USERS_DN"
}

ldap_group_dn() {
    printf '%s=%s,%s' "$GROUP_ATTR" "$1" "$GROUPS_DN"
}

ldap_user_exists() {
    local n
    n=$(ldap_run ldapsearch -LLL -b "$USERS_DN" \
        "(&${USER_FILTER}(${UID_ATTR}=$1))" dn 2>/dev/null | grep -c '^dn:')
    [ "$n" -gt 0 ]
}

ldap_group_exists() {
    local n
    n=$(ldap_run ldapsearch -LLL -b "$GROUPS_DN" \
        "(&${GROUP_FILTER}(${GROUP_ATTR}=$1))" dn 2>/dev/null | grep -c '^dn:')
    [ "$n" -gt 0 ]
}

ldap_group_gid() {
    ldap_run ldapsearch -LLL -b "$GROUPS_DN" \
        "(&${GROUP_FILTER}(${GROUP_ATTR}=$1))" gidNumber 2>/dev/null \
        | awk '/^gidNumber:/ {print $2; exit}'
}

ldap_list_uidnumbers() {
    ldap_run ldapsearch -LLL -b "$USERS_DN" "$USER_FILTER" uidNumber 2>/dev/null \
        | awk '/^uidNumber:/ {print $2}' | sort -n
}

# Prochain uidNumber libre, selon UID_ALLOCATION.
next_uid() {
    local used candidate
    used=$(ldap_list_uidnumbers)
    if [ "$UID_ALLOCATION" = "first" ]; then
        candidate="$UID_MIN"
        while echo "$used" | grep -qx "$candidate"; do
            candidate=$((candidate + 1))
        done
    else
        local last
        last=$(echo "$used" | awk -v min="$UID_MIN" '$1 >= min {v=$1} END {print v}')
        if [ -z "$last" ]; then
            candidate="$UID_MIN"
        else
            candidate=$((last + 1))
        fi
    fi
    [ "$candidate" -le "$UID_MAX" ] || die "plus d'UID disponible dans la plage ${UID_MIN}-${UID_MAX}"
    echo "$candidate"
}

# ---------------------------------------------------------------------------
# Kerberos
# ---------------------------------------------------------------------------
krb5_enabled() { [ "${KRB5_ENABLED:-0}" = "1" ]; }

kadmin_run() {
    # shellcheck disable=SC2206
    local cmd=(${KRB5_ADMIN_CMD} ${KRB5_ADMIN_OPTS})
    "${cmd[@]}" -q "$1" 2>&1
}

kerberos_principal_exists() {
    krb5_enabled || return 1
    kadmin_run "getprinc $1" | grep -q "^Principal: ${1}@${KRB5_REALM}"
}

# kadmin.local renvoie 0 même en cas d'échec de saisie du mot de passe :
# on vérifie donc le message de confirmation, avec plusieurs tentatives.
kerberos_create_principal() {
    local username="$1" attempt=1 out opts="$KRB5_ADDPRINC_OPTS"
    [ "$KRB5_PASSWORD_MODE" = "random" ] && opts="-randkey $opts"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "${C_YELLOW}[dry-run]${C_RESET} ${KRB5_ADMIN_CMD} -q \"addprinc ${opts} ${username}\""
        return 0
    fi
    while [ "$attempt" -le "$KRB5_MAX_RETRIES" ]; do
        out=$(kadmin_run "addprinc ${opts} ${username}")
        if echo "$out" | grep -q "^Principal \"${username}@${KRB5_REALM}\" created"; then
            return 0
        fi
        echo "$out" | grep -v "^Authenticating\|^No policy specified" >&2
        warn "tentative ${attempt}/${KRB5_MAX_RETRIES} échouée"
        attempt=$((attempt + 1))
    done
    return 1
}

kerberos_delete_principal() {
    krb5_enabled || return 0
    run_quiet_kadmin "delprinc -force $1"
}

kerberos_change_password() {
    local username="$1"
    if [ "$KRB5_PASSWORD_MODE" = "random" ]; then
        run_quiet_kadmin "cpw -randkey ${username}"
    else
        # Interactif : on laisse kadmin dialoguer avec le terminal.
        if [ "${DRY_RUN:-0}" = "1" ]; then
            echo "${C_YELLOW}[dry-run]${C_RESET} ${KRB5_ADMIN_CMD} -q \"cpw ${username}\""
            return 0
        fi
        # shellcheck disable=SC2206
        local cmd=(${KRB5_ADMIN_CMD} ${KRB5_ADMIN_OPTS})
        "${cmd[@]}" -q "cpw ${username}"
    fi
}

run_quiet_kadmin() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "${C_YELLOW}[dry-run]${C_RESET} ${KRB5_ADMIN_CMD} -q \"$1\""
        return 0
    fi
    kadmin_run "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Répertoires personnels
# ---------------------------------------------------------------------------
home_enabled() { [ "${HOME_ENABLED:-0}" = "1" ]; }

home_subpath() { expand_pattern "$HOME_PATTERN"; }
home_physical() { printf '%s/%s' "$HOME_ROOT" "$(home_subpath)"; }
home_logical()  { printf '%s/%s' "$HOME_LOGICAL_ROOT" "$(home_subpath)"; }

home_create() {
    local dir="$1" uidn="$2" gidn="$3"
    run mkdir -p "$dir"
    if [ -n "$HOME_SKEL" ] && [ -d "$HOME_SKEL" ]; then
        if [ "${DRY_RUN:-0}" = "1" ]; then
            echo "${C_YELLOW}[dry-run]${C_RESET} cp -a ${HOME_SKEL}/. ${dir}/"
        else
            cp -a "${HOME_SKEL}/." "$dir/" 2>/dev/null || warn "copie du squelette ${HOME_SKEL} incomplète"
        fi
    fi
    [ "${HOME_CHOWN:-1}" = "1" ] && run chown -R "${uidn}:${gidn}" "$dir"
    run chmod "$HOME_MODE" "$dir"
}

home_remove_or_archive() {
    local dir="$1" action="$2"
    if [ ! -d "$dir" ]; then
        info "aucun répertoire à traiter ($dir)"
        return 0
    fi
    case "$action" in
        keep)
            info "répertoire conservé : $dir"
            ;;
        purge)
            log "Suppression définitive de $dir"
            run rm -rf "$dir"
            ;;
        archive)
            run mkdir -p "$ARCHIVE_DIR"
            local name dest
            name=$(expand_pattern "$ARCHIVE_NAME_PATTERN")
            if [ "$ARCHIVE_FORMAT" = "tar" ]; then
                dest="${ARCHIVE_DIR}/${name}.tar.gz"
                log "Archivage de $dir vers $dest"
                run tar -czf "$dest" -C "$(dirname "$dir")" "$(basename "$dir")"
                run rm -rf "$dir"
            else
                dest="${ARCHIVE_DIR}/${name}"
                log "Archivage de $dir vers $dest"
                run mv "$dir" "$dest"
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Hooks
# ---------------------------------------------------------------------------
run_hook() {
    local name="$1" cmd
    cmd="${!name:-}"
    [ -n "$cmd" ] || return 0
    log "Hook ${name}"
    export LS_ACTION="${LS_ACTION:-}" LS_USERNAME="${USERNAME:-}" \
           LS_FIRSTNAME="${FIRSTNAME:-}" LS_LASTNAME="${LASTNAME:-}" \
           LS_UID="${UID_NUMBER:-}" LS_GID="${GID_NUMBER:-}" \
           LS_HOME="${HOME_PHYSICAL:-}" LS_USER_DN="${USER_DN:-}" \
           LS_GROUP="${GROUP_NAME:-}"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "${C_YELLOW}[dry-run]${C_RESET} $cmd"
        return 0
    fi
    bash -c "$cmd" || warn "le hook ${name} a retourné une erreur"
}

flush_cache() {
    [ -n "${CACHE_FLUSH_CMD:-}" ] || return 0
    run bash -c "$CACHE_FLUSH_CMD" || warn "échec de ${CACHE_FLUSH_CMD}"
}

# ---------------------------------------------------------------------------
# Divers
# ---------------------------------------------------------------------------
validate_username() {
    local u="$1"
    [ -n "$USERNAME_PATTERN" ] || return 0
    [[ "$u" =~ $USERNAME_PATTERN ]] || \
        die "nom de compte invalide : '$u' (doit correspondre à ${USERNAME_PATTERN})"
}

random_password() {
    local len="${1:-16}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$len"
    else
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len"
    fi
    echo
}
