all: check_deps clean build install test

check_deps:
	

install: build
	@echo "Installing..."
	@mkdir -p ~/.local/lib/lucy
	@cp ./build/lucy ~/.local/lib/lucy/lucy
	@cp ./stdlib/ ~/.local/lib/lucy/ -r
	@ln -sf ~/.local/lib/lucy/lucy ~/.local/bin/lucy

build: check_deps
	@echo "Building..."
	@c3c build -l LLVM --safe=no --trust=full $(shell which git >/dev/null 2>&1 && echo "-D GIT_FOUND")

clean:
	@echo "Cleaning..."
	@rm -rf ./build
	@rm -rf ~/.local/lib/lucy

test:
	@echo "Testing..."
	@lucy -c main.lc -e -vv

.PHONY: test build all clean install
