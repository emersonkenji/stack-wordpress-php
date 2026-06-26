# Deploy — Docker Swarm

Guia completo para subir os dois stacks: **Traefik + MySQL + Adminer** e **Nginx + PHP-FPM (WordPress)**.

---

## Arquitetura dos stacks

```
┌──────────────────────────────────────────────────────┐
│  traefik-stack.yml                                   │
│  ┌──────────┐  ┌────────────┐  ┌──────────────────┐ │
│  │  Traefik │  │  MariaDB   │  │     Adminer      │ │
│  │  :80/443 │  │ (internal) │  │ db.dominio.com.br│ │
│  └────┬─────┘  └─────┬──────┘  └────────┬─────────┘ │
│       │ (proxy)      │ (nw-backend)      │           │
└───────┼──────────────┼───────────────────┼───────────┘
        │              │                   │
┌───────┼──────────────┼───────────────────┼───────────┐
│  wordpress-stack.yml │                   │           │
│  ┌────┴─────┐  ┌─────┴──────┐           │           │
│  │  Nginx   │  │  WP-PHP    ├───────────┘           │
│  │ (proxy)  │  │ (internal) │ (nw-backend)           │
│  └──────────┘  └────────────┘                        │
└──────────────────────────────────────────────────────┘
```

### Redes

| Rede | Tipo | Usada por |
|---|---|---|
| `proxy` | overlay external | Traefik ↔ Nginx ↔ Adminer |
| `nw-backend` | overlay external | MySQL ↔ PHP-FPM ↔ Adminer |
| `nw-wp-internal` | overlay interno | Nginx ↔ PHP-FPM (isolado) |

---

## Pré-requisitos

### 1. Docker Swarm inicializado

```bash
docker swarm init
```

### 2. Redes externas

```bash
# Rede pública (Traefik + serviços com rota HTTP)
docker network create --driver=overlay --attachable proxy

# Rede backend (MySQL ↔ PHP-FPM ↔ Adminer)
# Rede backend (MySQL ↔ PHP-FPM ↔ Adminer)
docker network create --driver=overlay --attachable nw-backend
```

### 3. Diretórios no host

```bash
# Let's Encrypt
mkdir -p /data/letsencrypt_data
touch /data/letsencrypt_data/acme.json
chmod 600 /data/letsencrypt_data/acme.json

# MySQL
mkdir -p /data/mysql_data_takadatintas

# Arquivos WordPress
mkdir -p /srv/sites/takadatintas.com.br

# Dump SQL do banco (para restaurar na 1ª inicialização)
cp seu_dump.sql /srv/sites/takadatintas.com.br/takadatintas.sql
```

> **Atenção:** O MariaDB importa o dump apenas na **primeira inicialização** (volume vazio).

---

## Configurar variáveis de ambiente

Edite o arquivo `.env`:

```env
DOMAIN_NAME=takadatintas.com.br
PROJECT_NAME=takadatintas

MYSQL_PASSWORD=sua_senha_segura
MYSQL_ROOT_PASSWORD=sua_senha_root
MYSQL_USER=taka_takadatintas

BACKUP_DATABASE=takadatintas.sql
WORDPRESS_TABLE_PREFIX=wpog_

# Gerado com: echo $(htpasswd -nb admin SENHA) | sed -e s/\$/\$\$/g
ADMINER_BASIC_AUTH=admin:$$apr1$$HASH_AQUI
```

---


## DNS

Configure os registros A no seu provedor:

| Hostname | Tipo | Valor |
|---|---|---|
| `takadatintas.com.br` | A | `IP_DO_SERVIDOR` |
| `www.takadatintas.com.br` | A | `IP_DO_SERVIDOR` |
| `db.takadatintas.com.br` | A | `IP_DO_SERVIDOR` |

---

## Deploy

### 1. Traefik + MySQL + Adminer

```bash
env $(cat .env | grep -v '^#' | xargs) \
  docker stack deploy \
  --compose-file traefik-stack.yml \
  --with-registry-auth \
  traefik-stack
```

### 2. WordPress (Nginx + PHP-FPM)

```bash
env $(cat .env | grep -v '^#' | xargs) \
  docker stack deploy \
  --compose-file wordpress-stack.yml \
  --with-registry-auth \
  wordpress-stack
```

> **Ordem importa:** o `traefik-stack` deve estar running antes de subir o `wordpress-stack` (redes externas precisam existir).

---

## Verificação

### Status dos stacks

