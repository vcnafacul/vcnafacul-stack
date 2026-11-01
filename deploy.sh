#!/usr/bin/env bash
# deploy.sh — sobe UM serviço do stack, sem mexer nos outros (tickets/056 e 057).
#
#   ./deploy.sh <serviço> [tag]      tag padrão: latest (homol) | stable (prod)
#   ./deploy.sh rollback <serviço>   volta para a tag anterior desse serviço
#   ./deploy.sh status               serviços, tags em uso e saúde
#
# Serviços: api ms-simulado form ms-omr nginx + redis mailpit (homol) | valkey (prod)
#
# O ambiente vem de .ambiente (homol | prod), um arquivo por servidor, fora do
# git — sem ele o script recusa, para nunca usar o compose de um no outro.
# O CI chama `~/stack/deploy.sh <serviço> <sha | versão>` por SSH. As tags
# ficam em .tags.env (uma linha por app) e o histórico em .tags.history — os
# dois fora do git.
set -euo pipefail

cd "$(dirname "$0")"

erro() { echo "❌ $*" >&2; exit 1; }
info() { echo "→ $*"; }

[ -f .ambiente ] || erro "defina o ambiente deste servidor: echo homol > $(pwd)/.ambiente  (ou prod)"
AMBIENTE=$(tr -d '[:space:]' <.ambiente)
case "$AMBIENTE" in
  homol) ARQUIVO_PADRAO=docker-compose.homol.yml TAG_PADRAO=latest ;;
  prod) ARQUIVO_PADRAO=docker-compose.prod.yml TAG_PADRAO=stable ;;
  *) erro ".ambiente com valor inválido: '$AMBIENTE' (use homol ou prod)" ;;
esac

PROJETO=vcnafacul
ARQUIVO=${ARQUIVO:-$ARQUIVO_PADRAO}  # outro arquivo só para teste local
TAGS=.tags.env
HISTORICO=.tags.history
ESPERA_SAUDE=${ESPERA_SAUDE:-120}   # segundos até o serviço ficar healthy

touch "$TAGS" "$HISTORICO"

# Um deploy por vez no servidor: merges em vários repos disparam deploys
# simultâneos, e o `docker image prune` do fim de um apagava camadas que outro
# ainda estava baixando ("lease does not exist"). O lock espera a vez (até 15 min).
exec 9>.deploy.lock
if command -v flock >/dev/null 2>&1; then
  info "aguardando outro deploy terminar (se houver)"
  flock -w 900 9 || erro "outro deploy segurou o lock por mais de 15 min"
fi
compose() { docker compose -p "$PROJETO" --env-file "$TAGS" -f "$ARQUIVO" "$@"; }

# serviço → variável da tag no compose (vazio = imagem fixa no compose ou build)
variavel_da_tag() {
  case "$1" in
    api) echo API_TAG ;;
    ms-simulado) echo MS_TAG ;;
    form) echo FORM_TAG ;;
    ms-omr) echo OMR_TAG ;;
    redis | mailpit | valkey | nginx) echo "" ;;
    *) erro "serviço desconhecido: $1 (use: api ms-simulado form ms-omr nginx redis mailpit valkey)" ;;
  esac
}

# serviço → nome do container dos subir_*.sh antigos (transição)
container_antigo() {
  case "$1" in
    api) echo vcnafacul ;;
    ms-simulado) echo "vcnafacul_simulado_$AMBIENTE" ;;
    form) echo vcnafacul_form ;;
    ms-omr) echo vcnafacul_ms_omr ;;
    redis) echo vcnafacul_redis ;;
    mailpit) echo mailpit ;;
    valkey) echo valkey ;;
    nginx) echo nginx_vcnafacul ;;
  esac
}

tag_atual() {
  local var=$1
  grep -E "^${var}=" "$TAGS" | tail -1 | cut -d= -f2- || true
}

gravar_tag() {
  local var=$1 tag=$2 servico=$3
  if grep -qE "^${var}=" "$TAGS"; then
    sed -i.bak -E "s|^${var}=.*|${var}=${tag}|" "$TAGS" && rm -f "$TAGS.bak"
  else
    echo "${var}=${tag}" >>"$TAGS"
  fi
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) ${servico} ${tag}" >>"$HISTORICO"
}

