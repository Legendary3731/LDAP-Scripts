# Makefile de ldap-scripts
#
# Tout est paramétrable en ligne de commande :
#   make install PREFIX=/opt/ldap-scripts
#   make install DESTDIR=/tmp/pkg SYSCONFDIR=/etc/ldap-scripts
#   make install-completion
#   make check          (vérifie la syntaxe de tous les scripts)

PKGNAME    ?= ldap-scripts
PREFIX     ?= /usr/local
SBINDIR    ?= $(PREFIX)/sbin
LIBDIR     ?= $(PREFIX)/lib/$(PKGNAME)
SYSCONFDIR ?= $(PREFIX)/etc/$(PKGNAME)
DOCDIR     ?= $(PREFIX)/share/doc/$(PKGNAME)
COMPDIR    ?= $(PREFIX)/share/bash-completion/completions

INSTALL    ?= install
SCRIPTS     = ldapadduser ldapdeleteuser ldapsetpasswd ldapfinger lsldap ldapconfig

.PHONY: all install install-completion uninstall check help

all: help

help:
	@echo "Cibles disponibles :"
	@echo "  make install              Installe scripts, bibliothèque, config et templates"
	@echo "  make install-completion   Installe la complétion bash"
	@echo "  make uninstall            Désinstalle (la configuration est conservée)"
	@echo "  make check                Vérifie la syntaxe des scripts"
	@echo
	@echo "Variables : PREFIX=$(PREFIX) SBINDIR=$(SBINDIR)"
	@echo "            LIBDIR=$(LIBDIR) SYSCONFDIR=$(SYSCONFDIR)"

install:
	$(INSTALL) -d $(DESTDIR)$(SBINDIR) $(DESTDIR)$(LIBDIR) \
	             $(DESTDIR)$(SYSCONFDIR)/templates $(DESTDIR)$(SYSCONFDIR)/conf.d \
	             $(DESTDIR)$(DOCDIR)
	@# Les chemins d'installation sont injectés dans les scripts et la lib,
	@# ce qui évite toute dépendance à l'arborescence source.
	@for s in $(SCRIPTS); do \
		sed -e 's|@LIBDIR@|$(LIBDIR)|g' -e 's|@SYSCONFDIR@|$(SYSCONFDIR)|g' \
			sbin/$$s > $(DESTDIR)$(SBINDIR)/$$s; \
		chmod 755 $(DESTDIR)$(SBINDIR)/$$s; \
		echo "  installé $(SBINDIR)/$$s"; \
	done
	@sed -e 's|@LIBDIR@|$(LIBDIR)|g' -e 's|@SYSCONFDIR@|$(SYSCONFDIR)|g' \
		lib/runtime.sh > $(DESTDIR)$(LIBDIR)/runtime.sh
	@chmod 644 $(DESTDIR)$(LIBDIR)/runtime.sh
	$(INSTALL) -m 644 lib/defaults.sh $(DESTDIR)$(LIBDIR)/defaults.sh
	$(INSTALL) -m 644 etc/templates/*.ldif $(DESTDIR)$(SYSCONFDIR)/templates/
	$(INSTALL) -m 644 etc/conf.d/README $(DESTDIR)$(SYSCONFDIR)/conf.d/README
	$(INSTALL) -m 644 README.md CONFIGURATION.md $(DESTDIR)$(DOCDIR)/
	@# La configuration existante n'est jamais écrasée.
	@if [ -f $(DESTDIR)$(SYSCONFDIR)/$(PKGNAME).conf ]; then \
		echo "  conservé $(SYSCONFDIR)/$(PKGNAME).conf (existant)"; \
		$(INSTALL) -m 644 etc/ldap-scripts.conf $(DESTDIR)$(SYSCONFDIR)/$(PKGNAME).conf.example; \
	else \
		$(INSTALL) -m 640 etc/ldap-scripts.conf $(DESTDIR)$(SYSCONFDIR)/$(PKGNAME).conf; \
		echo "  installé $(SYSCONFDIR)/$(PKGNAME).conf"; \
	fi
	@echo
	@echo "Installation terminée. Étapes suivantes :"
	@echo "  1. $(SBINDIR)/ldapconfig init      # ou éditer $(SYSCONFDIR)/$(PKGNAME).conf"
	@echo "  2. $(SBINDIR)/ldapconfig check     # vérifier la configuration"

install-completion:
	$(INSTALL) -d $(DESTDIR)$(COMPDIR)
	$(INSTALL) -m 644 share/bash-completion/ldap-scripts $(DESTDIR)$(COMPDIR)/$(PKGNAME)
	@echo "  installé $(COMPDIR)/$(PKGNAME)"

uninstall:
	@for s in $(SCRIPTS); do rm -f $(DESTDIR)$(SBINDIR)/$$s; done
	rm -f $(DESTDIR)$(LIBDIR)/runtime.sh $(DESTDIR)$(LIBDIR)/defaults.sh
	rm -f $(DESTDIR)$(COMPDIR)/$(PKGNAME)
	-rmdir $(DESTDIR)$(LIBDIR) 2>/dev/null || true
	@echo "Désinstallé. $(SYSCONFDIR) a été conservé."

check:
	@rc=0; \
	for f in sbin/* lib/*.sh share/bash-completion/*; do \
		if bash -n "$$f"; then echo "  ok      $$f"; \
		else echo "  ERREUR  $$f"; rc=1; fi; \
	done; \
	if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -S warning sbin/* lib/*.sh || rc=1; \
	else \
		echo "  (shellcheck absent, analyse statique ignorée)"; \
	fi; \
	exit $$rc
