#!/bin/bash
# install.sh - Installe, désinstalle ou vérifie ldap-scripts.
#
# Le projet est entièrement écrit en shell : son installateur l'est aussi,
# pour ne dépendre que de ce qui est déjà présent sur un serveur d'annuaire.
#
#   ./install.sh                                   installation par défaut
#   ./install.sh --sysconfdir /etc/ldap-scripts    configuration dans /etc
#   ./install.sh --prefix /opt/ldap-scripts
#   ./install.sh --destdir /tmp/pkg                pour empaqueter
#   ./install.sh --uninstall
#   ./install.sh --check
#
# Les variables à la manière de make sont acceptées : ./install.sh PREFIX=/opt

set -euo pipefail

PKGNAME="ldap-scripts"
SCRIPTS=(ldapadduser ldapdeleteuser ldapsetpasswd ldapfinger lsldap ldapconfig)

SRCDIR="$(cd "$(dirname "$0")" && pwd)"
DESTDIR=""
PREFIX="/usr/local"
SBINDIR=""
LIBDIR=""
SYSCONFDIR=""
DOCDIR=""
COMPDIR=""
WITH_COMPLETION=1
ACTION="install"
DRY_RUN=0

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

log()  { echo "${C_BLUE}==>${C_RESET} $*"; }
ok()   { echo "${C_GREEN}  ok${C_RESET} $*"; }
warn() { echo "${C_YELLOW}Attention:${C_RESET} $*" >&2; }
die()  { echo "${C_RED}Erreur:${C_RESET} $*" >&2; exit 1; }

run() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "${C_YELLOW}[dry-run]${C_RESET} $*"
        return 0
    fi
    "$@"
}

usage() {
    cat <<'USAGE'
install.sh - Installation de ldap-scripts

Usage :
  ./install.sh [options]

Options :
      --prefix CHEMIN      Racine d'installation (défaut : /usr/local)
      --sbindir CHEMIN     Commandes         (défaut : <prefix>/sbin)
      --libdir CHEMIN      Bibliothèque      (défaut : <prefix>/lib/ldap-scripts)
      --sysconfdir CHEMIN  Configuration     (défaut : <prefix>/etc/ldap-scripts)
      --docdir CHEMIN      Documentation     (défaut : <prefix>/share/doc/ldap-scripts)
      --compdir CHEMIN     Complétion bash   (défaut : <prefix>/share/bash-completion/completions)
      --destdir CHEMIN     Préfixe de destination, pour empaqueter
      --no-completion      N'installe pas la complétion bash
  -n, --dry-run            Affiche les actions sans rien écrire
      --uninstall          Désinstalle (la configuration est conservée)
      --check              Vérifie la syntaxe des scripts et s'arrête
  -h, --help               Affiche cette aide

Exemples :
  sudo ./install.sh --sysconfdir /etc/ldap-scripts
  sudo ./install.sh --prefix /opt/ldap-scripts --no-completion
  ./install.sh --destdir /tmp/pkg --dry-run
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)       PREFIX="$2"; shift 2 ;;
        --prefix=*)     PREFIX="${1#*=}"; shift ;;
        --sbindir)      SBINDIR="$2"; shift 2 ;;
        --sbindir=*)    SBINDIR="${1#*=}"; shift ;;
        --libdir)       LIBDIR="$2"; shift 2 ;;
        --libdir=*)     LIBDIR="${1#*=}"; shift ;;
        --sysconfdir)   SYSCONFDIR="$2"; shift 2 ;;
        --sysconfdir=*) SYSCONFDIR="${1#*=}"; shift ;;
        --docdir)       DOCDIR="$2"; shift 2 ;;
        --docdir=*)     DOCDIR="${1#*=}"; shift ;;
        --compdir)      COMPDIR="$2"; shift 2 ;;
        --compdir=*)    COMPDIR="${1#*=}"; shift ;;
        --destdir)      DESTDIR="$2"; shift 2 ;;
        --destdir=*)    DESTDIR="${1#*=}"; shift ;;
        --no-completion) WITH_COMPLETION=0; shift ;;
        -n|--dry-run)   DRY_RUN=1; shift ;;
        --uninstall)    ACTION="uninstall"; shift ;;
        --check)        ACTION="check"; shift ;;
        -h|--help)      usage; exit 0 ;;
        # Compatibilité avec les habitudes de make : PREFIX=/opt, DESTDIR=...
        # Seuls les noms connus sont acceptés : une faute de frappe doit se
        # voir tout de suite, pas s'installer silencieusement au mauvais endroit.
        PREFIX=*|DESTDIR=*|SBINDIR=*|LIBDIR=*|SYSCONFDIR=*|DOCDIR=*|COMPDIR=*)
            printf -v "${1%%=*}" '%s' "${1#*=}"; shift ;;
        [A-Za-z_]*=*)
            die "variable inconnue : ${1%%=*} (attendu : PREFIX, DESTDIR, SBINDIR, LIBDIR, SYSCONFDIR, DOCDIR, COMPDIR)" ;;
        *)              die "option inconnue : $1 (voir --help)" ;;
    esac
