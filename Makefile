## ============================================================
## Makefile — Stack WordPress + Traefik no Docker Swarm
## ============================================================
## Carrega variáveis do .env automaticamente
include .env
export

ENV_VARS = $(shell grep -v '^\#' .env | grep -v '^$$' | xargs)

# ─── DEPLOY ─────────────────────────────────────────────────

## Sobe o traefik-stack (Traefik + MySQL + Adminer)
.PHONY: deploy-traefik
deploy-traefik:
	@echo "→ Deploy traefik-stack..."
	env $(ENV_VARS) docker stack deploy \
		--compose-file traefik-stack.yml \
		--with-registry-auth \
		traefik-stack
	@echo "✓ traefik-stack deployado"

## Sobe o wordpress-stack (Nginx + PHP-FPM)
.PHONY: deploy-wordpress
deploy-wordpress:
	@echo "→ Deploy wordpress-stack..."
	env $(ENV_VARS) docker stack deploy \
		--compose-file wordpress-stack.yml \
		--with-registry-auth \
		wordpress-stack
	@echo "✓ wordpress-stack deployado"

## Deploy completo: traefik primeiro, depois wordpress
.PHONY: deploy
deploy: deploy-traefik deploy-wordpress

# ─── STATUS ─────────────────────────────────────────────────

## Lista todos os serviços dos stacks
.PHONY: status
status:
	@echo "\n=== traefik-stack ==="
	docker stack services traefik-stack
	@echo "\n=== wordpress-stack ==="
	docker stack services wordpress-stack

## Logs do nginx
.PHONY: logs-nginx
logs-nginx:
	docker service logs -f wordpress-stack_nginx

## Logs do php-fpm
.PHONY: logs-phpfpm
logs-phpfpm:
	docker service logs -f wordpress-stack_wpphpfpm

## Logs do traefik
.PHONY: logs-traefik
logs-traefik:
	docker service logs -f traefik-stack_traefik

## Logs do mysql
.PHONY: logs-mysql
logs-mysql:
	docker service logs -f traefik-stack_mysql

# ─── WP-CLI ─────────────────────────────────────────────────

## Abre um shell no container PHP-FPM
.PHONY: shell
shell:
	docker exec -it $$(docker ps -qf "name=wordpress-stack_wpphpfpm") bash

## Atalho para rodar wp-cli: make wp CMD="plugin list"
.PHONY: wp
wp:
	docker exec -it $$(docker ps -qf "name=wordpress-stack_wpphpfpm") wp $(CMD)

# ─── REMOÇÃO ────────────────────────────────────────────────

## Remove o wordpress-stack (mantém volumes)
.PHONY: down-wordpress
down-wordpress:
	docker stack rm wordpress-stack

## Remove o traefik-stack (mantém volumes)
.PHONY: down-traefik
down-traefik:
	docker stack rm traefik-stack

## Remove ambos os stacks
.PHONY: down
down: down-wordpress down-traefik

# ─── AJUDA ──────────────────────────────────────────────────

.PHONY: help
help:
	@echo ""
	@echo "Uso: make <comando>"
	@echo ""
	@echo "  DEPLOY"
	@echo "    deploy           Deploy completo (traefik + wordpress)"
	@echo "    deploy-traefik   Deploy apenas traefik-stack"
	@echo "    deploy-wordpress Deploy apenas wordpress-stack"
	@echo ""
	@echo "  STATUS / LOGS"
	@echo "    status           Lista serviços dos dois stacks"
	@echo "    logs-nginx       Logs do nginx"
	@echo "    logs-phpfpm      Logs do PHP-FPM"
	@echo "    logs-traefik     Logs do Traefik"
	@echo "    logs-mysql       Logs do MySQL"
	@echo ""
	@echo "  WP-CLI"
	@echo "    shell            Shell no container PHP-FPM"
	@echo "    wp CMD=...       Executa comando wp-cli"
	@echo ""
	@echo "  REMOÇÃO"
	@echo "    down             Remove ambos os stacks"
	@echo "    down-wordpress   Remove apenas wordpress-stack"
	@echo "    down-traefik     Remove apenas traefik-stack"
	@echo ""

.DEFAULT_GOAL := help
