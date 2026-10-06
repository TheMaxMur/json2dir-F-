PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: all bootstrap verify test differential clean install
all:
	./scripts/build
bootstrap:
	./scripts/bootstrap
verify:
	./scripts/verify
test: all
	python3 tests/test_cli.py
differential: all
	@test -n "$(REFERENCE)" || (echo 'Set REFERENCE=/absolute/path/to/rust/json2dir' >&2; exit 1)
	JSON2DIR_REFERENCE="$(REFERENCE)" python3 tests/test_cli.py
install: all
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 755 json2dir "$(DESTDIR)$(PREFIX)/bin/json2dir"
clean:
	rm -rf .build/cache .build/extracted .build/runtime json2dir
