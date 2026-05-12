COMPOSE=docker compose -f infra/docker-compose.yml

.PHONY: up down logs build test backend-test qt-build

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=200

build:
	$(COMPOSE) build

test: backend-test qt-build

backend-test:
	cd backend && python3 -m pytest

qt-build:
	cmake -S qt-frontend -B qt-frontend/build -G Ninja -DCMAKE_BUILD_TYPE=Release
	cmake --build qt-frontend/build
