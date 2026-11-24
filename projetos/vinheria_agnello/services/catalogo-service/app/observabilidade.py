"""Logs estruturados (JSON) e propagacao do X-Request-ID entre servicos."""

from __future__ import annotations

import json
import logging
import sys
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request


class FormatadorJSON(logging.Formatter):
    def __init__(self, servico: str) -> None:
        super().__init__()
        self.servico = servico

    def format(self, record: logging.LogRecord) -> str:
        evento = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)) + "Z",
            "nivel": record.levelname,
            "servico": self.servico,
            "msg": record.getMessage(),
        }
        evento.update(getattr(record, "extra_campos", {}))
        return json.dumps(evento, ensure_ascii=False)


def configurar_logs(servico: str) -> logging.Logger:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(FormatadorJSON(servico))
    logger = logging.getLogger(servico)
    logger.handlers = [handler]
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


class MiddlewareRequisicao(BaseHTTPMiddleware):
    def __init__(self, app, logger: logging.Logger) -> None:
        super().__init__(app)
        self.logger = logger

    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        request.state.request_id = request_id
        inicio = time.perf_counter()
        resposta = await call_next(request)
        resposta.headers["X-Request-ID"] = request_id
        if request.url.path != "/health":
            self.logger.info(
                "requisicao",
                extra={
                    "extra_campos": {
                        "request_id": request_id,
                        "metodo": request.method,
                        "caminho": request.url.path,
                        "status": resposta.status_code,
                        "duracao_ms": round((time.perf_counter() - inicio) * 1000, 1),
                        "cliente": request.client.host if request.client else None,
                    }
                },
            )
        return resposta
