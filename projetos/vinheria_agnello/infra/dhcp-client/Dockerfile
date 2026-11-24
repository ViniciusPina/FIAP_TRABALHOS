# syntax=docker/dockerfile:1
# Cliente DHCP da Vinheria Agnello.
#  - Sidecar dos microsservicos: compartilha o namespace de rede do servico e
#    concede a ele o IP reservado (o servico em si roda sem privilegios).
#  - Estacao PDV: obtem IP do pool dinamico e aplica o DNS recebido por DHCP.
FROM alpine:3.21
# Aplica correcoes de seguranca publicadas depois da imagem base
RUN apk upgrade --no-cache

LABEL org.opencontainers.image.title="vinheria-dhcp-client" \
      org.opencontainers.image.description="Agente DHCP (udhcpc) com registro de nome via opcao 81"

RUN apk add --no-cache iproute2 bind-tools curl jq openssl

COPY dhcp-agent.sh /usr/local/bin/dhcp-agent
COPY udhcpc-hook.sh /usr/local/bin/udhcpc-hook
RUN chmod 0755 /usr/local/bin/dhcp-agent /usr/local/bin/udhcpc-hook

HEALTHCHECK --interval=3s --timeout=2s --start-period=5s --retries=20 \
  CMD test -s /run/dhcp/lease.env

ENTRYPOINT ["/usr/local/bin/dhcp-agent"]
