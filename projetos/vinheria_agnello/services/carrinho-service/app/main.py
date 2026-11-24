"""carrinho-service - Vinheria Agnello.

Fluxo ao adicionar um item:
  1. autentica o operador do PDV (HTTP Basic sobre TLS);
  2. descobre o catalogo via DNS SRV (_catalogo._tcp.vinheria.local);
  3. consulta o produto no catalogo (HTTPS + mTLS);
  4. reserva o estoque com um JWT RS256 de 60 s (escopo estoque:reservar);
  5. grava o item no carrinho.
"""

from __future__ import annotations

import os
import socket
import threading
import time
import uuid
from functools import lru_cache

from fastapi import Depends, FastAPI, HTTPException, Request, status
from pydantic import BaseModel, Field

from .autenticacao import exigir_operador
from .cliente_catalogo import ClienteCatalogo, ErroCatalogo
from .descoberta import DescobertaServico
from .observabilidade import MiddlewareRequisicao, configurar_logs
from .token_servico import EmissorToken

SERVICO = "carrinho-service"
VERSAO = os.getenv("APP_VERSION", "dev")

logger = configurar_logs(SERVICO)

app = FastAPI(
    title="Vinheria Agnello - carrinho-service",
    version=VERSAO,
    description="Carrinho de compras do PDV. Consome o catalogo-service.",
)
app.add_middleware(MiddlewareRequisicao, logger=logger)


# --------------------------------------------------------------------- modelos
class ItemEntrada(BaseModel):
    produto_id: int = Field(gt=0)
    quantidade: int = Field(gt=0, le=24)


class Item(BaseModel):
    produto_id: int
    nome: str
    preco_unitario: float
    quantidade: int
    subtotal: float
    reservas: list[str]


class Carrinho(BaseModel):
    id: str
    operador: str
    itens: list[Item]
    total: float
    criado_em: float


# --------------------------------------------------------------- dependencias
@lru_cache(maxsize=1)
def obter_descoberta() -> DescobertaServico:
    return DescobertaServico(
        registro_srv=os.getenv("CATALOGO_SRV"),
        url_padrao=os.getenv("CATALOGO_URL_PADRAO", "https://catalogo.vinheria.local:8443"),
    )


@lru_cache(maxsize=1)
def obter_cliente_catalogo() -> ClienteCatalogo:
    with open(os.environ["JWT_PRIVATE_KEY_FILE"], "rb") as arquivo:
        emissor = EmissorToken(
            arquivo.read(),
            emissor=os.getenv("JWT_ISSUER", "carrinho-service"),
            audiencia=os.getenv("JWT_AUDIENCE", "catalogo-service"),
        )
    return ClienteCatalogo(
        descoberta=obter_descoberta(),
        emissor=emissor,
        ca=os.environ["TLS_CA_FILE"],
        cert=os.environ["TLS_CERT_FILE"],
        chave=os.environ["TLS_KEY_FILE"],
    )


class RepositorioCarrinhos:
    def __init__(self) -> None:
        self._dados: dict[str, dict] = {}
        self._lock = threading.Lock()

    def criar(self, operador: str) -> dict:
        carrinho = {"id": uuid.uuid4().hex[:12], "operador": operador, "itens": {},
                    "criado_em": time.time()}
        with self._lock:
            self._dados[carrinho["id"]] = carrinho
        return carrinho

    def obter(self, carrinho_id: str) -> dict:
        with self._lock:
            carrinho = self._dados.get(carrinho_id)
        if carrinho is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "carrinho nao encontrado")
        return carrinho

    def adicionar(self, carrinho_id: str, produto: dict, quantidade: int, reserva: str) -> dict:
        with self._lock:
            carrinho = self._dados[carrinho_id]
            item = carrinho["itens"].setdefault(
                produto["id"],
                {"produto_id": produto["id"], "nome": produto["nome"],
                 "preco_unitario": produto["preco"], "quantidade": 0, "reservas": []},
            )
            item["quantidade"] += quantidade
            item["reservas"].append(reserva)
            return carrinho

    def remover(self, carrinho_id: str, produto_id: int) -> dict:
        with self._lock:
            carrinho = self._dados.get(carrinho_id)
            if carrinho is None or produto_id not in carrinho["itens"]:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "item nao encontrado")
            del carrinho["itens"][produto_id]
            return carrinho


