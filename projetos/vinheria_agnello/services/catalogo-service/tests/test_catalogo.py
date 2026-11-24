"""Testes do catalogo-service: regras de negocio + seguranca do JWT."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
import uuid

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app import main
from app.dados import PRODUTOS_INICIAIS
from app.seguranca import ConfigJWT, obter_config_jwt


def _gerar_chaves() -> tuple[bytes, str]:
    privada = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem_privada = privada.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    pem_publica = privada.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    return pem_privada, pem_publica.decode()


PRIVADA, PUBLICA = _gerar_chaves()
PRIVADA_INTRUSO, _ = _gerar_chaves()


def emitir(chave=PRIVADA, alg="RS256", **sobrescrever) -> str:
    agora = int(time.time())
    claims = {
        "iss": "carrinho-service",
        "sub": "carrinho-service",
        "aud": "catalogo-service",
        "scope": "estoque:reservar",
        "iat": agora,
        "exp": agora + 60,
        "jti": uuid.uuid4().hex,
    }
    claims.update(sobrescrever)
    return jwt.encode(claims, chave, algorithm=alg)


def emitir_hs256_com_chave_publica() -> str:
    """Ataque classico de 'confusao de algoritmo': o atacante assina com HMAC
    usando a chave PUBLICA (que todos conhecem) como segredo. Montado a mao
    porque o proprio PyJWT se recusa a gerar esse token."""
    agora = int(time.time())

    def b64(dados: bytes) -> bytes:
        return base64.urlsafe_b64encode(dados).rstrip(b"=")

    cabecalho = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    corpo = b64(
        json.dumps(
            {
                "iss": "carrinho-service",
                "sub": "atacante",
                "aud": "catalogo-service",
                "scope": "estoque:reservar",
                "iat": agora,
                "exp": agora + 60,
                "jti": uuid.uuid4().hex,
            }
        ).encode()
    )
    assinatura = b64(hmac.new(PUBLICA.encode(), cabecalho + b"." + corpo, hashlib.sha256).digest())
    return (cabecalho + b"." + corpo + b"." + assinatura).decode()


@pytest.fixture()
def cliente():
    main.estoque = main.Estoque(PRODUTOS_INICIAIS)
    main.app.dependency_overrides[obter_config_jwt] = lambda: ConfigJWT(
        chave_publica=PUBLICA, emissor="carrinho-service", audiencia="catalogo-service"
    )
    with TestClient(main.app) as c:
        yield c
    main.app.dependency_overrides.clear()


def reservar(cliente, token: str | None, produto_id: int = 2, quantidade: int = 2):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return cliente.post(
        f"/produtos/{produto_id}/reservas", json={"quantidade": quantidade}, headers=headers
    )


# ----------------------------------------------------------------- catalogo
def test_health(cliente):
    resposta = cliente.get("/health")
    assert resposta.status_code == 200
    assert resposta.json()["servico"] == "catalogo-service"
    assert "X-Request-ID" in resposta.headers


def test_lista_os_seis_vinhos_do_catalogo_jsp(cliente):
    nomes = {p["nome"] for p in cliente.get("/produtos").json()}
    assert len(nomes) == 6
    assert "Malbec" in nomes


@pytest.mark.parametrize(
    ("filtro", "esperado"),
    [("tipo=tinto", 3), ("tipo=espumante", 2), ("preco_max=80", 1), ("busca=merlot", 1)],
)
def test_filtros(cliente, filtro, esperado):
    assert len(cliente.get(f"/produtos?{filtro}").json()) == esperado


def test_produto_inexistente(cliente):
    assert cliente.get("/produtos/999").status_code == 404


# ----------------------------------------------------------------- reservas
def test_reserva_com_token_valido_baixa_estoque(cliente):
    antes = cliente.get("/produtos/2").json()["estoque"]
    resposta = reservar(cliente, emitir(), quantidade=3)
    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["estoque_restante"] == antes - 3
    assert corpo["solicitante"] == "carrinho-service"
    assert cliente.get("/produtos/2").json()["estoque"] == antes - 3


def test_estoque_insuficiente(cliente):
    assert reservar(cliente, emitir(), produto_id=6, quantidade=24).status_code == 409


def test_quantidade_invalida(cliente):
    assert reservar(cliente, emitir(), quantidade=0).status_code == 422


# ----------------------------------------------------------------- seguranca
def test_sem_token_retorna_401(cliente):
    resposta = reservar(cliente, None)
    assert resposta.status_code == 401
    assert resposta.headers["WWW-Authenticate"].startswith("Bearer")


@pytest.mark.parametrize(
    "token",
    [
        pytest.param(emitir(aud="outro-servico"), id="audiencia-errada"),
        pytest.param(emitir(iss="atacante"), id="emissor-errado"),
        pytest.param(emitir(chave=PRIVADA_INTRUSO), id="assinado-por-outra-chave"),
        pytest.param(emitir(exp=int(time.time()) - 120), id="expirado"),
        pytest.param(emitir(chave=None, alg="none"), id="alg-none"),
        pytest.param(emitir_hs256_com_chave_publica(), id="confusao-de-algoritmo"),
        pytest.param("nao.e.um.jwt", id="malformado"),
    ],
)
def test_tokens_invalidos_sao_rejeitados(cliente, token):
    assert reservar(cliente, token).status_code == 401


def test_escopo_insuficiente_retorna_403(cliente):
    assert reservar(cliente, emitir(scope="catalogo:ler")).status_code == 403


def test_replay_do_mesmo_token_e_bloqueado(cliente):
    token = emitir()
    assert reservar(cliente, token).status_code == 201
    segunda = reservar(cliente, token)
    assert segunda.status_code == 401
    assert "replay" in segunda.json()["detail"]
