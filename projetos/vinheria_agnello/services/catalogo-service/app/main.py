"""catalogo-service - Vinheria Agnello.

Responsabilidades:
  * expor o catalogo de vinhos (leitura publica via gateway);
  * controlar o estoque: reservas so podem ser feitas por servicos autenticados
    com JWT RS256 que contenha o escopo "estoque:reservar".
"""

from __future__ import annotations

import os
import socket
import threading
import uuid
from copy import deepcopy
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Query, Request, status
from pydantic import BaseModel, Field

from .dados import PRODUTOS_INICIAIS
from .observabilidade import MiddlewareRequisicao, configurar_logs
from .seguranca import exigir_escopo

SERVICO = "catalogo-service"
VERSAO = os.getenv("APP_VERSION", "dev")
TipoVinho = Literal["tinto", "branco", "espumante", "rose"]

logger = configurar_logs(SERVICO)

app = FastAPI(
    title="Vinheria Agnello - catalogo-service",
    version=VERSAO,
    description="Catalogo de vinhos e controle de estoque.",
)
app.add_middleware(MiddlewareRequisicao, logger=logger)


class Produto(BaseModel):
    id: int
    nome: str
    tipo: TipoVinho
    preco: float
    estoque: int
    imagem: str
    descricao: str


class PedidoReserva(BaseModel):
    quantidade: int = Field(gt=0, le=24, description="garrafas (maximo 24 por reserva)")


class Reserva(BaseModel):
    reserva_id: str
    produto_id: int
    quantidade: int
    estoque_restante: int
    solicitante: str


class Estoque:
    """Repositorio em memoria, seguro para acesso concorrente."""

    def __init__(self, produtos: list[dict]) -> None:
        self._produtos = {p["id"]: deepcopy(p) for p in produtos}
        self._lock = threading.Lock()

    def listar(self) -> list[dict]:
        with self._lock:
            return [deepcopy(p) for p in self._produtos.values()]

    def obter(self, produto_id: int) -> dict | None:
        with self._lock:
            produto = self._produtos.get(produto_id)
            return deepcopy(produto) if produto else None

    def reservar(self, produto_id: int, quantidade: int) -> int:
        with self._lock:
            produto = self._produtos.get(produto_id)
            if produto is None:
                raise KeyError(produto_id)
            if produto["estoque"] < quantidade:
                raise ValueError(produto["estoque"])
            produto["estoque"] -= quantidade
            return produto["estoque"]


estoque = Estoque(PRODUTOS_INICIAIS)


@app.get("/health", tags=["operacao"])
def health() -> dict:
    return {"status": "ok", "servico": SERVICO, "versao": VERSAO, "host": socket.getfqdn()}


@app.get("/produtos", response_model=list[Produto], tags=["catalogo"])
def listar_produtos(
    tipo: TipoVinho | None = None,
    preco_max: float | None = Query(default=None, gt=0),
    busca: str | None = Query(default=None, max_length=60),
) -> list[dict]:
    produtos = estoque.listar()
    if tipo:
        produtos = [p for p in produtos if p["tipo"] == tipo]
    if preco_max is not None:
        produtos = [p for p in produtos if p["preco"] <= preco_max]
    if busca:
        termo = busca.lower()
        produtos = [p for p in produtos if termo in p["nome"].lower() or termo in p["tipo"]]
    return produtos


@app.get("/produtos/{produto_id}", response_model=Produto, tags=["catalogo"])
def obter_produto(produto_id: int) -> dict:
    produto = estoque.obter(produto_id)
    if produto is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "produto nao encontrado")
    return produto


@app.post(
    "/produtos/{produto_id}/reservas",
    response_model=Reserva,
    status_code=status.HTTP_201_CREATED,
    tags=["estoque"],
)
def reservar_estoque(
    produto_id: int,
    pedido: PedidoReserva,
    request: Request,
    claims: dict = Depends(exigir_escopo("estoque:reservar")),
) -> Reserva:
    try:
        restante = estoque.reservar(produto_id, pedido.quantidade)
    except KeyError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "produto nao encontrado") from None
    except ValueError as exc:
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"estoque insuficiente (disponivel: {exc.args[0]})"
        ) from None

    reserva = Reserva(
        reserva_id=uuid.uuid4().hex,
        produto_id=produto_id,
        quantidade=pedido.quantidade,
        estoque_restante=restante,
        solicitante=claims["sub"],
    )
    logger.info(
        "estoque reservado",
        extra={
            "extra_campos": {
                "request_id": getattr(request.state, "request_id", None),
                "produto_id": produto_id,
                "quantidade": pedido.quantidade,
                "solicitante": claims["sub"],
                "jti": claims["jti"],
            }
        },
    )
    return reserva
