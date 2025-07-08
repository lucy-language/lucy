all: clean build install

install: build
	@echo "Installing..."; \
	mkdir -p ~/.local/lib/lucy; \
	cp ./build/lucy ~/.local/lib/lucy/lucy; \
	cp ./stdlib/ ~/.local/lib/lucy/ -r; \
	ln -sf ~/.local/lib/lucy/lucy ~/.local/bin/lucy;

build: clean
	@echo "Building..."; \
	c3c build -l LLVM --trust=full $(shell which git >/dev/null 2>&1 && echo "-D GIT_FOUND");

clean:
	@echo "Cleaning..."; \
	rm -rf ./build; \
	rm -f ~/.local/lib/lucy/lucy;

TEST_FILES := $(wildcard test/*.lc)
test:
	@passed=0; \
	failed=0; \
	total=0; \
	echo "Running tests..."; \
	echo ""; \
	for file in $(TEST_FILES); do \
		./build/lucy compile $$file -a; \
		exit_code=$$?; \
		total=$$((total + 1)); \
		if [ $$exit_code -ne 0 ]; then \
			printf "\u001B[91m❌ Test %-40s FAILED\u001B[0m\n" "$$file"; \
			failed=$$((failed + 1)); \
		else \
			printf "\u001B[92m✅ Test %-40s PASSED\u001B[0m\n" "$$file"; \
			passed=$$((passed + 1)); \
		fi; \
	done; \
	echo ""; \
	if [ $$failed -eq 0 ]; then \
		echo "🎉 All $$total tests passed successfully!"; \
	else \
		echo "📊 Test results: $$passed passed, $$failed failed (total: $$total)"; \
	fi; \

.PHONY: test
