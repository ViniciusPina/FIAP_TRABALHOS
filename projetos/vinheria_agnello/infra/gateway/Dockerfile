# syntax=docker/dockerfile:1
# Gateway TLS da Vinheria Agnello. A configuracao vai DENTRO da imagem
# (artefato imutavel) - isso tambem permite o deploy pelo Jenkins via
# Docker-out-of-Docker, onde bind mounts de arquivos do workspace nao funcionam.
FROM nginx:1.30-alpine
# Aplica correcoes de seguranca publicadas depois da imagem base
RUN apk upgrade --no-cache

LABEL org.opencontainers.image.title="vinheria-gateway" \
      org.opencontainers.image.description="Nginx reverse proxy com TLS 1.2/1.3, HSTS e mTLS para os servicos"

COPY nginx.conf /etc/nginx/nginx.conf
COPY comum.conf /etc/nginx/comum.conf
COPY templates/ /etc/nginx/templates/
COPY templates-inseguro/ /etc/nginx/templates-inseguro/

# Shift-left: valida as duas variantes com um certificado descartavel.
RUN apk add --no-cache --virtual .build openssl \
 && mkdir -p /run/pki \
 && openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:P-256 -days 1 \
        -subj "/CN=build" -keyout /run/pki/tls.key -out /run/pki/tls.crt 2>/dev/null \
 && cp /run/pki/tls.crt /run/pki/ca.crt \
 && HTTPS_PORTA_PUBLICA=8443 envsubst '$HTTPS_PORTA_PUBLICA' \
        < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf \
 && nginx -t \
 && cp /etc/nginx/templates-inseguro/default.conf.template /etc/nginx/conf.d/default.conf \
 && nginx -t \
 && rm -rf /run/pki /etc/nginx/conf.d/default.conf \
 && apk del .build

HEALTHCHECK --interval=5s --timeout=3s --retries=10 \
  CMD wget -qO- http://127.0.0.1/health | grep -q ok
