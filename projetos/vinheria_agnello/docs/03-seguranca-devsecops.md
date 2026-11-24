# Parte 3 — Comunicação Segura e DevSecOps

> Objetivo: *definir como os microsserviços trocam informações (REST/HTTP + JWT), implementar
> autenticação e usar Wireshark para mostrar o que acontece sem segurança.*

## 1. Como os serviços conversam

**REST sobre HTTPS**, em três camadas de proteção (defesa em profundidade):

| Trecho | Transporte | Identidade de quem chama | Autorização |
|---|---|---|---|
| PDV / navegador → **gateway** | TLS 1.2/1.3 (cert. `api.vinheria.local`) | — | — |
| gateway → serviços | **mTLS** (o gateway apresenta certificado) | certificado X.509 da CA interna | — |
| PDV → **carrinho** (via gateway) | TLS + mTLS | **HTTP Basic** do operador (senha via Docker secret) | rotas exigem operador |
| **carrinho → catálogo** | **mTLS** | certificado do carrinho | **JWT RS256** com escopo `estoque:reservar` |

```mermaid
sequenceDiagram
    participant P as PDV (operador)
    participant G as gateway (Nginx)
    participant R as carrinho-service
    participant C as catalogo-service
    P->>G: POST /api/carrinho/carrinhos/{id}/itens<br/>TLS 1.3 + Authorization: Basic
    G->>R: mTLS (cert do gateway) + X-Request-ID
    R->>R: valida Basic (tempo constante, anti-força-bruta)
    R->>C: GET /produtos/4 (mTLS)
    R->>R: assina JWT RS256 (iss, aud, scope, exp=60s, jti)
    R->>C: POST /produtos/4/reservas<br/>Authorization: Bearer <JWT>
    C->>C: valida assinatura, iss, aud, exp, escopo, jti (anti-replay)
    C-->>R: 201 reserva
    R-->>P: 201 carrinho atualizado
```

### Por que JWT **RS256** (assimétrico)?

O carrinho **assina** com a chave privada, que só existe no volume dele. O catálogo **verifica** com a
chave pública. Se o catálogo for comprometido, o atacante **não consegue emitir tokens**, o que não
acontece com HS256 (segredo compartilhado).

### Validações do token no catálogo ([`seguranca.py`](../services/catalogo-service/app/seguranca.py))

| Ataque | Defesa | Teste |
|---|---|---|
| `alg: none` | `algorithms=["RS256"]` | `test_tokens_invalidos_sao_rejeitados[alg-none]` |
| Confusão de algoritmo (HS256 assinado com a chave pública) | idem | `[confusao-de-algoritmo]` |
| Token de outro serviço/emissor | `aud` e `iss` obrigatórios | `[audiencia-errada]`, `[emissor-errado]` |
| Token expirado / roubado e guardado | `exp` de 60 s | `[expirado]` |
| **Replay** (reenviar token capturado) | `jti` de uso único | `test_replay_do_mesmo_token_e_bloqueado` |
| Escalada de privilégio | escopo por operação → **403** | `test_escopo_insuficiente_retorna_403` |
| Payload adulterado | assinatura RSA | `python -m app.diagnostico jwt-adulterado` |

## 2. Wireshark: o que acontece sem segurança

```bash
bash scripts/demo-wireshark.sh
```

O script sobe um **gateway inseguro** (perfil `demo-inseguro`, HTTP puro), captura o **mesmo fluxo de
compra** em HTTP e em HTTPS e grava `capturas/01-sem-tls-http.pcap` e `capturas/02-com-tls-https.pcap`.
Resultado real:

```
== O que o atacante lê na captura SEM TLS ==
  Cabeçalho capturado : Authorization: Basic b3BlcmFkb3I6QWduZWxsb0BMYWIyMDI2
  Base64 decodificado : operador:Agnello@Lab2026
  Corpo da requisição : {"produto_id":5,"quantidade":1}
  Resposta (trecho)   : {"id":"1cb369df9582","operador":"operador"

== O que o atacante lê na captura COM TLS ==
  Ocorrências de 'Authorization' : 0
  Ocorrências da senha           : 0
  Nome visível no SNI do ClientHello: api.vinheria.local
```

**No Wireshark:**

1. Abra `01-sem-tls-http.pcap` → filtro `http` → clique no `POST` → *Hypertext Transfer Protocol* →
   **Authorization: Basic …**. O Wireshark já mostra a *Credentials* decodificada (**captura de tela 1**).
2. *Analyze → Follow → HTTP Stream*: pedido, JSON e resposta inteiros, em texto claro (**captura 2**).
3. Abra `02-com-tls-https.pcap` → filtro `tls` → só aparecem *Client Hello*, *Server Hello* e
   **Application Data** cifrado (**captura 3**). Note que o **SNI** ainda revela o nome do servidor
   (é isso que o ECH, *Encrypted Client Hello*, resolve).
4. Na captura **sem TLS**, filtre `tcp.port == 8443`: mesmo no modo inseguro, o trecho gateway → carrinho
   é **TLS** (mTLS interno). Só o "último trecho" ficou exposto.

**Ao vivo no Windows:** Wireshark na interface *Adapter for loopback traffic capture*, filtro
`tcp.port == 8881`, e acesse `http://localhost:8881/api/catalogo/produtos`.

> **Lição:** HTTP Basic é só **Base64**, uma codificação e não uma criptografia. Sem TLS, qualquer
> pessoa na mesma rede (Wi-Fi da loja, switch espelhado, roteador comprometido) lê a senha do operador e
> os dados do pedido, e ainda pode **reutilizar** a credencial.

## 3. Controles de DevSecOps aplicados

| Camada | Controle |
|---|---|
| **Pipeline** | gitleaks bloqueia segredos; Trivy aponta CVEs em dependências e imagens; hadolint/shellcheck; testes de segurança no `pytest` |
| **Achado real** | o Trivy encontrou **CVE crítica de *authentication bypass* no PyJWT 2.10.1** e CVE crítica no Nginx 1.28. Ambas corrigidas (PyJWT 2.15.1, Nginx 1.30) e documentadas no histórico do Git |
| **Segredos** | nada no Git: CA, certificados, chaves JWT e TSIG gerados no 1º `up` (`pki-init`); senha do operador via **Docker secret**; cada serviço monta **só** a sua pasta da PKI (`volume.subpath`) com permissão 0400 |
| **Containers** | usuário não-root (10001), `cap_drop: ALL`, `no-new-privileges`, FS somente leitura, *healthchecks*, limite de log |
| **Rede** | só o gateway é publicado no host; LAN sem NAT; DNS sem recursão e com DDNS apenas via TSIG |
| **TLS** | TLS 1.2/1.3 apenas (1.1 recusado, testado), cifras AEAD/ECDHE, HSTS, `server_tokens off` |
| **Aplicação** | Basic com comparação em tempo constante + bloqueio após 5 falhas/min (429); limite de taxa no gateway; gateway só permite `GET` no catálogo (reservas são internas) |
| **Rastreabilidade** | `X-Request-ID` propagado gateway → carrinho → catálogo e logs JSON |

## 4. Próximos passos (produção)

* Trocar HTTP Basic por **OAuth 2.0 / OIDC** (ex.: Keycloak, Entra ID) com tokens de curta duração.
* Gerenciar certificados com **cert-manager / Vault PKI** (rotação automática) em vez de uma CA local.
* *Service mesh* (Istio/Linkerd) para mTLS transparente e políticas de autorização.
* Assinar imagens (cosign) e gerar SBOM no pipeline; política "sem CVE crítica" bloqueando o deploy.
