all: test

test: install
	@echo "Testing..."
	@python test/runner.py test/

.PHONY: test
