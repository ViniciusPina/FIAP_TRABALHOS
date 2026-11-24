# syntax=docker/dockerfile:1
# Job de bootstrap: gera CA interna, certificados TLS, chaves JWT e TSIG.
FROM alpine:3.21
# Aplica correcoes de seguranca publicadas depois da imagem base
RUN apk upgrade --no-cache
RUN apk add --no-cache openssl
COPY gerar-pki.sh /usr/local/bin/gerar-pki
RUN chmod 0755 /usr/local/bin/gerar-pki
ENTRYPOINT ["/usr/local/bin/gerar-pki"]
