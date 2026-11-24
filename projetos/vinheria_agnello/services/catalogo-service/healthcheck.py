"""HEALTHCHECK do container: chama /health via HTTPS apresentando o proprio
certificado (o servico exige mTLS ate para a checagem de saude)."""

import os
import ssl
import sys
import urllib.request

porta = os.getenv("PORTA", "8443")
cert, chave, ca = (os.getenv(v) for v in ("TLS_CERT_FILE", "TLS_KEY_FILE", "TLS_CA_FILE"))

if cert and chave:
    contexto = ssl.create_default_context(cafile=ca)
    contexto.load_cert_chain(cert, chave)
    url = f"https://localhost:{porta}/health"
else:
    contexto = None
    url = f"http://localhost:{porta}/health"

try:
    with urllib.request.urlopen(url, context=contexto, timeout=3) as resposta:  # noqa: S310
        sys.exit(0 if resposta.status == 200 else 1)
except Exception as erro:  # noqa: BLE001
    print(f"healthcheck falhou: {erro}", file=sys.stderr)
    sys.exit(1)
