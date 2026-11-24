# syntax=docker/dockerfile:1
# Sniffer para a demonstracao da Parte 3 (gera .pcap que abre no Wireshark).
FROM alpine:3.21
# Aplica correcoes de seguranca publicadas depois da imagem base
RUN apk upgrade --no-cache
RUN apk add --no-cache tcpdump
ENTRYPOINT ["tcpdump"]
