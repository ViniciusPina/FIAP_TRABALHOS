#!/usr/bin/env bash
# =============================================================================
# Empacota o release: artefato versionado, rastreavel e com checksum.
#   dist/vinheria-agnello-<versao>.tar.gz        (+ .sha256)
#     |- manifest.json   versao, commit, build, data, imagens (id/digest)
#     |- site/           "site" publicado na pasta do IIS simulado
#     |- deploy/         docker-compose.yml, infra/, scripts/ (infra como codigo)
#
# Uso: bash scripts/empacotar.sh <versao> [commit]
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

VERSAO=${1:-${APP_VERSION:-dev}}
COMMIT=${2:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}
BUILD=${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-local}}
DATA=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NOME="vinheria-agnello-$VERSAO"
TMP="dist/$NOME"

echo "Deploy da Vinheria - empacotando versao $VERSAO (commit $COMMIT, build $BUILD)"
rm -rf "$TMP" "dist/$NOME.tar.gz" "dist/$NOME.tar.gz.sha256"
mkdir -p "$TMP/site" "$TMP/deploy"

# 1) Infra como codigo (o que o servidor precisa para subir o ambiente)
cp -r docker-compose.yml .env.example infra scripts "$TMP/deploy/"

# 2) Inventario das imagens construidas nesta versao
imagens_json=$(docker image ls --format '{{json .}}' 2>/dev/null \
    | grep '"Repository":"vinheria/' | grep "\"Tag\":\"$VERSAO\"" \
    | sed -E 's/.*"ID":"([^"]+)".*"Repository":"([^"]+)".*"Tag":"([^"]+)".*/{"imagem":"\2:\3","id":"\1"}/' \
    | paste -sd, - || true)

cat > "$TMP/manifest.json" <<EOF
{
  "aplicacao": "vinheria-agnello",
  "versao": "$VERSAO",
  "commit": "$COMMIT",
  "build": "$BUILD",
  "gerado_em": "$DATA",
  "servicos": ["catalogo-service", "carrinho-service"],
  "imagens": [${imagens_json}]
}
EOF

# 3) Pagina de status publicada (o "site" que o IIS serviria)
cat > "$TMP/site/index.html" <<EOF
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>Vinheria Agnello - release $VERSAO</title>
<style>
 body{font-family:Georgia,serif;background:#1d0b10;color:#f4e9dc;margin:0;padding:48px}
 h1{color:#e3b873;font-weight:normal;margin:0 0 4px} .sub{color:#c9a99a;margin-bottom:32px}
 table{border-collapse:collapse;min-width:520px} td{padding:8px 16px;border-bottom:1px solid #4a2530}
 td:first-child{color:#c9a99a} code{color:#e3b873}
</style></head><body>
<h1>Vinheria Agnello</h1>
<div class="sub">Release publicado pelo pipeline de CI/CD</div>
<table>
<tr><td>Versao</td><td><code>$VERSAO</code></td></tr>
<tr><td>Commit</td><td><code>$COMMIT</code></td></tr>
<tr><td>Build</td><td><code>$BUILD</code></td></tr>
<tr><td>Publicado em (UTC)</td><td><code>$DATA</code></td></tr>
<tr><td>Microsservicos</td><td>catalogo-service, carrinho-service</td></tr>
<tr><td>API</td><td><code>https://api.vinheria.local</code></td></tr>
</table></body></html>
EOF

# web.config: o que o IIS leria ao servir esta pasta (cabecalhos de seguranca)
cat > "$TMP/site/web.config" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <defaultDocument><files><clear /><add value="index.html" /></files></defaultDocument>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Content-Type-Options" value="nosniff" />
        <add name="X-Frame-Options" value="DENY" />
        <add name="Strict-Transport-Security" value="max-age=31536000" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
EOF
cp "$TMP/manifest.json" "$TMP/site/manifest.json"

tar -czf "dist/$NOME.tar.gz" -C dist "$NOME"
(cd dist && sha256sum "$NOME.tar.gz" > "$NOME.tar.gz.sha256")
rm -rf "$TMP"

echo "Pacote: dist/$NOME.tar.gz"
cat "dist/$NOME.tar.gz.sha256"
