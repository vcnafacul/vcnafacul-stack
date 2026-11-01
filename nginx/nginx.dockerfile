FROM nginx:stable

# certbot fica na imagem para EMITIR certificado de domínio novo e para o cron
# de renovação (scripts/instalar-cron-renovacao.sh). No dia a dia o default.conf
# já vem com os blocos de SSL e os certificados vêm do volume /etc/letsencrypt.
RUN apt-get update \
    && apt-get install -y --no-install-recommends certbot python3-certbot-nginx \
    && rm -rf /var/lib/apt/lists/*

# homol usa default.conf; prod passa CONF=prod.conf (docker-compose.prod.yml)
ARG CONF=default.conf
COPY ${CONF} /etc/nginx/conf.d/default.conf
COPY gzip.conf /etc/nginx/conf.d/gzip.conf

EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]
