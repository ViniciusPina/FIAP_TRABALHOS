#!/usr/bin/env bash
# =============================================================================
# Gera as EVIDENCIAS para o PDF da entrega (cada arquivo = uma "captura de tela"
# de terminal, com o comando executado e a saida). Rode com o ambiente no ar.
#
# Uso: bash scripts/coletar-evidencias.sh      -> evidencias/AAAAMMDD-HHMMSS/
# =============================================================================
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

DESTINO="evidencias/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DESTINO"
CA="--cacert /run/pki/ca.crt"
API="https://api.vinheria.local"
CRED="${OPERADOR_USUARIO}:${OPERADOR_SENHA}"

# evidencia <arquivo> <titulo> <descricao do comando> <comando...>
evidencia() {
    local arquivo="$DESTINO/$1" titulo=$2 rotulo=$3; shift 3
    {
        echo "=============================================================================="
        echo " $titulo"
        echo " Gerado em: $(date '+%d/%m/%Y %H:%M:%S')"
        echo "=============================================================================="
        echo "\$ $rotulo"
        echo
        "$@" 2>&1 | tr -d '\r'
        echo
    } >> "$arquivo"
}

aguardar_saude 180 || exit 1
info "coletando evidencias em $DESTINO ..."

# ---------------------------------------------------------------- Parte 1
evidencia 01-containers.txt "Containers do ambiente (docker compose ps)" \
    "docker compose ps" "${COMPOSE[@]}" ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

evidencia 02-rede-docker.txt "Rede vinheria-lan (bridge 10.50.0.0/24, sem NAT)" \
    "docker network inspect vinheria-lan" \
    docker network inspect vinheria-lan --format '{{json .IPAM.Config}}{{"\n"}}Opcoes: {{json .Options}}{{"\n"}}Internal: {{.Internal}}'
evidencia 02-rede-docker.txt "IP REAL de cada host por interface (apos o DHCP o IP de bootstrap do Docker e removido)" \
    "ip -4 addr show  (em cada container)" \
    sh -c "for s in dns dhcp gateway catalogo-dhcp carrinho-dhcp estacao-pdv; do printf '%-14s ' \$s; ${COMPOSE[*]} exec -T \$s ip -4 -o addr show scope global | awk '{printf \"%s=%s  \", \$2, \$4} END {print \"\"}'; done"

evidencia 03-dhcp-configuracao.txt "Kea DHCPv4 - escopo, pool, reservas e opcoes" \
    "cat /etc/kea/kea-dhcp4.conf (trecho subnet4)" \
    no_servico dhcp "sed -n '/\"option-data\": \[/,/\"loggers\"/p' /etc/kea/kea-dhcp4.conf"

evidencia 04-dhcp-leases.txt "Concessoes (leases) ativas no Kea" \
    "docker compose exec dhcp kea-leases" no_servico dhcp "kea-leases"
evidencia 04-dhcp-leases.txt "Concessoes em JSON (API de controle do Kea: lease4-get-all)" \
    "docker compose exec dhcp kea-leases --json" no_servico dhcp "kea-leases --json"

evidencia 05-dhcp-logs.txt "Log do servidor DHCP: concessoes realizadas" \
    "docker compose logs dhcp | grep DHCP4_LEASE_ALLOC" \
    sh -c "${COMPOSE[*]} logs --no-color dhcp | grep -E 'DHCP4_LEASE_ALLOC|DHCP4_CONFIG_COMPLETE'"
evidencia 05-dhcp-logs.txt "Log dos clientes DHCP (DISCOVER -> OFFER -> REQUEST -> ACK)" \
    "docker compose logs catalogo-dhcp carrinho-dhcp estacao-pdv" \
    "${COMPOSE[@]}" logs --no-color catalogo-dhcp carrinho-dhcp estacao-pdv

evidencia 06-ddns.txt "Kea D2 enviando atualizacoes DNS (DDNS)" \
    "docker compose logs dhcp-ddns | grep DHCP_DDNS_ADD_SUCCEEDED" \
    sh -c "${COMPOSE[*]} logs --no-color dhcp-ddns | grep -E 'SUCCEEDED|FAILED'"
