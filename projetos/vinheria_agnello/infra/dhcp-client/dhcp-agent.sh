#!/bin/sh
# Agente DHCP: obtem (e renova) o IP do host via DHCP, enviando o hostname
# (opcao 12) e o FQDN (opcao 81) para que o servidor registre o nome no DNS.
# Ao parar (SIGTERM), libera a concessao (-R) e o DNS e desregistrado.
set -eu

IFACE="${DHCP_INTERFACE:-eth0}"
HOST="${DHCP_HOSTNAME:-$(hostname -s)}"
export DHCP_HOSTNAME="$HOST"

# Aguarda a interface do container principal existir (sidecar sobe junto)
i=0
until ip link show "$IFACE" >/dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -gt 30 ] && { echo "interface $IFACE nao encontrada" >&2; exit 1; }
    sleep 1
done

mac=$(cat "/sys/class/net/$IFACE/address")
echo "[dhcp-agent] interface=$IFACE mac=$mac hostname=$HOST - solicitando concessao..."

exec udhcpc -f -R -B \
    -i "$IFACE" \
    -s /usr/local/bin/udhcpc-hook \
    -x "hostname:$HOST" \
    -F "$HOST" \
    -V "${DHCP_VENDOR_CLASS:-vinheria-agnello}" \
    -O search -O domain -O dns -O router \
    -t 10 -T 3 -A 5
