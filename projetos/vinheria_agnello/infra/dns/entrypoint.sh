#!/bin/sh
# Inicializa o BIND: injeta a chave TSIG (vinda do volume PKI) e prepara as
# zonas num diretorio PERSISTENTE (as atualizacoes dinamicas vivem nos .jnl).
set -eu

SECRET_FILE="${TSIG_SECRET_FILE:-/run/pki/tsig.secret}"

if [ ! -s "$SECRET_FILE" ]; then
    echo "[dns] ERRO: segredo TSIG nao encontrado em $SECRET_FILE (o pki-init rodou?)" >&2
    exit 1
fi

umask 027
mkdir -p /run/named /var/bind/dyn
printf 'key "ddns-key" {\n    algorithm hmac-sha256;\n    secret "%s";\n};\n' "$(cat "$SECRET_FILE")" > /run/named/ddns.key

# Zona so e (re)semeada quando o arquivo versionado no Git muda. Caso contrario
# o BIND reaproveita a zona + journal, preservando os registros vindos do DHCP.
for origem in /etc/bind/zones/db.*; do
    nome=$(basename "$origem")
    destino="/var/bind/dyn/$nome"
    hash_novo=$(sha256sum "$origem" | cut -d' ' -f1)
    hash_atual=$(cat "$destino.sha256" 2>/dev/null || true)
    if [ ! -f "$destino" ] || [ "$hash_novo" != "$hash_atual" ]; then
        cp "$origem" "$destino"
        rm -f "$destino.jnl"
        echo "$hash_novo" > "$destino.sha256"
        echo "[dns] zona $nome semeada a partir da configuracao versionada"
    else
        echo "[dns] zona $nome reaproveitada (registros dinamicos preservados)"
    fi
done

chown -R named:named /run/named /var/bind
chown root:named /run/named/ddns.key
chmod 0640 /run/named/ddns.key

named-checkconf /etc/bind/named.conf
echo "[dns] configuracao valida - iniciando $(named -v)"
exec named -f -u named -c /etc/bind/named.conf