evidencia 06-ddns.txt "BIND recebendo as atualizacoes assinadas com TSIG" \
    "docker compose logs dns | grep 'update:'" \
    sh -c "${COMPOSE[*]} logs --no-color dns | grep 'update:' | grep -v 'query:'"

evidencia 07-dns-zona.txt "Zonas DNS completas (estatico + registrado pelo DHCP)" \
    "docker compose exec dns dns-registros" no_servico dns "dns-registros"

evidencia 08-dns-consultas.txt "Consultas a partir da estacao PDV" \
    "dig catalogo.vinheria.local / carrinho / -x / SRV" \
    pdv "for q in 'catalogo.vinheria.local A' 'carrinho.vinheria.local A' 'api.vinheria.local A' '_catalogo._tcp.vinheria.local SRV' '_catalogo._tcp.vinheria.local TXT'; do echo \"--- dig \$q\"; dig +noall +answer \$q; done; echo '--- dig -x 10.50.0.101'; dig +noall +answer -x 10.50.0.101"
evidencia 08-dns-consultas.txt "Resposta completa de uma consulta (cabecalho e flags)" \
    "dig catalogo.vinheria.local" pdv "dig catalogo.vinheria.local"
evidencia 08-dns-consultas.txt "resolv.conf da estacao - preenchido pelas opcoes do DHCP" \
    "cat /etc/resolv.conf" pdv "cat /etc/resolv.conf"

evidencia 09-comunicacao.txt "Catalogo via gateway HTTPS" \
    "curl $API/api/catalogo/produtos" pdv "curl -s $CA $API/api/catalogo/produtos | jq -c '.[] | {id,nome,tipo,preco,estoque}'"
evidencia 09-comunicacao.txt "Fluxo do carrinho: cria carrinho e adiciona item (carrinho -> catalogo)" \
    "POST /carrinhos ; POST /carrinhos/{id}/itens" \
    pdv "C=\$(curl -s $CA -u '$CRED' -X POST $API/api/carrinho/carrinhos | jq -r .id); echo carrinho=\$C; curl -s $CA -u '$CRED' -H 'Content-Type: application/json' -d '{\"produto_id\":3,\"quantidade\":2}' $API/api/carrinho/carrinhos/\$C/itens | jq ."
evidencia 09-comunicacao.txt "Como o carrinho encontrou o catalogo (DNS SRV + DDNS)" \
    "GET /diagnostico/descoberta" pdv "curl -s $CA -u '$CRED' $API/api/carrinho/diagnostico/descoberta | jq ."
evidencia 09-comunicacao.txt "Logs correlacionados pelo X-Request-ID (gateway -> carrinho -> catalogo)" \
    "docker compose logs gateway carrinho catalogo | tail" \
    sh -c "${COMPOSE[*]} logs --no-color --tail 6 gateway carrinho catalogo"

# ---------------------------------------------------------------- Parte 3
evidencia 10-seguranca.txt "Ataques simulados contra o catalogo (de dentro da rede, com mTLS)" \
    "docker compose exec carrinho python -m app.diagnostico" no_servico carrinho "python -m app.diagnostico todos"
evidencia 10-seguranca.txt "Handshake TLS no gateway (versao, cifra, cadeia)" \
    "curl -v https://api.vinheria.local/health" pdv "curl -sv -o /dev/null $CA $API/health 2>&1 | grep -E '^\* (SSL|TLS|Server certificate|  subject|  issuer|  expire|ALPN)'"
evidencia 10-seguranca.txt "Cabecalhos de seguranca" "curl -I https://api.vinheria.local/health" \
    pdv "curl -sI $CA $API/health"
evidencia 10-seguranca.txt "DDNS forjado (sem chave TSIG) e recusado pelo BIND" \
    "nsupdate (sem -k)" pdv "printf 'server 10.50.0.2\nzone vinheria.local\nupdate add invasor.vinheria.local 60 A 6.6.6.6\nsend\n' | nsupdate"

evidencia 11-smoke-test.txt "Smoke test automatizado" "bash scripts/smoke-test.sh" bash scripts/smoke-test.sh

info "pronto: $(find "$DESTINO" -type f | wc -l) arquivos em $DESTINO"
ls -1 "$DESTINO"
