#!/usr/bin/env bash
# Funcoes compartilhadas pelos scripts da Vinheria Agnello.
# shellcheck disable=SC2034

# Git Bash (Windows) reescreve caminhos como /etc/x para C:/Program Files/Git/etc/x
# ao chamar executaveis nativos (docker.exe). Isso quebra o "docker exec".
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1

COMPOSE=(docker compose)

if [ ! -f .env ]; then
    cp .env.example .env
    echo "[info] .env criado a partir de .env.example"
fi
# shellcheck disable=SC1091
set -a; . ./.env; set +a

if [ -t 1 ]; then
    VERDE=$'\e[32m'; VERMELHO=$'\e[31m'; AMARELO=$'\e[33m'; AZUL=$'\e[36m'; NEGRITO=$'\e[1m'; RESET=$'\e[0m'
else
    VERDE=""; VERMELHO=""; AMARELO=""; AZUL=""; NEGRITO=""; RESET=""
fi

titulo() { printf '\n%s== %s ==%s\n' "$NEGRITO$AZUL" "$*" "$RESET"; }
info()   { printf '%s[info]%s %s\n' "$AZUL" "$RESET" "$*"; }
aviso()  { printf '%s[aviso]%s %s\n' "$AMARELO" "$RESET" "$*"; }
erro()   { printf '%s[erro]%s %s\n' "$VERMELHO" "$RESET" "$*" >&2; }

# Executa um comando dentro de um servico do compose
no_servico() { local servico=$1; shift; "${COMPOSE[@]}" exec -T "$servico" sh -c "$*"; }
pdv() { no_servico estacao-pdv "$@"; }

# Espera todos os containers com healthcheck ficarem "healthy"
aguardar_saude() {
    local limite=${1:-180} inicio pendentes
    inicio=$(date +%s)
    while :; do
        pendentes=$("${COMPOSE[@]}" ps --format '{{.Service}} {{.Health}}' 2>/dev/null \
            | awk '$2 != "" && $2 != "healthy" {print $1"("$2")"}')
        if [ -z "$pendentes" ] && [ "$("${COMPOSE[@]}" ps -q | wc -l)" -gt 0 ]; then
            info "todos os servicos estao saudaveis"
            return 0
        fi
        if [ $(( $(date +%s) - inicio )) -ge "$limite" ]; then
            erro "tempo esgotado aguardando: $pendentes"
            "${COMPOSE[@]}" ps
            return 1
        fi
        sleep 3
    done
}
