"""Cliente HTTP do catalogo-service: HTTPS + mTLS + JWT + retries + timeout."""

from __future__ import annotations

import ssl

import httpx

from .descoberta import DescobertaServico
from .token_servico import EmissorToken


class ErroCatalogo(Exception):
    def __init__(self, status: int, detalhe: str) -> None:
        super().__init__(detalhe)
        self.status = status
        self.detalhe = detalhe


class ClienteCatalogo:
    def __init__(
        self,
        descoberta: DescobertaServico,
        emissor: EmissorToken,
        ca: str,
        cert: str,
        chave: str,
        timeout_s: float = 3.0,
    ) -> None:
        self.descoberta = descoberta
        self.emissor = emissor
        contexto = ssl.create_default_context(cafile=ca)       # confia SO na CA interna
        contexto.minimum_version = ssl.TLSVersion.TLSv1_2
        contexto.load_cert_chain(cert, chave)                  # identidade do carrinho (mTLS)
        self._http = httpx.Client(
            timeout=timeout_s,
            transport=httpx.HTTPTransport(verify=contexto, retries=2),
        )

    def _requisitar(self, metodo: str, caminho: str, request_id: str, **kwargs) -> dict:
        destino = self.descoberta.resolver()
        headers = kwargs.pop("headers", {})
        headers["X-Request-ID"] = request_id
        try:
            resposta = self._http.request(
                metodo, f"{destino.url_base}{caminho}", headers=headers, **kwargs
            )
        except httpx.HTTPError as exc:
            self.descoberta.resolver(forcar=True)  # o servico pode ter mudado de endereco
            raise ErroCatalogo(503, f"catalogo indisponivel: {type(exc).__name__}") from exc

        if resposta.status_code in (404, 409, 422):
            raise ErroCatalogo(resposta.status_code, resposta.json().get("detail", "erro"))
        if resposta.status_code in (401, 403):
            raise ErroCatalogo(502, "catalogo recusou a credencial do carrinho-service")
        if resposta.status_code >= 400:
            raise ErroCatalogo(502, f"erro inesperado do catalogo ({resposta.status_code})")
        return resposta.json()

    def obter_produto(self, produto_id: int, request_id: str) -> dict:
        return self._requisitar("GET", f"/produtos/{produto_id}", request_id)

    def reservar(self, produto_id: int, quantidade: int, request_id: str) -> dict:
        token = self.emissor.emitir("estoque:reservar")
        return self._requisitar(
            "POST",
            f"/produtos/{produto_id}/reservas",
            request_id,
            json={"quantidade": quantidade},
            headers={"Authorization": f"Bearer {token}"},
        )
