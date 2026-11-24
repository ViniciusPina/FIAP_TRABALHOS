#!/usr/bin/env bash
# Aguarda todos os containers ficarem saudaveis (usado pelo CI e pelo Jenkins).
# Uso: bash scripts/aguardar-saude.sh [timeout_em_segundos]
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
aguardar_saude "${1:-180}"
