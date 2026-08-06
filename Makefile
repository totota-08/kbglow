PREFIX ?= $(HOME)/.local

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install .build/release/kbglow $(PREFIX)/bin/kbglow

uninstall:
	rm -f $(PREFIX)/bin/kbglow

clean:
	swift package clean

.PHONY: build install uninstall clean
