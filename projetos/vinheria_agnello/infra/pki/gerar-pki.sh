#!/bin/sh
# =============================================================================
# Bootstrap de segredos e PKI interna da Vinheria Agnello (roda 1x, idempotente)
#
#   /pki/ca/        CA raiz interna (chave privada fica SO aqui)
#   /pki/ddns/      segredo TSIG compartilhado DNS <-> DHCP (DDNS)
#   /pki/gateway/   certificado TLS de api.vinheria.local
#   /pki/catalogo/  certificado TLS (mTLS) + chave PUBLICA JWT do carrinho
#   /pki/carrinho/  certificado TLS (mTLS) + chave PRIVADA JWT (assinatura)
#   /pki/pdv/       apenas o certificado da CA (para confiar no gateway)
#
# Cada servico monta somente o seu subdiretorio (menor privilegio).
# Nada disso vai para o Git: e gerado no primeiro "docker compose up".
# =============================================================================
set -eu

PKI=/pki
VERSAO_PKI=1
APP_UID=10001
DIAS_CA=825
DIAS_CERT=397
SUBJ_BASE="/C=BR/ST=SP/L=Sao Paulo/O=Vinheria Agnello"

# A senha do operador chega como Docker secret e e repassada SOMENTE ao
# carrinho (0400, dono uid 10001). Roda sempre, para refletir trocas de senha.
sincronizar_senha_operador() {
    if [ -s /run/secrets/operador_senha ]; then
        install -m 0400 -o "$APP_UID" -g "$APP_UID" /run/secrets/operador_senha "$PKI/carrinho/operador.senha"
        echo "[pki] senha do operador entregue ao carrinho-service (Docker secret)"
    else
        echo "[pki] AVISO: secret operador_senha ausente - defina OPERADOR_SENHA no .env" >&2
    fi
}

if [ -f "$PKI/.versao" ] && [ "$(cat "$PKI/.versao")" = "$VERSAO_PKI" ]; then
    echo "[pki] material criptografico v$VERSAO_PKI ja existe - nada a fazer"
    sincronizar_senha_operador
    exit 0
fi

echo "[pki] gerando PKI interna v$VERSAO_PKI ..."
umask 077
rm -rf "${PKI:?}"/*
mkdir -p "$PKI/ca" "$PKI/ddns" "$PKI/gateway" "$PKI/catalogo" "$PKI/carrinho" "$PKI/pdv"
TMP=$(mktemp -d)

# 1) CA raiz interna (ECDSA P-256)
openssl req -x509 -new -nodes -sha256 -days "$DIAS_CA" \
    -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
    -keyout "$PKI/ca/ca.key" -out "$PKI/ca/ca.crt" \
    -subj "$SUBJ_BASE/OU=Infraestrutura/CN=Vinheria Agnello Root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

# 2) Certificados de servidor/cliente (serverAuth + clientAuth => mTLS)
emitir() {
    cn=$1; destino=$2; sans=$3
    openssl req -new -nodes -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$destino/tls.key" -out "$TMP/$cn.csr" \
        -subj "$SUBJ_BASE/OU=Servicos/CN=$cn" 2>/dev/null
    cat > "$TMP/$cn.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=$sans
EOF
    openssl x509 -req -sha256 -days "$DIAS_CERT" \
        -in "$TMP/$cn.csr" -CA "$PKI/ca/ca.crt" -CAkey "$PKI/ca/ca.key" \
        -set_serial "0x$(openssl rand -hex 16)" \
        -extfile "$TMP/$cn.ext" -out "$destino/tls.crt" 2>/dev/null
    cp "$PKI/ca/ca.crt" "$destino/ca.crt"
    echo "[pki]   certificado emitido: $cn ($sans)"
}

emitir api.vinheria.local      "$PKI/gateway"  "DNS:api.vinheria.local,DNS:gateway.vinheria.local,DNS:inseguro.vinheria.local,DNS:localhost,IP:127.0.0.1"
emitir catalogo.vinheria.local "$PKI/catalogo" "DNS:catalogo.vinheria.local,DNS:localhost,IP:127.0.0.1"
emitir carrinho.vinheria.local "$PKI/carrinho" "DNS:carrinho.vinheria.local,DNS:localhost,IP:127.0.0.1"
cp "$PKI/ca/ca.crt" "$PKI/pdv/ca.crt"

# 3) Par de chaves RS256 do carrinho-service (emissor dos JWT servico->servico)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$PKI/carrinho/jwt-privada.pem" 2>/dev/null
openssl pkey -in "$PKI/carrinho/jwt-privada.pem" -pubout -out "$PKI/catalogo/jwt-carrinho.pub"
echo "[pki]   par de chaves JWT RS256 do carrinho-service gerado"

# 4) Segredo TSIG (HMAC-SHA256) para o DNS dinamico
openssl rand -base64 32 > "$PKI/ddns/tsig.secret"
echo "[pki]   segredo TSIG para DDNS gerado"

# 5) Permissoes: chaves privadas 0400, legiveis apenas pelo dono do servico
chmod 0400 "$PKI"/*/*.key "$PKI/carrinho/jwt-privada.pem" "$PKI/ddns/tsig.secret"
chmod 0444 "$PKI"/*/*.crt "$PKI/catalogo/jwt-carrinho.pub"
chmod 0555 "$PKI"/ddns "$PKI"/gateway "$PKI"/pdv
chmod 0500 "$PKI/ca"
chown -R "$APP_UID:$APP_UID" "$PKI/catalogo" "$PKI/carrinho"
chmod 0500 "$PKI/catalogo" "$PKI/carrinho"

rm -rf "$TMP"
sincronizar_senha_operador
echo "$VERSAO_PKI" > "$PKI/.versao"
echo "[pki] concluido. Impressao digital da CA:"
openssl x509 -in "$PKI/ca/ca.crt" -noout -fingerprint -sha256
