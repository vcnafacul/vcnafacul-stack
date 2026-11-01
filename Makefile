# Makefile — stack do Você na Facul em docker compose (tickets/055).
# `make help` lista os alvos. Modos:
#   make up        → modo local: apps + MySQL/Mongo/MinIO locais (dados de teste)
#   make up-homol  → modo homol: apps locais falando com os bancos do .env de cada repo

DOCKER  := $(shell command -v docker 2>/dev/null || echo /opt/homebrew/opt/docker/bin/docker)
RAIZ    := ..
LOCAL   := $(DOCKER) compose -p vcnafacul-local --env-file .env.compose -f docker-compose.yml -f docker-compose.dados-locais.yml
HOMOL   := $(DOCKER) compose -p vcnafacul-homol --env-file .env.compose -f docker-compose.yml
REPOS   := api-vcnafacul ms-simulado ms-omr vcnafacul-form client-vcnafacul
VOLUMES := api ms form client
MODO    := $(shell cat .modo 2>/dev/null)
ATUAL   := $(if $(filter homol,$(MODO)),$(HOMOL),$(LOCAL))

.DEFAULT_GOAL := help
.PHONY: help check-env check-local check-homol up up-homol infra down down-v ps logs restart stop start migrate seed-mongo urls

help: ## lista os alvos
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo "  modo atual: $(if $(MODO),$(MODO),nenhum)"

check-env: ## confere os 5 .env e o .env.compose (e cria os volumes de node_modules)
	@for v in $(VOLUMES); do $(DOCKER) volume create vcnafacul-stack_$${v}_node_modules >/dev/null; done
	@falta=0; \
	for r in $(REPOS); do \
	  if [ -f "$(RAIZ)/$$r/.env" ]; then echo "✔ $$r/.env"; \
	  else echo "❌ falta $$r/.env — copie do $$r/.env.example"; falta=1; fi; \
	done; \
	if [ -f .env.compose ]; then echo "✔ .env.compose"; \
	else echo "❌ falta .env.compose — cp .env.compose.example .env.compose"; falta=1; fi; \
	[ $$falta -eq 0 ]

check-local: ## falha se algum app do modo local apontar para banco/bucket remoto
	@$(LOCAL) config --format json | python3 scripts/conferir-modo-local.py

check-homol: ## falha se algum .env tiver banco/bucket em localhost
	@python3 scripts/conferir-modo-homol.py $(RAIZ)

up: check-env check-local ## modo local: sobe tudo com dados locais
	@$(HOMOL) down --remove-orphans 2>/dev/null || true
	$(LOCAL) up -d --build
	@echo local > .modo
	@$(MAKE) --no-print-directory urls

up-homol: check-env check-homol ## modo homol: apps locais, bancos do .env (homol)
	@$(LOCAL) down --remove-orphans 2>/dev/null || true
	$(HOMOL) up -d --build
	@echo homol > .modo
	@$(MAKE) --no-print-directory urls

infra: check-env ## só MySQL, Mongo, MinIO, Redis e Mailpit (apps rodando no host)
	@$(HOMOL) down --remove-orphans 2>/dev/null || true
	$(LOCAL) up -d mysql mongo-init minio-init redis mailpit
	@echo local > .modo

down: ## derruba o modo atual (mantém os dados)
	$(ATUAL) down --remove-orphans
	@rm -f .modo

down-v: ## modo local: derruba E apaga MySQL/Mongo/MinIO/Mailpit (node_modules ficam)
	@if [ "$(MODO)" = "homol" ]; then echo "❌ down-v só no modo local"; exit 1; fi
	$(LOCAL) down -v --remove-orphans
	@rm -f .modo

ps: ## status dos serviços
	$(ATUAL) ps -a

logs: ## logs (-f); um só: make logs s=api
	$(ATUAL) logs -f --tail=100 $(s)

restart: ## reinicia um serviço: make restart s=form
	@if [ -z "$(s)" ]; then echo "uso: make restart s=<serviço>"; exit 1; fi
	$(ATUAL) restart $(s)

stop: ## para um serviço: make stop s=ms-simulado
	@if [ -z "$(s)" ]; then echo "uso: make stop s=<serviço>"; exit 1; fi
	$(ATUAL) stop $(s)

start: ## sobe (ou recria) um serviço sem mexer nos outros: make start s=ms-simulado
	@if [ -z "$(s)" ]; then echo "uso: make start s=<serviço>"; exit 1; fi
	$(ATUAL) up -d --no-deps $(s)

migrate: ## modo local: roda as migrations da api de novo
	@if [ "$(MODO)" = "homol" ]; then echo "❌ migrate só no modo local (homol migra pelo deploy)"; exit 1; fi
	$(LOCAL) run --rm api-migrate

seed-mongo: ## modo local: clona o Mongo de SOURCE_MONGODB (ms-simulado/.env) para o banco simulado local
	@if [ "$(MODO)" = "homol" ]; then echo "❌ seed-mongo só no modo local"; exit 1; fi
	@SRC=$$(grep -E '^[[:space:]]*(export[[:space:]]+)?SOURCE_MONGODB=' $(RAIZ)/ms-simulado/.env | tail -1 | sed -E 's/^[^=]*=//'); \
	if [ -z "$$SRC" ]; then echo "❌ defina SOURCE_MONGODB em ms-simulado/.env"; exit 1; fi; \
	SRCDB=$$(printf '%s' "$$SRC" | sed -E 's#.*/([^/?]+)(\?.*)?$$#\1#'); \
	echo "→ clonando '$$SRCDB' (só leitura no remoto) → mongo local, banco 'simulado'"; \
	$(LOCAL) exec -T mongo sh -c \
	  "mongodump --uri='$$SRC' --archive --gzip | mongorestore --uri='mongodb://localhost:27017/?directConnection=true' --archive --gzip --drop --nsFrom='$$SRCDB.*' --nsTo='simulado.*'"

urls: ## endereços dos serviços
	@echo ""
	@echo "modo: $$(cat .modo 2>/dev/null)"
	@echo "client      → http://localhost:5173"
	@echo "api         → http://localhost:3333/api (swagger)"
	@echo "ms-simulado → http://localhost:3000/api"
	@echo "form        → http://localhost:3334"
	@echo "ms-omr      → http://localhost:8000/health"
	@echo "mailpit     → http://localhost:8025"
	@if [ "$$(cat .modo 2>/dev/null)" = "local" ]; then \
	  echo "minio       → http://localhost:9001 (minioadmin / minioadmin123)"; \
	  echo "mysql       → localhost:3306 (root / 123456, banco vcnafacul)"; \
	  echo "mongo       → mongodb://localhost:27017/?directConnection=true (bancos simulado e form)"; \
	fi
