# syntax=docker/dockerfile:1
# Servidor DHCP da Vinheria Agnello (ISC Kea 2.6: DHCPv4 + D2/DDNS)
FROM alpine:3.21
# Aplica correcoes de seguranca publicadas depois da imagem base
RUN apk upgrade --no-cache

LABEL org.opencontainers.image.title="vinheria-dhcp" \
      org.opencontainers.image.description="ISC Kea DHCPv4 com reservas e DNS dinamico (D2)"

RUN apk add --no-cache \
        kea-dhcp4=~2.6 kea-dhcp-ddns=~2.6 kea-hook-lease-cmds=~2.6 \
        socat jq util-linux-misc

COPY kea-dhcp4.conf /etc/kea/kea-dhcp4.conf
COPY kea-dhcp-ddns.conf.tpl /etc/kea/kea-dhcp-ddns.conf.tpl
COPY entrypoint.sh /usr/local/bin/kea-entrypoint
COPY kea-leases.sh /usr/local/bin/kea-leases

# Shift-left: valida as duas configuracoes durante o build da imagem.
# O processo roda como root, mas SEM DAC_OVERRIDE (cap_drop ALL no compose):
# o diretorio de leases precisa pertencer ao proprio root.
RUN chmod 0755 /usr/local/bin/kea-entrypoint /usr/local/bin/kea-leases \
 && mkdir -p /var/lib/kea && chown root:root /var/lib/kea && chmod 0700 /var/lib/kea \
 && kea-dhcp4 -t /etc/kea/kea-dhcp4.conf \
 && sed "s|__TSIG_SECRET__|$(head -c 32 /dev/urandom | base64)|" /etc/kea/kea-dhcp-ddns.conf.tpl > /tmp/d2.conf \
 && kea-dhcp-ddns -t /tmp/d2.conf \
 && rm -f /tmp/d2.conf

EXPOSE 67/udp

ENTRYPOINT ["/usr/local/bin/kea-entrypoint"]
CMD ["dhcp4"]
