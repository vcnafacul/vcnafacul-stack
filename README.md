# vcnafacul-stack

Sobe o Você na Facul inteiro em docker compose: **api, ms-simulado, ms-omr, vcnafacul-form e client**, cada um
lendo o `.env` do próprio repositório, com hot reload. Origem: `tickets/055`.

## Dois modos

| | `make up` — **local** | `make up-homol` — **homol** |
|---|---|---|
| Apps | containers, hot reload | containers, hot reload |
| MySQL, Mongo, bucket | **containers locais** (MySQL 8.0, Mongo 8 rs0, MinIO) | **os do `.env` de cada repo** |
| Migrations | `api-migrate` (MySQL) e `yarn migracoes` (Mongo) rodam no `up` | **nunca** — homol migra pelo deploy |
| Redis, Mailpit | locais | locais |
| E-mail | Mailpit | Mailpit (nenhum e-mail sai de verdade) |
| Para quê | testar sem medo, migration nova, dados de exemplo | testar com os dados de homol |

⚠️ No modo homol **tudo o que você fizer escreve em homol** (como rodar com o `.env` no host hoje).

Os dois modos não rodam juntos (mesmas portas). Cada um é um projeto do compose (`vcnafacul-local` /
`vcnafacul-homol`): trocar de modo derruba o outro sem apagar os dados.

## Pré-requisitos

- Docker com compose v2 e **pelo menos 4 CPUs / 8 GB** para a VM (Colima: `colima start --cpu 4 --memory 8`).
- Os repos clonados lado a lado:
  ```
  pasta/
  ├── api-vcnafacul/   ├── ms-simulado/   ├── ms-omr/
  ├── vcnafacul-form/  ├── client-vcnafacul/
  └── vcnafacul-stack/   ← este
  ```
- Um `.env` em cada repo (`cp .env.example .env`) e o `.env.compose` aqui (`cp .env.compose.example .env.compose`).

## Uso

```bash
make up            # modo local (1º run demora: instala dependências e builda o ms-omr)
make up-homol      # modo homol
make infra         # só MySQL, Mongo, MinIO, Redis, Mailpit — para rodar os apps no host
make ps            # status
make logs s=api    # logs de um serviço (sem s= : todos)
make migrate       # modo local: migrations da api de novo
make seed-mongo    # modo local: clona o Mongo de SOURCE_MONGODB (ms-simulado/.env) para o banco simulado
make down          # derruba o modo atual (dados ficam)
make down-v        # modo local: derruba e apaga MySQL, Mongo, MinIO e Mailpit
make urls
```

Um serviço só, sem mexer nos outros:

```bash
make stop s=ms-simulado
make start s=ms-simulado     # up -d --no-deps: não reroda mongo-init/api-migrate
make restart s=form
```

## Portas

| Serviço | Endereço |
|---|---|
| client | http://localhost:5173 |
| api | http://localhost:3333 (swagger em `/api`) |
| ms-simulado | http://localhost:3000 |
| form | http://localhost:3334 |
| ms-omr | http://localhost:8000/health |
| Mailpit | http://localhost:8025 (SMTP 1025) |
| MinIO (local) | http://localhost:9001 — `minioadmin` / `minioadmin123` |
| MySQL (local) | `localhost:3306` — `root` / `123456`, banco `vcnafacul` |
| Mongo (local) | `mongodb://localhost:27017/?directConnection=true` — bancos `simulado` e `form` |
| Redis | `localhost:6379` |

## Como as variáveis se combinam

Do mais fraco para o mais forte:

1. `env_file`: o `.env` do repo (segredos, chaves, config);
2. `docker-compose.yml`, nos dois modos: endereços entre serviços (`SIMULADO_URL=http://ms-simulado:3000`,
   `FORMULARIO_URL`, `OMR_URL`, `API_URL`, `CALLBACK_URL`, `REDIS_*`), Mailpit (`USE_SMTP_FAKE=true`) e os
   segredos compartilhados do `.env.compose` (`ADMIN_FORM_SECRET`, `NOTIFICACAO_SECRET`);
3. `docker-compose.dados-locais.yml`, só no modo local: `MY_*` → `mysql`, `MONGODB` → `mongo`,
   `AWS_*`/`BUCKET_*` → MinIO.

**Travas:**
- `make up` roda `scripts/conferir-modo-local.py` na config final e **recusa** se algum app apontar para um
  banco ou bucket fora dos containers. O `api-vcnafacul/.env` real aponta para um MySQL remoto: é isso que a
  trava pega se o override sumir.
- `make up-homol` roda `scripts/conferir-modo-homol.py` e recusa se algum `.env` tiver banco/bucket em
  `localhost`, porque dentro do container esse endereço é o próprio container.

## Limitações conhecidas

- **MinIO**: o `minio/minio` saiu do Docker Hub (set/2026). Usamos o fork `pgsty/silo`, compatível, com tag fixa.
- **Arquivos no modo local**: um link pré-assinado gerado pela api aponta para `http://minio:9000`, que o
  navegador não resolve. Upload e leitura feitos pela própria api funcionam.
- **Questões clonadas** com `make seed-mongo` apontam para imagens no R2 de homol, que não estão no MinIO.
- O banco local começa **vazio**: para logar, crie um admin (`yarn create-admin-user` no container da api).
  O seed completo é o card 055/04.
- `node_modules` de cada app fica num volume (`vcnafacul-stack_*_node_modules`), compartilhado entre os modos.
  Dependência nova no `package.json` → `make restart s=<app>` (o `yarn install` roda no início do comando).
