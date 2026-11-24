#!/usr/bin/env bash
# =============================================================================
# Smoke test ponta a ponta do ambiente da Vinheria Agnello.
# Valida a Parte 1 (rede, DHCP, DNS, comunicacao) e controles da Parte 3.
# Tudo e executado DE DENTRO da rede (a partir da estacao PDV), portanto
# funciona igual no notebook, no GitHub Actions e no Jenkins.
#
# Uso: bash scripts/smoke-test.sh          -> relatorio em relatorios/smoke-test.xml
# =============================================================================
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

CA="--cacert /run/pki/ca.crt"
API="https://api.vinheria.local"
CRED="${OPERADOR_USUARIO}:${OPERADOR_SENHA}"
RELATORIO="relatorios/smoke-test.xml"
mkdir -p relatorios

total=0; falhas=0; casos=""
registrar() { # registrar <grupo> <descricao> <ok|falha> [detalhe]
    local grupo=$1 desc=$2 resultado=$3 detalhe=${4:-}
    total=$((total + 1))
    if [ "$resultado" = ok ]; then
        printf '  %s✔%s %s\n' "$VERDE" "$RESET" "$desc"
        casos+="<testcase classname=\"smoke.$grupo\" name=\"$desc\"/>"
    else
        falhas=$((falhas + 1))
        printf '  %s✘ %s%s  %s\n' "$VERMELHO" "$desc" "$RESET" "${detalhe:0:200}"
        detalhe=${detalhe//&/&amp;}; detalhe=${detalhe//</&lt;}; detalhe=${detalhe//\"/&quot;}
        casos+="<testcase classname=\"smoke.$grupo\" name=\"$desc\"><failure message=\"${detalhe:0:500}\"/></testcase>"
    fi
}
# igual <grupo> <descricao> <esperado> <comando...>
igual() {
    local grupo=$1 desc=$2 esperado=$3; shift 3
    local obtido; obtido=$("$@" 2>&1 | tr -d '\r' | sed -e 's/[[:space:]]*$//')
    if [ "$obtido" = "$esperado" ]; then registrar "$grupo" "$desc" ok
    else registrar "$grupo" "$desc" falha "esperado=[$esperado] obtido=[$obtido]"; fi
}
# contem <grupo> <descricao> <regex> <comando...>
contem() {
    local grupo=$1 desc=$2 padrao=$3; shift 3
    local obtido; obtido=$("$@" 2>&1 | tr -d '\r')
    if grep -Eq -- "$padrao" <<<"$obtido"; then registrar "$grupo" "$desc" ok
    else registrar "$grupo" "$desc" falha "padrao=[$padrao] obtido=[${obtido:0:300}]"; fi
}
http_status() { pdv "curl -s -o /dev/null -w '%{http_code}' $*"; }
ip_do_host() { no_servico "$1" "ip -4 -o addr show eth0 | awk '{print \$4}' | paste -sd' '"; }

aguardar_saude 180 || exit 1

# ----------------------------------------------------------------------------
titulo "1. Rede e enderecamento"
igual rede "catalogo-service possui SOMENTE o IP reservado no DHCP" "10.50.0.101/24" ip_do_host catalogo-dhcp
igual rede "carrinho-service possui SOMENTE o IP reservado no DHCP" "10.50.0.102/24" ip_do_host carrinho-dhcp
contem rede "estacao PDV recebeu IP do pool dinamico (.150-.199)" '^10\.50\.0\.1(5[0-9]|[6-9][0-9])/24$' ip_do_host estacao-pdv
igual rede "servicos internos NAO sao publicados no host (so o gateway)" "0" sh -c \
    "docker ps --filter label=com.docker.compose.project=vinheria --format '{{.Names}} {{.Ports}}' | grep -E 'catalogo|carrinho|dns|dhcp' | grep -c -- '->'"
contem rede "LAN sem NAT para a internet (masquerade desligado)" '"false"' \
    docker network inspect vinheria-lan --format '{{json (index .Options "com.docker.network.bridge.enable_ip_masquerade")}}'

# ----------------------------------------------------------------------------
titulo "2. DHCP (Kea)"
igual dhcp "lease ativo: catalogo.vinheria.local -> 10.50.0.101 (reserva por MAC)" "10.50.0.101" \
    no_servico dhcp "kea-leases --ip catalogo.vinheria.local."
igual dhcp "lease ativo: carrinho.vinheria.local -> 10.50.0.102 (reserva por MAC)" "10.50.0.102" \
    no_servico dhcp "kea-leases --ip carrinho.vinheria.local."
contem dhcp "DHCP entregou o servidor DNS ao PDV (opcao 6)" '^nameserver 10\.50\.0\.2$' pdv "cat /etc/resolv.conf"
contem dhcp "DHCP entregou o dominio de busca ao PDV (opcao 119)" '^search vinheria\.local$' pdv "cat /etc/resolv.conf"

# ----------------------------------------------------------------------------
titulo "3. DNS (BIND) e DNS dinamico"
igual dns "A     catalogo.vinheria.local (registrado pelo DHCP)" "10.50.0.101" pdv "dig +short catalogo.vinheria.local"
igual dns "A     carrinho.vinheria.local (registrado pelo DHCP)" "10.50.0.102" pdv "dig +short carrinho.vinheria.local"
igual dns "PTR   10.50.0.101 -> catalogo (reverso dinamico)" "catalogo.vinheria.local." pdv "dig +short -x 10.50.0.101"
igual dns "SRV   _catalogo._tcp (descoberta de servico)" "0 100 8443 catalogo.vinheria.local." pdv "dig +short SRV _catalogo._tcp.vinheria.local"
contem dns "CNAME api -> gateway" '^gateway\.vinheria\.local\.$' pdv "dig +short api.vinheria.local | head -1"
contem dns "nome curto resolve via dominio de busca do DHCP" '^10\.50\.0\.102$' pdv "getent hosts carrinho | awk '{print \$1}'"
contem dns "DNS nao e resolver aberto (recursao recusada)" 'status: REFUSED' pdv "dig @10.50.0.2 www.google.com"
contem dns "atualizacao dinamica SEM chave TSIG e recusada" 'REFUSED' \
    pdv "printf 'server 10.50.0.2\nzone vinheria.local\nupdate add invasor.vinheria.local 60 A 6.6.6.6\nsend\n' | nsupdate 2>&1"
igual dns "registro forjado NAO entrou na zona" "" pdv "dig +short invasor.vinheria.local"

# ----------------------------------------------------------------------------
titulo "4. Comunicacao entre os microsservicos"
contem com "catalogo via gateway HTTPS lista os 6 vinhos" '^6$' pdv "curl -sf $CA $API/api/catalogo/produtos | jq length"
ESTOQUE_ANTES=$(pdv "curl -sf $CA $API/api/catalogo/produtos/4 | jq .estoque")
CARRINHO=$(pdv "curl -sf $CA -u '$CRED' -X POST $API/api/carrinho/carrinhos | jq -r .id")
contem com "operador autenticado cria carrinho" '^[0-9a-f]{12}$' echo "$CARRINHO"
contem com "carrinho -> catalogo: adiciona 2x Malbec (consulta + reserva com JWT)" '^190(\.0)?$' \
    pdv "curl -sf $CA -u '$CRED' -H 'Content-Type: application/json' -d '{\"produto_id\":4,\"quantidade\":2}' $API/api/carrinho/carrinhos/$CARRINHO/itens | jq .total"
igual com "estoque do catalogo foi baixado em 2 unidades" "$((ESTOQUE_ANTES - 2))" pdv "curl -sf $CA $API/api/catalogo/produtos/4 | jq .estoque"
contem com "carrinho descobriu o catalogo via DNS SRV" '"origem":"dns-srv"' \
    pdv "curl -sf $CA -u '$CRED' $API/api/carrinho/diagnostico/descoberta | jq -c ."
contem com "X-Request-ID propagado (rastreabilidade)" '^x-request-id: [0-9a-f]{32}' \
    pdv "curl -sI $CA $API/api/catalogo/produtos | tr -d '\r' | grep -i '^x-request-id'"

# ----------------------------------------------------------------------------
titulo "5. Seguranca (DevSecOps)"
igual seg "sem credenciais -> 401" "401" http_status "$CA -X POST $API/api/carrinho/carrinhos"
igual seg "senha errada -> 401" "401" http_status "$CA -u operador:errada -X POST $API/api/carrinho/carrinhos"  # gitleaks:allow (senha errada proposital)
igual seg "reserva de estoque bloqueada no gateway (somente GET) -> 403" "403" http_status "$CA -X POST $API/api/catalogo/produtos/4/reservas"
igual seg "HTTP redireciona para HTTPS -> 301" "301" http_status "http://api.vinheria.local/api/catalogo/produtos"
contem seg "HSTS habilitado" '^strict-transport-security: max-age=31536000' \
    pdv "curl -sI $CA $API/health | tr -d '\r' | tr 'A-Z' 'a-z'"
contem seg "gateway negocia TLS 1.3" 'TLSv1\.3' \
    pdv "curl -sv -o /dev/null $CA $API/health 2>&1 | grep -i 'SSL connection using'"
contem seg "TLS 1.1 rejeitado pelo gateway" '(alert protocol version|no protocols available|unsupported protocol|wrong version)' \
    pdv "openssl s_client -connect api.vinheria.local:443 -tls1_1 -cipher 'DEFAULT@SECLEVEL=0' </dev/null 2>&1"
contem seg "certificado do gateway emitido pela CA interna" 'Vinheria Agnello Root CA' \
    pdv "curl -sv -o /dev/null $CA $API/health 2>&1 | grep -i 'issuer'"
contem seg "catalogo recusa conexao direta sem certificado de cliente (mTLS)" '^(35|56)$' \
    pdv "curl -s -o /dev/null $CA https://catalogo.vinheria.local:8443/produtos; echo \$?"
DIAG=$(no_servico carrinho "python -m app.diagnostico todos" 2>&1)
contem seg "catalogo: reserva SEM JWT -> 401 (mesmo com mTLS)" 'sem-jwt +-> HTTP 401' echo "$DIAG"
contem seg "catalogo: JWT adulterado (escalada de escopo) -> 401" 'jwt-adulterado +-> HTTP 401' echo "$DIAG"
contem seg "catalogo: JWT valido -> 201" 'jwt-valido +-> HTTP 201' echo "$DIAG"
contem seg "catalogo: reuso do mesmo JWT (replay) -> 401" 'jwt-replay +-> HTTP 401' echo "$DIAG"
contem seg "containers de aplicacao rodam como usuario nao-root" '^10001$' no_servico catalogo "id -u"
contem seg "sistema de arquivos dos servicos e somente leitura" 'Read-only' no_servico catalogo "touch /app/x 2>&1"

# ----------------------------------------------------------------------------
printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="smoke-test" tests="%d" failures="%d">%s</testsuite>\n' \
    "$total" "$falhas" "$casos" > "$RELATORIO"

echo
if [ "$falhas" -eq 0 ]; then
    printf '%s%sSMOKE TEST OK%s - %d verificacoes aprovadas (relatorio: %s)\n' "$NEGRITO" "$VERDE" "$RESET" "$total" "$RELATORIO"
else
    printf '%s%sSMOKE TEST FALHOU%s - %d de %d verificacoes falharam\n' "$NEGRITO" "$VERMELHO" "$RESET" "$falhas" "$total"
    exit 1
fi
