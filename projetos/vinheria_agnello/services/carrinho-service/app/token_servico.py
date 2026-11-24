"""Emissao de JWT servico-a-servico (RS256).

Cada chamada ao catalogo leva um token NOVO, de vida curta (60 s), com jti
unico, audiencia restrita ao catalogo e somente o escopo necessario.
A chave privada so existe dentro do container do carrinho (volume PKI).
"""

from __future__ import annotations

import hashlib
import time
import uuid

import jwt
from cryptography.hazmat.primitives import serialization


class EmissorToken:
    def __init__(
        self, chave_privada_pem: bytes, emissor: str, audiencia: str, validade_s: int = 60
    ) -> None:
        self._chave = serialization.load_pem_private_key(chave_privada_pem, password=None)
        self.emissor = emissor
        self.audiencia = audiencia
        self.validade_s = validade_s
        publica = self._chave.public_key().public_bytes(
            serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
        )
        self.kid = hashlib.sha256(publica).hexdigest()[:16]

    def emitir(self, escopo: str) -> str:
        agora = int(time.time())
        claims = {
            "iss": self.emissor,
            "sub": self.emissor,
            "aud": self.audiencia,
            "scope": escopo,
            "iat": agora,
            "nbf": agora,
            "exp": agora + self.validade_s,
            "jti": uuid.uuid4().hex,
        }
        return jwt.encode(claims, self._chave, algorithm="RS256", headers={"kid": self.kid})
