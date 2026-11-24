#!/bin/sh
# Entrypoint unico da imagem Kea. Papel escolhido pelo 1o argumento:
#   dhcp4 -> servidor DHCPv4
#   ddns  -> Kea D2 (atualizador de DNS), com o segredo TSIG injetado
set -eu

export KEA_PIDFILE_DIR=/run/kea KEA_LOCKFILE_DIR=/run/kea
mkdir -p /run/kea /var/lib/kea

papel="${1:-dhcp4}"
case "$papel" in
    dhcp4)
        kea-dhcp4 -t /etc/kea/kea-dhcp4.conf >/dev/null
        echo "[dhcp] configuracao valida - iniciando $(kea-dhcp4 -v)"
        exec kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
        ;;
    ddns)
        SECRET_FILE="${TSIG_SECRET_FILE:-/run/pki/tsig.secret}"
        if [ ! -s "$SECRET_FILE" ]; then
            echo "[ddns] ERRO: segredo TSIG nao encontrado em $SECRET_FILE" >&2
            exit 1
        fi
        umask 077
        sed "s|__TSIG_SECRET__|$(cat "$SECRET_FILE")|" /etc/kea/kea-dhcp-ddns.conf.tpl > /run/kea/kea-dhcp-ddns.conf
        kea-dhcp-ddns -t /run/kea/kea-dhcp-ddns.conf >/dev/null
        echo "[ddns] configuracao valida - iniciando $(kea-dhcp-ddns -v)"
        exec kea-dhcp-ddns -c /run/kea/kea-dhcp-ddns.conf
        ;;
    *)
        exec "$@"
        ;;
esac
