.PHONY: install agent-venv agent-dev agent-test desktop-dev desktop-build dev test check

install:
	vp install
	$(MAKE) agent-venv

agent-venv:
	cd services/agent && python3 -m venv .venv && . .venv/bin/activate && python -m pip install --upgrade pip && python -m pip install -e ".[dev]"

agent-dev:
	cd services/agent && . .venv/bin/activate && uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload

agent-test:
	cd services/agent && . .venv/bin/activate && pytest

desktop-dev:
	vp run desktop-dev

desktop-build:
	vp run desktop-build

dev:
	@echo "Run 'make agent-dev' in one terminal, then 'make desktop-dev' in another."

test:
	$(MAKE) agent-test

check:
	vp run check
