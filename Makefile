COMPOSE=docker compose -f infra/docker-compose.yml

.PHONY: up down logs build test backend-test frontend-build

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=200

build:
	$(COMPOSE) build

test: backend-test frontend-build

backend-test:
	cd backend && python3 -m pytest

frontend-build:
	cd frontend && npm install && npm run build

