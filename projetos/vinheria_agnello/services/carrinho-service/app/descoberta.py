"""Service discovery via DNS (registro SRV, RFC 2782).

O carrinho NAO tem o endereco do catalogo fixo no codigo: ele pergunta ao DNS
"onde atende o _catalogo._tcp.vinheria.local?" e recebe host + porta. O host,
por sua vez, foi registrado automaticamente pelo DHCP (DDNS). Se o DNS falhar,
usa a URL padrao configurada (degradacao controlada).
"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from urllib.parse import urlparse

import dns.exception
import dns.resolver


@dataclass(frozen=True)
class Destino:
    host: str
    porta: int
    origem: str  # "dns-srv" ou "url-padrao"

    @property
    def url_base(self) -> str:
        return f"https://{self.host}:{self.porta}"


class DescobertaServico:
    def __init__(self, registro_srv: str | None, url_padrao: str, ttl_cache_s: int = 30) -> None:
        self.registro_srv = registro_srv
        self.url_padrao = url_padrao
        self.ttl_cache_s = ttl_cache_s
        self._cache: tuple[float, Destino] | None = None
        self._lock = threading.Lock()

    def _padrao(self) -> Destino:
        url = urlparse(self.url_padrao)
        return Destino(url.hostname or "localhost", url.port or 443, "url-padrao")

    def _consultar_srv(self) -> Destino:
        respostas = dns.resolver.resolve(self.registro_srv, "SRV", lifetime=2.0)
        melhor = sorted(respostas, key=lambda r: (r.priority, -r.weight))[0]
        return Destino(str(melhor.target).rstrip("."), int(melhor.port), "dns-srv")

    def resolver(self, forcar: bool = False) -> Destino:
        with self._lock:
            if not forcar and self._cache and self._cache[0] > time.monotonic():
                return self._cache[1]
            destino = self._padrao()
            if self.registro_srv:
                try:
                    destino = self._consultar_srv()
                except (dns.exception.DNSException, IndexError):
                    destino = self._padrao()
            self._cache = (time.monotonic() + self.ttl_cache_s, destino)
            return destino
