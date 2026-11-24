"""Ataques simulados contra o catalogo-service (demonstracao da Parte 3).

Executa a partir do container do carrinho, que possui certificado valido
(mTLS ok) - o objetivo e provar que, mesmo dentro da rede e com TLS, o
catalogo exige um JWT valido para alterar estoque.

Uso:  docker compose exec carrinho python -m app.diagnostico [cenario]
      cenarios: sem-jwt | jwt-adulterado | jwt-replay | jwt-valido | todos
"""

from __future__ import annotations

import base64
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

from .descoberta import DescobertaServico
from .token_servico import EmissorToken


def _contexto() -> ssl.SSLContext:
    contexto = ssl.create_default_context(cafile=os.environ["TLS_CA_FILE"])
    contexto.load_cert_chain(os.environ["TLS_CERT_FILE"], os.environ["TLS_KEY_FILE"])
    return contexto


def _reservar(token: str | None) -> int:
    destino = DescobertaServico(
        os.getenv("CATALOGO_SRV"), os.getenv("CATALOGO_URL_PADRAO", "")
    ).resolver()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    requisicao = urllib.request.Request(  # noqa: S310 - URL interna vinda do DNS SRV
        f"{destino.url_base}/produtos/1/reservas",
        data=json.dumps({"quantidade": 1}).encode(),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(requisicao, context=_contexto(), timeout=5) as resposta:  # noqa: S310
            return resposta.status
    except urllib.error.HTTPError as erro:
        return erro.code


def _emissor() -> EmissorToken:
    with open(os.environ["JWT_PRIVATE_KEY_FILE"], "rb") as arquivo:
        return EmissorToken(arquivo.read(), "carrinho-service", "catalogo-service")


def _adulterar(token: str) -> str:
    cabecalho, corpo, assinatura = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(corpo + "=" * (-len(corpo) % 4)))
    claims["scope"] = "estoque:reservar admin"  # tenta escalar privilegio
    novo = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode()
    return f"{cabecalho}.{novo}.{assinatura}"


def main() -> int:
    cenario = sys.argv[1] if len(sys.argv) > 1 else "todos"
    resultados: dict[str, int] = {}
    if cenario in ("sem-jwt", "todos"):
        resultados["sem-jwt"] = _reservar(None)
    if cenario in ("jwt-adulterado", "todos"):
        resultados["jwt-adulterado"] = _reservar(_adulterar(_emissor().emitir("estoque:reservar")))
    if cenario in ("jwt-replay", "jwt-valido", "todos"):
        token = _emissor().emitir("estoque:reservar")
        resultados["jwt-valido"] = _reservar(token)
        if cenario != "jwt-valido":
            resultados["jwt-replay"] = _reservar(token)
    for nome, codigo in resultados.items():
        print(f"{nome:15s} -> HTTP {codigo}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
