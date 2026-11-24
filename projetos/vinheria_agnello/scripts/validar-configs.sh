#!/usr/bin/env bash
# =============================================================================
# Lint da infraestrutura como codigo:
#   - docker compose config   (sintaxe/semantica do compose, com e sem perfis)
#   - hadolint                (boas praticas de Dockerfile)
#   - shellcheck              (bugs em scripts shell)
# As ferramentas rodam em containers lendo o arquivo pelo STDIN - sem bind
# mount, portanto funciona tambem no Jenkins (Docker-out-of-Docker).
# As validacoes de BIND (named-checkzone) e Kea (kea-dhcp4 -t) acontecem
# dentro do build das imagens.
# =============================================================================
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

HADOLINT_IMG=hadolint/hadolint:v2.12.0-alpine
SHELLCHECK_IMG=koalaman/shellcheck-alpine:v0.10.0
falhas=0

titulo "docker compose config"
for perfil in "" "--profile demo-inseguro"; do
    # shellcheck disable=SC2086
    if "${COMPOSE[@]}" $perfil config --quiet; then
        echo "  ✔ compose valido ${perfil:-(perfil padrao)}"
    else
        echo "  ✘ compose invalido ${perfil}"; falhas=$((falhas + 1))
    fi
done

titulo "hadolint (Dockerfiles)"
while IFS= read -r arquivo; do
    if saida=$(docker run --rm -i "$HADOLINT_IMG" hadolint --failure-threshold error \
                 --ignore DL3018 --ignore DL3008 - < "$arquivo" 2>&1); then
        echo "  ✔ $arquivo"
    else
        echo "  ✘ $arquivo"; falhas=$((falhas + 1))
    fi
    [ -n "$saida" ] && sed 's/^/      /' <<<"$saida"
done < <(find infra services jenkins -name Dockerfile | sort)

titulo "shellcheck (scripts)"
while IFS= read -r arquivo; do
    if saida=$(docker run --rm -i "$SHELLCHECK_IMG" shellcheck -S warning -e SC1091 - < "$arquivo" 2>&1); then
        echo "  ✔ $arquivo"
    else
        echo "  ✘ $arquivo"; falhas=$((falhas + 1)); sed 's/^/      /' <<<"$saida"
    fi
done < <(find scripts infra -name '*.sh' | sort)

echo
if [ "$falhas" -eq 0 ]; then echo "${VERDE}validacao OK${RESET}"; else echo "${VERMELHO}$falhas problema(s)${RESET}"; exit 1; fi
