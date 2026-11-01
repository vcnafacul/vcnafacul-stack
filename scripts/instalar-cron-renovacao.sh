#!/usr/bin/env bash
# Instala (ou atualiza) no crontab do usuário deploy a renovação do certificado
# pelo nginx do compose. Substitui a entrada do ~/install_crontab_renew.sh antigo,
# que chamava o container pelo nome fixo (nginx_vcnafacul). Idempotente.
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
marcador="# certbot-renew-vcnafacul-stack"
marcador_antigo="# certbot-renew-nginx_vcnafacul"
linha="0 3 * * * cd $STACK_DIR && docker compose -p vcnafacul --env-file .tags.env -f docker-compose.homol.yml exec -T nginx certbot renew --quiet --deploy-hook 'nginx -s reload' $marcador"

atual="$(crontab -l 2>/dev/null || true)"
novo="$(printf '%s\n' "$atual" | grep -Fv "$marcador" | grep -Fv "$marcador_antigo" || true)"
printf '%s\n%s\n' "$novo" "$linha" | sed '/^$/d' | crontab -

echo '--- crontab atual ---'
crontab -l
