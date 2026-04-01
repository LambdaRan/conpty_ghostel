EMACS ?= emacs

.PHONY: all build check test lint byte-compile checkdoc package-lint clean

all: build byte-compile test lint

build:
	./build.sh

check:
	zig build check

test:
	$(EMACS) --batch -Q -L . -l test/ghostel-test.el -f ghostel-test-run-elisp

lint: byte-compile checkdoc package-lint

byte-compile:
	$(EMACS) --batch -Q -L . -f batch-byte-compile ghostel.el ghostel-debug.el

checkdoc:
	@output=$$($(EMACS) --batch -Q -L . \
	  --eval "(require 'checkdoc)" \
	  --eval "(checkdoc-file \"ghostel.el\")" 2>&1); \
	echo "$$output"; \
	if echo "$$output" | grep -q "Warning"; then exit 1; fi

package-lint:
	$(EMACS) --batch -Q \
	  --eval "(progn \
	            (require 'package) \
	            (push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives) \
	            (package-initialize) \
	            (package-refresh-contents) \
	            (package-install 'package-lint))" \
	  -L . \
	  -f package-lint-batch-and-exit \
	  ghostel.el

clean:
	rm -f ghostel-module.dylib ghostel-module.so
	rm -f ghostel.elc ghostel-debug.elc
	rm -rf zig-out .zig-cache
