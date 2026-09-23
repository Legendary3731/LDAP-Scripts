# Makefile de ldap-scripts
#
# L'installation est faite par ./install.sh : ce Makefile n'est qu'une façade
# pour ceux qui tapent 'make install' par habitude, et pour les outils
# d'empaquetage qui s'attendent à DESTDIR/PREFIX.
#
#   make install
#   make install SYSCONFDIR=/etc/ldap-scripts
#   make install DESTDIR=/tmp/pkg PREFIX=/usr
#   make uninstall
#   make check

PREFIX     ?= /usr/local
DESTDIR    ?=
SBINDIR    ?=
LIBDIR     ?=
SYSCONFDIR ?=
DOCDIR     ?=
COMPDIR    ?=

INSTALL_SH  = ./install.sh
OPTS        = --prefix '$(PREFIX)'
ifneq ($(DESTDIR),)
OPTS       += --destdir '$(DESTDIR)'
endif
ifneq ($(SBINDIR),)
OPTS       += --sbindir '$(SBINDIR)'
endif
ifneq ($(LIBDIR),)
OPTS       += --libdir '$(LIBDIR)'
endif
ifneq ($(SYSCONFDIR),)
OPTS       += --sysconfdir '$(SYSCONFDIR)'
endif
ifneq ($(DOCDIR),)
OPTS       += --docdir '$(DOCDIR)'
endif
ifneq ($(COMPDIR),)
OPTS       += --compdir '$(COMPDIR)'
endif

.PHONY: all help install uninstall check

all: help

help:
	@echo "Cibles :"
	@echo "  make install     Installe (voir aussi ./install.sh --help)"
	@echo "  make uninstall   Désinstalle, la configuration est conservée"
	@echo "  make check       Vérifie la syntaxe des scripts"
	@echo
	@echo "Variables : PREFIX DESTDIR SBINDIR LIBDIR SYSCONFDIR DOCDIR COMPDIR"
	@echo "Exemple   : make install SYSCONFDIR=/etc/ldap-scripts"

install:
	@$(INSTALL_SH) $(OPTS)

uninstall:
	@$(INSTALL_SH) $(OPTS) --uninstall

check:
	@$(INSTALL_SH) --check
