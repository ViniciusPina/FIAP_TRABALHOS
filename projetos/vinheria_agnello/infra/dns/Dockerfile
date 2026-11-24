# syntax=docker/dockerfile:1
# DNS autoritativo interno da Vinheria Agnello (BIND 9.18 LTS)
FROM alpine:3.21
# Aplica correcoes de seguranca publicadas depois da imagem base
RUN apk upgrade --no-cache

LABEL org.opencontainers.image.title="vinheria-dns" \
      org.opencontainers.image.description="BIND 9 autoritativo para vinheria.local com DNS dinamico (RFC 2136 + TSIG)"

RUN apk add --no-cache bind=~9.18 bind-tools=~9.18

COPY named.conf /etc/bind/named.conf
COPY zones/ /etc/bind/zones/
COPY entrypoint.sh /usr/local/bin/dns-entrypoint
COPY registros.sh /usr/local/bin/dns-registros

# Shift-left: a imagem NAO e gerada se a configuracao ou as zonas tiverem erro.
RUN chmod 0755 /usr/local/bin/dns-entrypoint /usr/local/bin/dns-registros \
 && mkdir -p /run/named \
 && printf 'key "ddns-key" { algorithm hmac-sha256; secret "%s"; };\n' "$(head -c 32 /dev/urandom | base64)" > /run/named/ddns.key \
 && named-checkconf /etc/bind/named.conf \
 && named-checkzone vinheria.local /etc/bind/zones/db.vinheria.local \
 && named-checkzone 0.50.10.in-addr.arpa /etc/bind/zones/db.10.50.0 \
 && rm -f /run/named/ddns.key

EXPOSE 53/udp 53/tcp

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=10 \
  CMD dig +short +time=1 +tries=1 @127.0.0.1 ns1.vinheria.local A | grep -qx 10.50.0.2

ENTRYPOINT ["/usr/local/bin/dns-entrypoint"]
