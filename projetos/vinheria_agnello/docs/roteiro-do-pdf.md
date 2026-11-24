# Roteiro do PDF de entrega

Estrutura sugerida, na ordem pedida pela atividade. Os itens **[cmd]** viram capturas de tela:
rode o comando no terminal e tire o print, ou use os arquivos gerados por
`bash scripts/coletar-evidencias.sh` (pasta `evidencias/<data>/`, numerados na mesma ordem).

> Nome do arquivo pedido no enunciado: `Nomecompleto_rm_turma_fase7_atividade`. O enunciado pede um
> **PDF**, mas o exemplo de nome termina em `.docx`. Confirme com o professor qual extensão enviar.

---

## Capa
Vinheria Agnello · Fase 7 · integrantes (nome + RM) · turma · link do repositório.

## 1. Descrição dos serviços e da infraestrutura simulada
* **Serviços escolhidos**: catalogo-service e carrinho-service (tabela da seção 1 de `docs/01-…`).
  Justificativa: são as duas telas do projeto anterior (`catalogo.jsp` e `carrinho.jsp`), e o carrinho
  depende do catálogo, o que exige comunicação real entre serviços.
* **Topologia**: diagrama da seção 2 de `docs/01-…` (o GitHub renderiza o Mermaid, então basta um print).
* **Plano de endereçamento** (tabela) e por que a infraestrutura usa IP fixo e os serviços usam DHCP.
* Equivalência com o Windows Server (tabela da seção 8).

## 2. Capturas de tela da configuração
**Rede**
1. [cmd] `docker compose ps` (todos *healthy*) → `evidencias/01-containers.txt`
2. [cmd] `docker network inspect vinheria-lan` + IP real de cada host → `02-rede-docker.txt`

**DHCP**
3. Trecho do `infra/dhcp/kea-dhcp4.conf`: pool, reservas, opções → `03-dhcp-configuracao.txt`
4. [cmd] `docker compose exec dhcp kea-leases` → `04-dhcp-leases.txt`
5. [cmd] logs DISCOVER/OFFER/REQUEST/ACK → `05-dhcp-logs.txt`

**DNS**
6. Arquivo de zona `infra/dns/zones/db.vinheria.local` (estático: SRV, TXT, infraestrutura)
7. [cmd] DDNS: BIND recebendo atualização assinada com TSIG → `06-ddns.txt`
8. [cmd] `docker compose exec dns dns-registros` (zona com os registros criados pelo DHCP) → `07-dns-zona.txt`
9. [cmd] `dig` a partir da estação e o `resolv.conf` vindo do DHCP → `08-dns-consultas.txt`

**Comunicação entre os serviços**
10. [cmd] Fluxo do carrinho + `/diagnostico/descoberta` (mostra `origem: dns-srv`) → `09-comunicacao.txt`

**Jenkins**
11. Job no Jenkins, Stage View verde, Console com `Deploy da Vinheria`, resultados JUnit (ver `docs/02-…`, seção "Capturas")

## 3. Fluxo de deploy
* Diagrama de estágios (seção 1 de `docs/02-…`) e a tabela "o que cada estágio faz".
* Pasta de publicação (árvore de `publicacao/`), `index.html` aberto no navegador e `deploy.log`.
* Rollback automático em caso de falha.
* GitHub Actions espelhando o mesmo pipeline (print da aba Actions).

## 4. Práticas de segurança aplicadas
* Diagrama de sequência (seção 1 de `docs/03-…`): Basic → mTLS → JWT RS256.
* Tabela de ataques ao JWT e defesas + [cmd] `python -m app.diagnostico` → `10-seguranca.txt`.
* **Wireshark**: as 3 capturas descritas na seção 2 de `docs/03-…` (senha legível em HTTP × nada legível em TLS).
* DevSecOps: o Trivy encontrou uma CVE **crítica** no PyJWT e no Nginx, e o pipeline levou à correção.
* Hardening dos containers e do DNS (TSIG, sem recursão).
* [cmd] Smoke test com 39 verificações verdes → `11-smoke-test.txt`.

## 5. Reflexão final: desafios e aprendizados
Use os problemas reais da seção 7 de `docs/01-…` como base. Rascunho para adaptar com as palavras do grupo:

> **Desafios.** Nosso maior desafio foi fazer o DHCP funcionar "de verdade" dentro de containers, já que o
> Docker normalmente distribui os IPs sozinho. Descobrimos com o tcpdump que a rede `internal` do Docker
> descartava o `DHCPDISCOVER`, que sai de `0.0.0.0` para broadcast, e que no Linux, ao remover o IP
> primário de uma interface, os endereços secundários são removidos junto. Também percebemos que o DNS
> dinâmico precisa de persistência: reiniciar o servidor DNS apagava os registros criados pelo DHCP.
> No pipeline, o modelo Docker-out-of-Docker do Jenkins nos obrigou a colocar as configurações dentro das
> imagens em vez de usar bind mounts.
>
> **Aprendizados.** Entendemos na prática o ciclo DORA do DHCP, as opções de escopo, as reservas e como o
> DHCP e o DNS se integram (DDNS com TSIG, como o "atualizações seguras" do Windows Server), além do uso do
> DNS para descoberta de serviços (SRV). A captura no Wireshark mostrou que HTTP Basic sem TLS entrega a
> senha a qualquer um na rede. E o scanner de vulnerabilidades do pipeline encontrou uma falha crítica real
> numa biblioteca de JWT que estávamos usando, o que mostrou o valor de automatizar a segurança
> (*shift-left*) em vez de deixá-la para o fim.
