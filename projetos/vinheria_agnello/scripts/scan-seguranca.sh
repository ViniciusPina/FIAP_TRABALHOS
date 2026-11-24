#!/usr/bin/env bash
# =============================================================================
# DevSecOps - varreduras de seguranca do pipeline
#   1. gitleaks : segredos commitados por engano          -> BLOQUEIA o pipeline
#   2. trivy fs : dependencias vulneraveis + misconfig     -> relatorio
#   3. trivy img: vulnerabilidades CRITICAS nas imagens    -> relatorio
# Usa os binarios locais se existirem (imagem do Jenkins) ou containers.
# Relatorios em relatorios/seguranca/
# =============================================================================
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

SAIDA=relatorios/seguranca
mkdir -p "$SAIDA"
GITLEAKS_IMG=zricethezav/gitleaks:v8.21.2
TRIVY_IMG=aquasec/trivy:0.58.1
# Caminho do projeto no formato aceito pelo Docker (Git Bash: C:/...)
PASTA_HOST=$(pwd -W 2>/dev/null || pwd)
bloqueios=0

gitleaks_run() {
    if command -v gitleaks >/dev/null; then gitleaks "$@"
    else docker run --rm -v "$PASTA_HOST:/repo" -w /repo "$GITLEAKS_IMG" "$@"; fi
}
trivy_run() {
    if command -v trivy >/dev/null; then trivy "$@"
    else docker run --rm -v "$PASTA_HOST:/repo" -w /repo -v vinheria-trivy-cache:/root/.cache \
            -v /var/run/docker.sock:/var/run/docker.sock "$TRIVY_IMG" "$@"; fi
}

titulo "1/3 gitleaks - segredos no codigo"
if gitleaks_run dir . --no-banner --redact --config .gitleaks.toml \
        --report-format json --report-path "$SAIDA/gitleaks.json"; then
    echo "  ${VERDE}✔ nenhum segredo encontrado${RESET}"
else
    echo "  ${VERMELHO}✘ segredos encontrados - veja $SAIDA/gitleaks.json${RESET}"; bloqueios=$((bloqueios + 1))
fi

titulo "2/3 trivy fs - dependencias (requirements.txt) e configuracao"
trivy_run fs --quiet --scanners vuln,misconfig --severity HIGH,CRITICAL \
    --skip-dirs relatorios --skip-dirs evidencias --skip-dirs dist --skip-dirs publicacao \
    --format table --exit-code 0 . | tee "$SAIDA/trivy-fs.txt"

titulo "3/3 trivy image - vulnerabilidades CRITICAS nas imagens publicadas"
for imagem in catalogo-service carrinho-service gateway; do
    ref="vinheria/$imagem:${APP_VERSION:-dev}"
    if docker image inspect "$ref" >/dev/null 2>&1; then
        trivy_run image --quiet --severity CRITICAL --ignore-unfixed --format table --exit-code 0 "$ref" \
            | tee "$SAIDA/trivy-$imagem.txt"
    else
        aviso "imagem $ref nao encontrada (rode docker compose build) - pulando"
    fi
done

echo
if [ "$bloqueios" -gt 0 ]; then
    echo "${VERMELHO}DevSecOps: pipeline BLOQUEADO ($bloqueios achado(s) critico(s))${RESET}"; exit 1
fi
echo "${VERDE}DevSecOps: nenhum bloqueio. Relatorios em $SAIDA/${RESET}"