done

[ -n "$SBINDIR" ]    || SBINDIR="${PREFIX}/sbin"
[ -n "$LIBDIR" ]     || LIBDIR="${PREFIX}/lib/${PKGNAME}"
[ -n "$SYSCONFDIR" ] || SYSCONFDIR="${PREFIX}/etc/${PKGNAME}"
[ -n "$DOCDIR" ]     || DOCDIR="${PREFIX}/share/doc/${PKGNAME}"
[ -n "$COMPDIR" ]    || COMPDIR="${PREFIX}/share/bash-completion/completions"

# ---------------------------------------------------------------------------
# Vérification de la syntaxe
# ---------------------------------------------------------------------------
do_check() {
    local rc=0 f
    for f in "$SRCDIR"/sbin/* "$SRCDIR"/lib/*.sh "$SRCDIR"/install.sh \
             "$SRCDIR"/share/bash-completion/*; do
        if bash -n "$f" 2>/dev/null; then
            ok "${f#"$SRCDIR"/}"
        else
            echo "${C_RED}  KO${C_RESET} ${f#"$SRCDIR"/}"
            bash -n "$f" || true
            rc=1
        fi
    done
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck -S warning "$SRCDIR"/sbin/* "$SRCDIR"/lib/*.sh || rc=1
    else
        echo "  (shellcheck absent, analyse statique ignorée)"
    fi
    return $rc
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------
do_install() {
    [ -f "$SRCDIR/lib/runtime.sh" ] || die "lancer ce script depuis le dossier du projet"

    local v="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    case "${BASH_VERSINFO[0]}" in
        [0-3]) die "bash 4.1 ou plus récent est requis (version détectée : $v)" ;;
        4) [ "${BASH_VERSINFO[1]}" -ge 1 ] || die "bash 4.1 ou plus récent est requis (version détectée : $v)" ;;
    esac

    if [ "$DRY_RUN" != "1" ] && [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
        warn "installation hors de ton répertoire personnel sans être root : ça va probablement échouer"
    fi

    log "Création des répertoires"
    run mkdir -p "${DESTDIR}${SBINDIR}" "${DESTDIR}${LIBDIR}" \
                 "${DESTDIR}${SYSCONFDIR}/templates" "${DESTDIR}${SYSCONFDIR}/conf.d" \
                 "${DESTDIR}${DOCDIR}"

    # Les chemins réels sont injectés dans les scripts : une fois installés,
    # ils ne dépendent plus de l'emplacement des sources.
    log "Installation des commandes dans ${SBINDIR}"
    local s
    for s in "${SCRIPTS[@]}"; do
        if [ "$DRY_RUN" = "1" ]; then
            echo "${C_YELLOW}[dry-run]${C_RESET} sbin/$s -> ${DESTDIR}${SBINDIR}/$s"
        else
            sed -e "s|@LIBDIR@|${LIBDIR}|g" -e "s|@SYSCONFDIR@|${SYSCONFDIR}|g" \
                "$SRCDIR/sbin/$s" > "${DESTDIR}${SBINDIR}/$s"
            chmod 755 "${DESTDIR}${SBINDIR}/$s"
            ok "$s"
        fi
    done

    log "Installation de la bibliothèque dans ${LIBDIR}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "${C_YELLOW}[dry-run]${C_RESET} lib/runtime.sh, lib/defaults.sh -> ${DESTDIR}${LIBDIR}/"
    else
        sed -e "s|@LIBDIR@|${LIBDIR}|g" -e "s|@SYSCONFDIR@|${SYSCONFDIR}|g" \
            "$SRCDIR/lib/runtime.sh" > "${DESTDIR}${LIBDIR}/runtime.sh"
        chmod 644 "${DESTDIR}${LIBDIR}/runtime.sh"
        install -m 644 "$SRCDIR/lib/defaults.sh" "${DESTDIR}${LIBDIR}/defaults.sh"
        ok "runtime.sh, defaults.sh"
    fi

    log "Installation des templates et de la documentation"
    run install -m 644 "$SRCDIR"/etc/templates/*.ldif "${DESTDIR}${SYSCONFDIR}/templates/"
    run install -m 644 "$SRCDIR/etc/conf.d/README" "${DESTDIR}${SYSCONFDIR}/conf.d/README"
    run install -m 644 "$SRCDIR/README.md" "$SRCDIR/CONFIGURATION.md" "${DESTDIR}${DOCDIR}/"

    # Une configuration existante n'est jamais écrasée.
    local conf="${DESTDIR}${SYSCONFDIR}/${PKGNAME}.conf"
    if [ -f "$conf" ]; then
        run install -m 644 "$SRCDIR/etc/ldap-scripts.conf" "${conf}.example"
        ok "configuration existante conservée (nouvel exemple : ${SYSCONFDIR}/${PKGNAME}.conf.example)"
    else
        run install -m 640 "$SRCDIR/etc/ldap-scripts.conf" "$conf"
        ok "configuration installée : ${SYSCONFDIR}/${PKGNAME}.conf"
    fi

    if [ "$WITH_COMPLETION" = "1" ]; then
        log "Installation de la complétion bash dans ${COMPDIR}"
        run mkdir -p "${DESTDIR}${COMPDIR}"
        # bash-completion charge le fichier portant le nom de la commande
        # tapée : il en faut donc un par commande.
        local first=""
        for s in "${SCRIPTS[@]}"; do
            if [ -z "$first" ]; then
                run install -m 644 "$SRCDIR/share/bash-completion/ldap-scripts" \
                    "${DESTDIR}${COMPDIR}/$s"
                first="$s"
            else
                run ln -sf "$first" "${DESTDIR}${COMPDIR}/$s"
            fi
        done
        ok "${#SCRIPTS[@]} commandes complétées"
    fi

    echo
    log "Installation terminée."
    local missing=()
    local tool
    for tool in ldapsearch ldapadd ldapmodify ldapdelete; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        warn "outils absents : ${missing[*]} (paquet ldap-utils ou openldap-clients)"
    fi
    echo "  1. ${SBINDIR}/ldapconfig init     # ou éditer ${SYSCONFDIR}/${PKGNAME}.conf"
    echo "  2. ${SBINDIR}/ldapconfig check    # vérifier la configuration"
}

# ---------------------------------------------------------------------------
# Désinstallation
# ---------------------------------------------------------------------------
do_uninstall() {
    log "Suppression des commandes"
    local s
    for s in "${SCRIPTS[@]}"; do
        run rm -f "${DESTDIR}${SBINDIR}/$s" "${DESTDIR}${COMPDIR}/$s"
    done
    run rm -f "${DESTDIR}${LIBDIR}/runtime.sh" "${DESTDIR}${LIBDIR}/defaults.sh"
    run rmdir "${DESTDIR}${LIBDIR}" 2>/dev/null || true
    echo
    log "Désinstallé. ${SYSCONFDIR} a été conservé : supprime-le à la main si tu n'en veux plus."
}

case "$ACTION" in
    check)     do_check ;;
    install)   do_install ;;
    uninstall) do_uninstall ;;
esac