```bash
docker stack ls
docker stack services traefik-stack
docker stack services wordpress-stack
```

Saída esperada (todos com `1/1`):

```
ID    NAME                             MODE         REPLICAS
xxxx  traefik-stack_traefik            replicated   1/1
xxxx  traefik-stack_mysql              replicated   1/1
xxxx  traefik-stack_adminer            replicated   1/1
xxxx  wordpress-stack_nginx            replicated   1/1
xxxx  wordpress-stack_wpphpfpm         replicated   1/1
```

### Logs

```bash
docker service logs -f traefik-stack_traefik
docker service logs -f wordpress-stack_nginx
docker service logs -f wordpress-stack_wpphpfpm
```

---

## Acessar o Adminer

- **URL:** `https://db.takadatintas.com.br`
- Credenciais HTTP: as configuradas em `ADMINER_BASIC_AUTH`

| Campo | Valor |
|---|---|
| Sistema | MySQL |
| Servidor | `mysql` |
| Usuário | valor de `MYSQL_USER` |
| Senha | valor de `MYSQL_PASSWORD` |
| Banco | valor de `MYSQL_USER` |

---

## Usar WP-CLI no Swarm

```bash
# Encontrar o container do phpfpm em execução
docker exec -it $(docker ps -qf "name=wordpress-stack_wpphpfpm") bash

# Ou rodar um comando direto
docker exec -it $(docker ps -qf "name=wordpress-stack_wpphpfpm") wp plugin list
docker exec -it $(docker ps -qf "name=wordpress-stack_wpphpfpm") wp core version
```

---

## Atualizar os stacks (redeploy)

```bash
# Ambos os stacks
env $(cat .env | grep -v '^#' | xargs) \
  docker stack deploy --compose-file traefik-stack.yml --with-registry-auth traefik-stack

env $(cat .env | grep -v '^#' | xargs) \
  docker stack deploy --compose-file wordpress-stack.yml --with-registry-auth wordpress-stack
```

> O Swarm faz rolling update automático. Para atualizar configs nginx (arquivos `.conf`), o redeploy já recria os Docker Configs automaticamente.

---

## Remover os stacks

```bash
docker stack rm wordpress-stack
docker stack rm traefik-stack
```

> ⚠️ Volumes **não** são removidos. Os dados do MySQL e WordPress permanecem nos paths de bind mount.

---

## Atalhos Rápidos (Makefile)

O projeto possui um `Makefile` com comandos simplificados para facilitar a administração das stacks no dia a dia (evitando ter que carregar variáveis `.env` ou digitar comandos longos do Swarm manualmente):

### Implantação (Deploy)
*   **Subir ambas as stacks** (traefik-stack e wordpress-stack):
    ```bash
    make deploy
    ```
*   **Subir apenas a stack do Traefik, MariaDB e Adminer**:
    ```bash
    make deploy-traefik
    ```
*   **Subir apenas a stack do WordPress e Nginx**:
    ```bash
    make deploy-wordpress
    ```

### Monitoramento de Status e Logs
*   **Status de todos os serviços das stacks**:
    ```bash
    make status
    ```
*   **Logs do Nginx**:
    ```bash
    make logs-nginx
    ```
*   **Logs do PHP-FPM**:
    ```bash
    make logs-phpfpm
    ```
*   **Logs do MySQL/MariaDB**:
    ```bash
    make logs-mysql
    ```

### Executar Comandos e WP-CLI
*   **Shell interativo (bash) no container PHP-FPM ativo**:
    ```bash
    make shell
    ```
*   **Executar comandos WP-CLI** (especifique o comando usando `CMD="..."`):
    ```bash
    make wp CMD="plugin list"
    make wp CMD="core update"
    ```

### Remoção
*   **Remover ambas as stacks**:
    ```bash
    make down
    ```

---

## Estrutura do projeto

```
stack-wordpress-php/
├── .env                              # Variáveis de ambiente (não commitar!)
├── traefik-stack.yml                 # Stack: Traefik + MySQL + Adminer
├── wordpress-stack.yml               # Stack: Nginx + PHP-FPM (WordPress)
├── DEPLOY.md                         # Este arquivo
├── wp-cli.yml                        # Instruções WP-CLI para Swarm
├── config/
│   └── nginx/
│       ├── templates/
│       │   └── default.conf.template # Template nginx (${NGINX_HOST})
│       └── server.conf               # Configurações PHP-FPM fastcgi
└── system/                           # Arquivos WordPress (montado em /srv/sites/...)
```
