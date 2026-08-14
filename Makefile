PREFIX ?= $(HOME)/.local

build:
	swift build -c release

# Ad-hoc sign the installed copy: TCC (Full Disk Access for watch mode)
# refuses to match an unsigned binary against its recorded requirement.
install: build
	install -d $(PREFIX)/bin
	install .build/release/kbglow $(PREFIX)/bin/kbglow
	codesign --force -s - -i dev.totota08.kbglow $(PREFIX)/bin/kbglow

uninstall:
	rm -f $(PREFIX)/bin/kbglow

clean:
	swift package clean

.PHONY: build install uninstall clean