carrinhos = RepositorioCarrinhos()


def _serializar(carrinho: dict) -> Carrinho:
    itens = [
        Item(**item, subtotal=round(item["preco_unitario"] * item["quantidade"], 2))
        for item in carrinho["itens"].values()
    ]
    return Carrinho(
        id=carrinho["id"],
        operador=carrinho["operador"],
        itens=itens,
        total=round(sum(i.subtotal for i in itens), 2),
        criado_em=carrinho["criado_em"],
    )


# ------------------------------------------------------------------- rotas
@app.get("/health", tags=["operacao"])
def health() -> dict:
    return {"status": "ok", "servico": SERVICO, "versao": VERSAO, "host": socket.getfqdn()}


@app.get("/diagnostico/descoberta", tags=["operacao"])
def diagnostico_descoberta(
    operador: str = Depends(exigir_operador),
    descoberta: DescobertaServico = Depends(obter_descoberta),
) -> dict:
    """Mostra como o carrinho encontrou o catalogo (evidencia de DNS SRV + DDNS)."""
    destino = descoberta.resolver(forcar=True)
    try:
        ips = sorted({info[4][0] for info in socket.getaddrinfo(destino.host, destino.porta)})
    except socket.gaierror:
        ips = []
    return {
        "registro_srv": descoberta.registro_srv,
        "origem": destino.origem,
        "host": destino.host,
        "porta": destino.porta,
        "ips_resolvidos": ips,
        "url_base": destino.url_base,
    }


@app.post("/carrinhos", response_model=Carrinho, status_code=status.HTTP_201_CREATED,
          tags=["carrinho"])
def criar_carrinho(operador: str = Depends(exigir_operador)) -> Carrinho:
    return _serializar(carrinhos.criar(operador))


@app.get("/carrinhos/{carrinho_id}", response_model=Carrinho, tags=["carrinho"])
def obter_carrinho(carrinho_id: str, operador: str = Depends(exigir_operador)) -> Carrinho:
    return _serializar(carrinhos.obter(carrinho_id))


@app.post("/carrinhos/{carrinho_id}/itens", response_model=Carrinho,
          status_code=status.HTTP_201_CREATED, tags=["carrinho"])
def adicionar_item(
    carrinho_id: str,
    entrada: ItemEntrada,
    request: Request,
    operador: str = Depends(exigir_operador),
    catalogo: ClienteCatalogo = Depends(obter_cliente_catalogo),
) -> Carrinho:
    carrinhos.obter(carrinho_id)
    request_id = getattr(request.state, "request_id", uuid.uuid4().hex)
    try:
        produto = catalogo.obter_produto(entrada.produto_id, request_id)
        reserva = catalogo.reservar(entrada.produto_id, entrada.quantidade, request_id)
    except ErroCatalogo as erro:
        raise HTTPException(erro.status, erro.detalhe) from None

    logger.info("item adicionado", extra={"extra_campos": {
        "request_id": request_id, "carrinho": carrinho_id, "operador": operador,
        "produto_id": entrada.produto_id, "quantidade": entrada.quantidade,
        "reserva": reserva["reserva_id"]}})
    return _serializar(carrinhos.adicionar(carrinho_id, produto, entrada.quantidade,
                                           reserva["reserva_id"]))


@app.delete("/carrinhos/{carrinho_id}/itens/{produto_id}", response_model=Carrinho,
            tags=["carrinho"])
def remover_item(carrinho_id: str, produto_id: int,
                 operador: str = Depends(exigir_operador)) -> Carrinho:
    return _serializar(carrinhos.remover(carrinho_id, produto_id))
