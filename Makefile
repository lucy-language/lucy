all: check_deps clean build install run test

check_deps:
	

install: build
	@echo "Installing..."
	@mkdir -p ~/.local/lib/lucy
	@cp ./build/lucy ~/.local/lib/lucy/lucy
	@cp ./stdlib/ ~/.local/lib/lucy/ -r
	@ln -sf ~/.local/lib/lucy/lucy ~/.local/bin/lucy

build: clean
	@echo "Building..."
	@c3c build -l LLVM --trust=full $(shell which git >/dev/null 2>&1 && echo "-D GIT_FOUND")

clean:
	@echo "Cleaning..."
	@rm -rf ./build
	@rm -rf ~/.local/lib/lucy
	@rm -f ./main
	@rm -f ./main.ll

run: install
	@echo "Running..."
	@lucy -c main.lc -e
	@./main

test: install
	@echo "Testing..."
	@python test/runner.py test/

.PHONY: test build all clean install