# Durante a transição o container antigo (do subir_*.sh) ainda pode existir com o
# mesmo nome que o alias do compose: os dois responderiam pelo mesmo nome na rede.
conferir_transicao() {
  local antigo
  antigo=$(container_antigo "$1")
  # --type container: sem ele o inspect também acha IMAGEM com esse nome (a do
  # nginx antigo chama nginx_vcnafacul) e a trava recusa sem container nenhum.
  if docker inspect --type container "$antigo" >/dev/null 2>&1; then
    local projeto
    projeto=$(docker inspect --type container -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$antigo" 2>/dev/null || true)
    if [ "$projeto" != "$PROJETO" ]; then
      erro "o container antigo '$antigo' (subir_*.sh) ainda existe. Na troca: docker rm -f $antigo   (plano B: ~/subir_*.sh)"
    fi
  fi
}

esperar_saude() {
  local servico=$1 id estado inicio
  id=$(compose ps -q "$servico")
  [ -n "$id" ] || erro "$servico não subiu"
  inicio=$(date +%s)
  while :; do
    estado=$(docker inspect -f '{{ if .State.Health }}{{ .State.Health.Status }}{{ else }}{{ .State.Status }}{{ end }}' "$id")
    case "$estado" in
      healthy | running) info "$servico: $estado"; return 0 ;;
      unhealthy | exited | dead) break ;;
    esac
    if [ $(($(date +%s) - inicio)) -ge "$ESPERA_SAUDE" ]; then break; fi
    sleep 3
  done
  echo "❌ $servico: $estado depois de $(($(date +%s) - inicio))s — últimas linhas do log:" >&2
  compose logs --tail=50 "$servico" >&2 || true
  echo "   para voltar: ./deploy.sh rollback $servico" >&2
  exit 1
}

deploy() {
  local servico=$1 tag=${2:-$TAG_PADRAO} var
  var=$(variavel_da_tag "$servico")

  if [ "${DEPLOY_SEM_PULL:-0}" != 1 ] && [ -d .git ]; then
    info "atualizando o stack (git pull)"
    git pull --ff-only -q
  fi

  conferir_transicao "$servico"

  # A tag nova vale para este comando pela variável de ambiente (vence o
  # .tags.env); só é gravada depois que a migration passar.
  if [ -n "$var" ]; then
    export "$var=$tag"
    info "$servico → ${var}=${tag} (antes: $(tag_atual "$var" || true))"
  fi

  if [ "$servico" = nginx ]; then
    compose build nginx
  else
    compose pull "$servico"
  fi

  if [ "$servico" = api ]; then
    info "migrations (api-migrate) antes de trocar a api"
    compose --profile migrate run --rm api-migrate || erro "migration falhou — a api antiga continua no ar, nada foi trocado"
  fi

  [ -n "$var" ] && gravar_tag "$var" "$tag" "$servico"

  compose up -d --no-deps "$servico"
  esperar_saude "$servico"

  # imagens sem uso há mais de 14 dias (as tags recentes ficam para rollback)
  docker image prune -af --filter "until=336h" >/dev/null || true
  info "✅ $servico no ar"
}

rollback() {
  local servico=${1:?uso: ./deploy.sh rollback <serviço>} var anterior
  var=$(variavel_da_tag "$servico")
  [ -n "$var" ] || erro "$servico não tem tag (imagem fixa no compose ou build)"
  # penúltima entrada desse serviço no histórico
  anterior=$(awk -v s="$servico" '$2 == s { print $3 }' "$HISTORICO" | tail -2 | head -1)
  local atual
  atual=$(tag_atual "$var")
  [ -n "$anterior" ] && [ "$anterior" != "$atual" ] || erro "sem tag anterior para $servico no $HISTORICO"
  info "rollback de $servico: $atual → $anterior"
  DEPLOY_SEM_PULL=1 deploy "$servico" "$anterior"
}

status() {
  echo "ambiente: $AMBIENTE ($ARQUIVO)"
  compose ps -a --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'
  echo
  echo "tags (.tags.env):"
  sed 's/^/  /' "$TAGS"
}

case "${1:-}" in
  "" | -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
  rollback) rollback "${2:-}" ;;
  status) status ;;
  *) deploy "$1" "${2:-$TAG_PADRAO}" ;;
esac
