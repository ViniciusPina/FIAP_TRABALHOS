#!/usr/bin/env bash
# =============================================================================
# Parte 3 - "O que acontece sem seguranca?"
#
# Captura o MESMO fluxo de compra duas vezes:
#   01-sem-tls-http.pcap   cliente -> gateway-inseguro (HTTP puro, porta 80)
#   02-com-tls-https.pcap  cliente -> gateway          (HTTPS/TLS 1.3, porta 443)
# e prova automaticamente o que um atacante na rede consegue ler em cada caso.
# Os .pcap ficam em ./capturas e abrem direto no Wireshark.
#
# Uso: bash scripts/demo-wireshark.sh
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

PERFIL=(--profile demo-inseguro)
CRED="${OPERADOR_USUARIO}:${OPERADOR_SENHA}"
mkdir -p capturas
rm -f capturas/*.pcap

titulo "Subindo o gateway INSEGURO (HTTP) e os sniffers"
"${COMPOSE[@]}" "${PERFIL[@]}" up -d --no-deps gateway-inseguro >/dev/null
aguardar_saude 120
"${COMPOSE[@]}" "${PERFIL[@]}" up -d --no-deps --build captura-http captura-https >/dev/null 2>&1
sleep 3

fluxo() { # fluxo <url-base> <curl-extra>
    pdv "C=\$(curl -s $2 -u '$CRED' -X POST $1/api/carrinho/carrinhos | jq -r .id); \
         curl -s $2 -u '$CRED' -H 'Content-Type: application/json' \
              -d '{\"produto_id\":5,\"quantidade\":1}' $1/api/carrinho/carrinhos/\$C/itens | jq -c '{id,total}'"
}

titulo "Fluxo de compra SEM TLS  (http://inseguro.vinheria.local)"
fluxo "http://inseguro.vinheria.local" ""
titulo "Fluxo de compra COM TLS  (https://api.vinheria.local)"
fluxo "https://api.vinheria.local" "--cacert /run/pki/ca.crt"

sleep 2
"${COMPOSE[@]}" "${PERFIL[@]}" stop captura-http captura-https >/dev/null

ler() { # ler <pcap>  -> conteudo ASCII dos pacotes (tcpdump -A)
    # reaproveita o servico do compose (o bind mount ./capturas funciona igual no Windows)
    "${COMPOSE[@]}" "${PERFIL[@]}" run --rm --no-deps -T captura-http -nn -A -r "/capturas/$1" 2>/dev/null
}

HTTP_TXT=$(ler 01-sem-tls-http.pcap)
HTTPS_TXT=$(ler 02-com-tls-https.pcap)

titulo "O que o atacante le na captura SEM TLS"
CABECALHO=$(grep -m1 -o 'Authorization: Basic [A-Za-z0-9+/=]*' <<<"$HTTP_TXT" || true)
echo "  Cabecalho capturado : $CABECALHO"
echo "  Base64 decodificado : $(echo "${CABECALHO##* }" | base64 -d 2>/dev/null)"
echo "  Corpo da requisicao : $(grep -m1 -o '{"produto_id":[^}]*}' <<<"$HTTP_TXT" || true)"
echo "  Resposta (trecho)   : $(grep -m1 -o '{"id":"[0-9a-f]*","operador":"[a-z]*"' <<<"$HTTP_TXT" || true)"

titulo "O que o atacante le na captura COM TLS"
echo "  Ocorrencias de 'Authorization' : $(grep -c 'Authorization' <<<"$HTTPS_TXT" || true)"
echo "  Ocorrencias da senha           : $(grep -c -F "$OPERADOR_SENHA" <<<"$HTTPS_TXT" || true)"
echo "  Nome visivel no SNI do ClientHello: $(grep -m1 -o 'api\.vinheria\.local' <<<"$HTTPS_TXT" || echo '-')"
echo "  (o conteudo trafega como 'Application Data' cifrado com TLS 1.3)"

titulo "Verificacoes"
falhou=0
if grep -qF "$OPERADOR_SENHA" <<<"$(echo "${CABECALHO##* }" | base64 -d 2>/dev/null)"; then
    echo "  ${VERDE}✔${RESET} sem TLS: senha do operador recuperada da rede"
else echo "  ${VERMELHO}✘${RESET} sem TLS: senha nao encontrada na captura"; falhou=1; fi
if ! grep -q 'Authorization' <<<"$HTTPS_TXT" && ! grep -qF "$OPERADOR_SENHA" <<<"$HTTPS_TXT"; then
    echo "  ${VERDE}✔${RESET} com TLS: nenhuma credencial ou dado legivel"
else echo "  ${VERMELHO}✘${RESET} com TLS: dado sensivel apareceu na captura"; falhou=1; fi

cat <<EOF

Abra no Wireshark:  capturas/01-sem-tls-http.pcap   filtro:  http
                    capturas/02-com-tls-https.pcap  filtro:  tls
Dica: em 01, clique numa requisicao POST > "Hypertext Transfer Protocol" >
      "Authorization: Basic ..." (o Wireshark ja mostra a senha decodificada).
Para capturar ao vivo no Windows: Wireshark na interface "Adapter for loopback
traffic capture" e acesse http://localhost:${GATEWAY_INSEGURO_PORTA:-8881}/api/catalogo/produtos

Para desligar o gateway inseguro:  docker compose --profile demo-inseguro rm -sf gateway-inseguro captura-http captura-https
EOF
exit "$falhou"
