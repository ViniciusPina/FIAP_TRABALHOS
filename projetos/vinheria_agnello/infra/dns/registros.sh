#!/bin/sh
# Lista TODOS os registros das zonas (estaticos + criados pelo DHCP).
# Uso: docker compose exec dns dns-registros
set -eu
for zona in vinheria.local 0.50.10.in-addr.arpa; do
    echo "===== zona $zona ====="
    dig +nocmd +nostats +nocomments @127.0.0.1 "$zona" AXFR | grep -v '^;' | sort -u -k4,4 -k1,1
    echo
done
