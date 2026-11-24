"""Testes do carrinho-service (catalogo simulado por um dublê)."""

from __future__ import annotations

import base64

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app import autenticacao, main
from app.cliente_catalogo import ErroCatalogo
from app.descoberta import DescobertaServico
from app.token_servico import EmissorToken

USUARIO, SENHA = "operador", "senha-de-teste"


class CatalogoFalso:
    def __init__(self) -> None:
        self.produtos = {2: {"id": 2, "nome": "Vinho Tinto Cabernet", "preco": 89.0, "estoque": 5}}
        self.reservas = 0

    def obter_produto(self, produto_id: int, request_id: str) -> dict:
        if produto_id not in self.produtos:
            raise ErroCatalogo(404, "produto nao encontrado")
        return self.produtos[produto_id]

    def reservar(self, produto_id: int, quantidade: int, request_id: str) -> dict:
        if quantidade > self.produtos[produto_id]["estoque"]:
            raise ErroCatalogo(409, "estoque insuficiente")
        self.reservas += 1
        return {"reserva_id": f"r{self.reservas}"}


@pytest.fixture()
def catalogo():
    return CatalogoFalso()


@pytest.fixture()
def cliente(catalogo):
    main.carrinhos = main.RepositorioCarrinhos()
    autenticacao.limitador = autenticacao.LimitadorFalhas()
    main.app.dependency_overrides[main.obter_cliente_catalogo] = lambda: catalogo
    main.app.dependency_overrides[autenticacao.obter_credenciais] = lambda: (USUARIO, SENHA)
    with TestClient(main.app) as c:
        yield c
    main.app.dependency_overrides.clear()


AUTH = (USUARIO, SENHA)


def test_health_publico(cliente):
    assert cliente.get("/health").json()["servico"] == "carrinho-service"


def test_rotas_exigem_autenticacao(cliente):
    resposta = cliente.post("/carrinhos")
    assert resposta.status_code == 401
    assert resposta.headers["WWW-Authenticate"].startswith("Basic")


def test_senha_errada(cliente):
    assert cliente.post("/carrinhos", auth=(USUARIO, "errada")).status_code == 401


def test_forca_bruta_e_bloqueada(cliente):
    for _ in range(autenticacao.MAX_FALHAS):
        assert cliente.post("/carrinhos", auth=(USUARIO, "x")).status_code == 401
    bloqueado = cliente.post("/carrinhos", auth=AUTH)
    assert bloqueado.status_code == 429
    assert "Retry-After" in bloqueado.headers


def test_fluxo_completo_do_carrinho(cliente, catalogo):
    carrinho = cliente.post("/carrinhos", auth=AUTH).json()
    assert carrinho["total"] == 0

    url = f"/carrinhos/{carrinho['id']}/itens"
    assert cliente.post(url, json={"produto_id": 2, "quantidade": 2}, auth=AUTH).status_code == 201
    corpo = cliente.post(url, json={"produto_id": 2, "quantidade": 1}, auth=AUTH).json()

    assert corpo["itens"][0]["quantidade"] == 3
    assert corpo["itens"][0]["reservas"] == ["r1", "r2"]
    assert corpo["total"] == pytest.approx(267.0)

    vazio = cliente.delete(f"{url}/2", auth=AUTH).json()
    assert vazio["itens"] == [] and vazio["total"] == 0


@pytest.mark.parametrize(
    ("produto_id", "quantidade", "status"), [(999, 1, 404), (2, 6, 409), (2, 0, 422)]
)
def test_erros_do_catalogo_sao_repassados(cliente, produto_id, quantidade, status):
    carrinho = cliente.post("/carrinhos", auth=AUTH).json()
    resposta = cliente.post(
        f"/carrinhos/{carrinho['id']}/itens",
        json={"produto_id": produto_id, "quantidade": quantidade},
        auth=AUTH,
    )
    assert resposta.status_code == status


def test_carrinho_inexistente(cliente):
    assert cliente.get("/carrinhos/naoexiste", auth=AUTH).status_code == 404


# --------------------------------------------------------- token servico->servico
def test_token_emitido_tem_claims_de_menor_privilegio():
    chave = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = chave.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    emissor = EmissorToken(pem, emissor="carrinho-service", audiencia="catalogo-service")
    token = emissor.emitir("estoque:reservar")

    cabecalho = jwt.get_unverified_header(token)
    assert cabecalho["alg"] == "RS256" and cabecalho["kid"] == emissor.kid

    claims = jwt.decode(token, chave.public_key(), algorithms=["RS256"],
                        audience="catalogo-service", issuer="carrinho-service")
    assert claims["scope"] == "estoque:reservar"
    assert claims["exp"] - claims["iat"] == 60
    assert emissor.emitir("x") != token  # jti unico a cada chamada


def test_descoberta_usa_url_padrao_quando_dns_falha():
    descoberta = DescobertaServico("_inexistente._tcp.invalid", "https://catalogo.local:9443")
    destino = descoberta.resolver()
    assert (destino.host, destino.porta, destino.origem) == ("catalogo.local", 9443, "url-padrao")


def test_basic_auth_nao_e_criptografia():
    """Documenta o motivo do TLS: Base64 se reverte trivialmente."""
    cabecalho = base64.b64encode(f"{USUARIO}:{SENHA}".encode()).decode()
    assert base64.b64decode(cabecalho).decode() == f"{USUARIO}:{SENHA}"
