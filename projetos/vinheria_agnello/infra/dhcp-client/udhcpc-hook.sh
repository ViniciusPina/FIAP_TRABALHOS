#!/bin/sh
# Hook do udhcpc (cliente DHCP do BusyBox). Chamado com $1 = evento:
#   deconfig | bound | renew | leasefail | nak
# Variaveis entregues pelo udhcpc: interface ip mask router dns domain search
#                                  lease serverid hostname
#
# Diferente do script padrao, este hook NAO derruba a interface: ela pertence
# ao container da aplicacao (o agente roda como sidecar no mesmo namespace).
# shellcheck disable=SC2154  # interface/ip/mask/serverid sao exportadas pelo udhcpc
set -u

STATE_DIR=/run/dhcp
LEASE_FILE="$STATE_DIR/lease.env"
mkdir -p "$STATE_DIR"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [dhcp-agent:${DHCP_HOSTNAME:-?}] $*"; }

lease_anterior() {
    LEASE_IP=""; LEASE_MASK=""
    # shellcheck disable=SC1090
    [ -f "$LEASE_FILE" ] && . "$LEASE_FILE"
}

case "$1" in
    deconfig)
        lease_anterior
        if [ -n "$LEASE_IP" ]; then
            ip addr del "$LEASE_IP/$LEASE_MASK" dev "$interface" 2>/dev/null || true
            log "deconfig: IP $LEASE_IP/$LEASE_MASK removido"
        fi
        rm -f "$LEASE_FILE"
        ;;

    bound|renew)
        lease_anterior
        if [ -n "$LEASE_IP" ] && [ "$LEASE_IP" != "$ip" ]; then
            ip addr del "$LEASE_IP/$LEASE_MASK" dev "$interface" 2>/dev/null || true
        fi
        # Remove o IP provisorio atribuido pelo Docker (IPAM): a partir daqui o
        # host passa a existir na rede SOMENTE com o endereco entregue pelo DHCP.
        # A remocao vem ANTES de aplicar o lease: no Linux, apagar o endereco
        # primario de uma sub-rede apaga junto os secundarios (promote_secondaries=0).
        if [ "${DHCP_REMOVE_BOOTSTRAP_IP:-true}" = "true" ]; then
            for cidr in $(ip -4 -o addr show dev "$interface" | awk '{print $4}'); do
                if [ "$cidr" != "$ip/$mask" ]; then
                    ip addr del "$cidr" dev "$interface" && log "IP de bootstrap do Docker $cidr removido"
                fi
            done
        fi
        ip addr replace "$ip/$mask" dev "$interface" valid_lft "${lease:-forever}" preferred_lft "${lease:-forever}"
        if [ -n "${router:-}" ] && [ "${DHCP_APLICAR_ROTA:-false}" = "true" ]; then
            ip route replace default via "${router%% *}" dev "$interface"
        fi

        # Estacoes (PDV) aplicam o DNS recebido por DHCP no proprio resolver.
        if [ "${DHCP_WRITE_RESOLV:-false}" = "true" ]; then
            {
                echo "# gerado pelo cliente DHCP em $(date -Iseconds) - servidor $serverid"
                if [ -n "${search:-}" ]; then echo "search $search"
                elif [ -n "${domain:-}" ]; then echo "search $domain"; fi
                for d in ${dns:-}; do echo "nameserver $d"; done
            } > /etc/resolv.conf
        fi

        cat > "$LEASE_FILE" <<EOF
LEASE_EVENTO='$1'
LEASE_IP='$ip'
LEASE_MASK='$mask'
LEASE_ROTEADOR='${router:-}'
LEASE_DNS='${dns:-}'
LEASE_DOMINIO='${domain:-}'
LEASE_BUSCA='${search:-}'
LEASE_TEMPO='${lease:-}'
LEASE_SERVIDOR='${serverid:-}'
LEASE_HOSTNAME='${DHCP_HOSTNAME:-}'
LEASE_OBTIDO_EM='$(date -Iseconds)'
EOF
        log "$1: ip=$ip/$mask gateway=${router:-} dns=${dns:-} dominio=${domain:-} lease=${lease:-}s servidor=${serverid:-}"
        ;;

    leasefail|nak)
        log "$1: ${message:-sem resposta do servidor DHCP}"
        ;;
esac
exit 0
