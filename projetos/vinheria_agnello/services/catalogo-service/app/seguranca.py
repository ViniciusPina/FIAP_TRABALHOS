"""Validacao dos JWT servico-a-servico emitidos pelo carrinho-service.

Regras (defesa em profundidade):
  * somente RS256 - bloqueia "alg=none" e confusao de algoritmo (HS256 com chave publica);
  * emissor (iss) e audiencia (aud) obrigatorios e conferidos;
  * exp/iat/jti obrigatorios, com tolerancia de relogio pequena;
  * escopo exigido por operacao (menor privilegio);
  * jti de uso unico - um token capturado na rede nao pode ser reutilizado (anti-replay).
"""

from __future__ import annotations

import os
import threading
import time
from dataclasses import dataclass
from functools import lru_cache

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class ConfigJWT:
    chave_publica: str
    emissor: str
    audiencia: str
    tolerancia_s: int = 5


class CacheAntiReplay:
    """Guarda os jti ja utilizados ate o token expirar."""

    def __init__(self) -> None:
        self._vistos: dict[str, float] = {}
        self._lock = threading.Lock()

    def registrar(self, jti: str, expira_em: float) -> bool:
        agora = time.time()
        with self._lock:
            for chave in [k for k, exp in self._vistos.items() if exp < agora]:
                del self._vistos[chave]
            if jti in self._vistos:
                return False
            self._vistos[jti] = expira_em
            return True


_anti_replay = CacheAntiReplay()


@lru_cache(maxsize=1)
def obter_config_jwt() -> ConfigJWT:
    caminho = os.environ.get("JWT_PUBLIC_KEY_FILE", "/run/pki/jwt-carrinho.pub")
    with open(caminho, encoding="utf-8") as arquivo:
        chave = arquivo.read()
    return ConfigJWT(
        chave_publica=chave,
        emissor=os.environ.get("JWT_ISSUER", "carrinho-service"),
        audiencia=os.environ.get("JWT_AUDIENCE", "catalogo-service"),
    )


def _nao_autorizado(motivo: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=f"token invalido: {motivo}",
        headers={"WWW-Authenticate": f'Bearer error="invalid_token", error_description="{motivo}"'},
    )


def validar_token(token: str, config: ConfigJWT) -> dict:
    try:
        claims = jwt.decode(
            token,
            config.chave_publica,
            algorithms=["RS256"],
            audience=config.audiencia,
            issuer=config.emissor,
            leeway=config.tolerancia_s,
            options={"require": ["exp", "iat", "iss", "aud", "sub", "jti"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise _nao_autorizado("token expirado") from exc
    except jwt.InvalidTokenError as exc:
        raise _nao_autorizado(type(exc).__name__) from exc

    if not _anti_replay.registrar(claims["jti"], float(claims["exp"]) + config.tolerancia_s):
        raise _nao_autorizado("token ja utilizado (replay)")
    return claims


def exigir_escopo(escopo: str):
    """Dependencia FastAPI: exige Bearer JWT valido contendo o escopo informado."""

    def dependencia(
        credenciais: HTTPAuthorizationCredentials | None = Depends(_bearer),
        config: ConfigJWT = Depends(obter_config_jwt),
    ) -> dict:
        if credenciais is None or credenciais.scheme.lower() != "bearer":
            raise _nao_autorizado("cabecalho Authorization Bearer ausente")
        claims = validar_token(credenciais.credentials, config)
        if escopo not in str(claims.get("scope", "")).split():
            desafio = f'Bearer error="insufficient_scope", scope="{escopo}"'
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"escopo '{escopo}' necessario",
                headers={"WWW-Authenticate": desafio},
            )
        return claims

    return dependencia
