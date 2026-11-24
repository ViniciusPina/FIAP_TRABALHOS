#!/usr/bin/env bash
# =============================================================================
# Deploy na PASTA DE PUBLICACAO (simula um servidor IIS: C:\inetpub\wwwroot).
#
#   <pub>/releases/<versao>/   releases imutaveis (historico, ultimas 5)
#   <pub>/wwwroot/             o que o "IIS" serve = release ativo
#   <pub>/versao-atual.txt     versao ativa
#   <pub>/historico.txt        ordem dos deploys (usado no rollback)
#   <pub>/deploy.log           auditoria: quem, quando, o que
#
# Uso: bash scripts/publicar.sh <pacote.tar.gz> <pasta_publicacao>
#      bash scripts/publicar.sh --rollback <pasta_publicacao>
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

MANTER=5
registrar() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | ${BUILD_TAG:-manual} | $*" >> "$PUB/deploy.log"; }

ativar() { # ativar <versao>  -> troca o conteudo do wwwroot pelo release
    local versao=$1 origem="$PUB/releases/$1/site"
    [ -d "$origem" ] || { erro "release $versao nao encontrado em $PUB/releases"; exit 1; }
    rm -rf "$PUB/wwwroot.novo"
    cp -r "$origem" "$PUB/wwwroot.novo"
    # troca quase atomica: o "site" nunca fica pela metade
    if [ -d "$PUB/wwwroot" ]; then mv "$PUB/wwwroot" "$PUB/wwwroot.antigo"; fi
    mv "$PUB/wwwroot.novo" "$PUB/wwwroot"
    rm -rf "$PUB/wwwroot.antigo"
    echo "$versao" > "$PUB/versao-atual.txt"
}

if [ "${1:-}" = "--rollback" ]; then
    PUB=${2:?informe a pasta de publicacao}
    [ -f "$PUB/historico.txt" ] || { aviso "nada para reverter (sem historico)"; exit 0; }
    atual=$(cat "$PUB/versao-atual.txt" 2>/dev/null || true)
    anterior=$(grep -vx "$atual" "$PUB/historico.txt" | tail -1 || true)
    [ -n "$anterior" ] || { aviso "nao ha versao anterior a $atual"; exit 0; }
    ativar "$anterior"
    echo "$anterior" >> "$PUB/historico.txt"
    registrar "ROLLBACK $atual -> $anterior"
    info "rollback concluido: $atual -> $anterior"
    exit 0
fi

PACOTE=${1:?informe o pacote .tar.gz}
PUB=${2:?informe a pasta de publicacao}
mkdir -p "$PUB/releases"

# 1) Integridade do artefato
if [ -f "$PACOTE.sha256" ]; then
    (cd "$(dirname "$PACOTE")" && sha256sum -c "$(basename "$PACOTE").sha256" >/dev/null) \
        || { erro "checksum invalido - deploy abortado"; exit 1; }
    info "checksum SHA-256 conferido"
fi

# 2) Extrai como release imutavel
NOME=$(basename "$PACOTE" .tar.gz)
VERSAO=${NOME#vinheria-agnello-}
rm -rf "$PUB/releases/$VERSAO"
mkdir -p "$PUB/releases/$VERSAO"
tar -xzf "$PACOTE" -C "$PUB/releases/$VERSAO" --strip-components=1

# 3) Ativa e registra
anterior=$(cat "$PUB/versao-atual.txt" 2>/dev/null || echo "-")
ativar "$VERSAO"
echo "$VERSAO" >> "$PUB/historico.txt"
registrar "DEPLOY $anterior -> $VERSAO"

# 4) Retencao: mantem apenas os ultimos releases
mapfile -t antigos < <(ls -1t "$PUB/releases" | tail -n +$((MANTER + 1)))
for r in "${antigos[@]}"; do rm -rf "${PUB:?}/releases/$r"; info "release antigo removido: $r"; done

info "Deploy da Vinheria concluido: $anterior -> $VERSAO"
info "pasta publicada: $PUB/wwwroot  ($(ls "$PUB/wwwroot" | paste -sd' ' -))"
