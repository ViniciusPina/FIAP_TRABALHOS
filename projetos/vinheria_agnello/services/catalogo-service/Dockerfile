# syntax=docker/dockerfile:1
# =============================================================================
# catalogo-service - build multi-stage
#   deps      -> instala dependencias de producao num virtualenv
#   teste     -> lint (ruff) + testes (pytest) DENTRO do build
#   relatorios-> exporta o JUnit XML (docker build --target relatorios --output ...)
#   runtime   -> imagem final minima, usuario nao-root, sem ferramentas de dev
# =============================================================================
ARG PYTHON_IMAGE=python:3.12-slim-bookworm

FROM ${PYTHON_IMAGE} AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH=/opt/venv/bin:$PATH
WORKDIR /app

FROM base AS deps
RUN python -m venv /opt/venv
COPY requirements.txt .
RUN pip install -r requirements.txt

FROM deps AS teste
COPY requirements-dev.txt pyproject.toml ./
RUN pip install -r requirements-dev.txt
COPY app ./app
COPY tests ./tests
RUN mkdir -p /relatorios \
 && ruff check --output-format=full app tests \
 && pytest --junitxml=/relatorios/junit-catalogo-service.xml

FROM scratch AS relatorios
COPY --from=teste /relatorios/ /

FROM base AS runtime
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="catalogo-service" \
      org.opencontainers.image.description="Vinheria Agnello - catalogo de vinhos e estoque" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="https://github.com/ViniciusPina/FIAP_TRABALHOS"
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
COPY --from=deps /opt/venv /opt/venv
COPY app ./app
COPY healthcheck.py ./
ENV APP_VERSION=${APP_VERSION}
USER 10001:10001
EXPOSE 8443
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=10 \
  CMD ["python", "/app/healthcheck.py"]
CMD ["python", "-m", "app.servidor"]
