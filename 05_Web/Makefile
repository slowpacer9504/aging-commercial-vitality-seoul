.PHONY: dev build test clean kill help

VENV       := backend/.venv
VENV_BIN   := $(VENV)/bin
PY         := $(VENV_BIN)/python
UV         := uv
RSCRIPT    := Rscript

help:
	@echo "Targets:"
	@echo "  dev      - run uvicorn + vite concurrently (assumes deps installed)"
	@echo "  build    - build R artifacts + Vite production bundle"
	@echo "  test     - run backend pytest + frontend vitest"
	@echo "  install  - install backend (uv) + frontend (npm) deps"
	@echo "  clean    - remove data/ + dist/ + .venv + node_modules caches"
	@echo "  kill     - free ports 8000 and 5173"

install: backend-install frontend-install

backend-install:
	cd backend && $(UV) sync

frontend-install:
	cd frontend && npm install

build: build-data build-frontend

build-data:
	$(RSCRIPT) build_data.R

build-frontend:
	cd frontend && npm run build

dev:
	cd frontend && npx concurrently -k -n api,web \
		"cd ../backend && .venv/bin/uvicorn app.main:app --reload --port 8000 --host 127.0.0.1" \
		"npm run dev"

test: test-backend test-frontend

test-backend:
	cd backend && .venv/bin/pytest -q

test-frontend:
	cd frontend && npm test -- --run

clean:
	rm -rf data frontend/dist backend/.venv frontend/node_modules
	find backend -type d -name __pycache__ -prune -exec rm -rf {} +

kill:
	@for p in 8000 5173; do \
		pid=$$(lsof -ti :$$p 2>/dev/null); \
		if [ -n "$$pid" ]; then echo "killing :$$p ($$pid)"; kill -9 $$pid; fi; \
	done
