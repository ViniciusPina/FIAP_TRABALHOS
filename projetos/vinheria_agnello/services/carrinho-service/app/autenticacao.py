"""Autenticacao do operador do PDV (HTTP Basic) com protecao contra forca bruta.

HTTP Basic so e aceitavel sobre TLS: o cabecalho e apenas Base64 (nao e
criptografia). A demonstracao com Wireshark (Parte 3) mostra exatamente isso.
"""

from __future__ import annotations

import hashlib
import os
import secrets
import threading
import time
from collections import defaultdict, deque
from functools import lru_cache

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials

_basic = HTTPBasic(auto_error=False, realm="Vinheria Agnello")

MAX_FALHAS = 5
JANELA_S = 60


class LimitadorFalhas:
    def __init__(self) -> None:
        self._falhas: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def _limpar(self, origem: str, agora: float) -> deque[float]:
        fila = self._falhas[origem]
        while fila and fila[0] < agora - JANELA_S:
            fila.popleft()
        return fila

    def bloqueado(self, origem: str) -> bool:
        with self._lock:
            return len(self._limpar(origem, time.monotonic())) >= MAX_FALHAS

    def registrar_falha(self, origem: str) -> None:
        with self._lock:
            self._limpar(origem, time.monotonic()).append(time.monotonic())

    def zerar(self, origem: str) -> None:
        with self._lock:
            self._falhas.pop(origem, None)


limitador = LimitadorFalhas()


@lru_cache(maxsize=1)
def obter_credenciais() -> tuple[str, str]:
    usuario = os.environ.get("OPERADOR_USUARIO", "operador")
    caminho = os.environ.get("OPERADOR_SENHA_FILE", "/run/secrets/operador_senha")
    with open(caminho, encoding="utf-8") as arquivo:
        return usuario, arquivo.read().strip()


def _hash(valor: str) -> bytes:
    return hashlib.sha256(valor.encode()).digest()


def _negar(mensagem: str) -> HTTPException:
    return HTTPException(
        status.HTTP_401_UNAUTHORIZED,
        mensagem,
        headers={"WWW-Authenticate": 'Basic realm="Vinheria Agnello", charset="UTF-8"'},
    )


def exigir_operador(
    request: Request,
    credenciais: HTTPBasicCredentials | None = Depends(_basic),
    esperado: tuple[str, str] = Depends(obter_credenciais),
) -> str:
    origem = request.client.host if request.client else "desconhecida"
    if limitador.bloqueado(origem):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "muitas tentativas de login - aguarde 1 minuto",
            headers={"Retry-After": str(JANELA_S)},
        )
    if credenciais is None:
        raise _negar("autenticacao necessaria")

    # compare_digest sobre o hash: tempo constante e sem vazar o tamanho da senha
    usuario_ok = secrets.compare_digest(_hash(credenciais.username), _hash(esperado[0]))
    senha_ok = secrets.compare_digest(_hash(credenciais.password), _hash(esperado[1]))
    if not (usuario_ok and senha_ok):
        limitador.registrar_falha(origem)
        raise _negar("credenciais invalidas")

    limitador.zerar(origem)
    return credenciais.username
