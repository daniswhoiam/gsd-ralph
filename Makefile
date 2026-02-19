# Makefile for gsd-ralph

BATS := ./tests/bats/bin/bats
SHELLCHECK := shellcheck
SRC_FILES := bin/gsd-ralph $(wildcard lib/*.sh) $(wildcard lib/commands/*.sh)

.PHONY: test lint check install uninstall

check: lint test

test:
	$(BATS) tests/*.bats

lint:
	$(SHELLCHECK) -s bash $(SRC_FILES)

install:
	@echo "Installing gsd-ralph..."
	ln -sf "$(CURDIR)/bin/gsd-ralph" /usr/local/bin/gsd-ralph
	@echo "Installed. Run 'gsd-ralph --help' to verify."

uninstall:
	rm -f /usr/local/bin/gsd-ralph
