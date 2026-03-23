.PHONY: test help

help:
	@echo "Available targets:"
	@echo "  test    - Run unit tests"

test:
	@nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/init.lua' }" -c "qa!"


