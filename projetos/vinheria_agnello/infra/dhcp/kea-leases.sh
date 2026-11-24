#!/bin/sh
# Mostra as concessoes (leases) ativas do Kea via API de controle.
# Uso: docker compose exec dhcp kea-leases          (tabela)
#      docker compose exec dhcp kea-leases --json   (JSON bruto)
set -eu
SOCK=/run/kea/kea4-ctrl-socket
resposta=$(printf '{"command":"lease4-get-all"}' | socat -t 2 - "UNIX-CONNECT:$SOCK")

if [ "${1:-}" = "--json" ]; then
    echo "$resposta" | jq .
    exit 0
fi
if [ "${1:-}" = "--ip" ]; then          # kea-leases --ip catalogo.vinheria.local.
    echo "$resposta" | jq -r --arg h "$2" '.arguments.leases[] | select(.hostname==$h) | .["ip-address"]'
    exit 0
fi

echo "$resposta" | jq -r '
  ["IP", "MAC", "HOSTNAME", "VALIDADE(s)", "DNS-DIRETO", "DNS-REVERSO"],
  (.arguments.leases // [] | sort_by(.["ip-address"]) | .[] |
    [ .["ip-address"], .["hw-address"], .hostname, (.["valid-lft"]|tostring),
      (.["fqdn-fwd"]|tostring), (.["fqdn-rev"]|tostring) ])
  | @tsv' | column -t
