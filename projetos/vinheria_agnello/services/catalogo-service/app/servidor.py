"""Inicializa o Uvicorn com HTTPS e, opcionalmente, mTLS (certificado de cliente)."""

from __future__ import annotations

import os
import ssl

import uvicorn


def main() -> None:
    porta = int(os.getenv("PORTA", "8443"))
    cert = os.getenv("TLS_CERT_FILE")
    chave = os.getenv("TLS_KEY_FILE")
    ca = os.getenv("TLS_CA_FILE")
    exigir_cliente = os.getenv("TLS_CLIENT_AUTH", "required") == "required"

    opcoes: dict = {}
    if cert and chave:
        opcoes = {
            "ssl_certfile": cert,
            "ssl_keyfile": chave,
            "ssl_ca_certs": ca,
            "ssl_cert_reqs": ssl.CERT_REQUIRED if exigir_cliente else ssl.CERT_NONE,
        }

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",  # noqa: S104 - container isolado; exposicao controlada pelo gateway
        port=porta,
        server_header=False,
        access_log=False,
        proxy_headers=True,
        forwarded_allow_ips="10.50.0.10,10.50.0.11",
        **opcoes,
    )


if __name__ == "__main__":
    main()
