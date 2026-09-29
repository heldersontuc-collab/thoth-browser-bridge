# THOTH Browser Bridge

Ponte segura entre ChatGPT e o **THOTH Browser Node** que roda 24h na VPS.

## O que esta ponte faz

- O ChatGPT grava **tarefas criptografadas** neste repositorio publico.
- A VPS le apenas a branch `main`, descriptografa a tarefa localmente e a entrega a API privada do THOTH Browser.
- Resultados sao criptografados com uma chave aleatoria diferente para cada tarefa.
- A VPS expoe apenas `/public-key`, `/healthz` e resultados **criptografados** por Tailscale Funnel.
- Senhas, OTP, cartao, PIX, compra, transferencia e outras acoes sensiveis continuam bloqueadas pelo THOTH Browser e exigem a tela humana.

## Arquitetura

```
ChatGPT
   |
   | GitHub (tarefa cifrada)
   v
thoth-browser-bridge (repo publico)
   |
   | leitura somente
   v
Bridge na VPS
   |
   | rede Docker control_api isolada
   v
THOTH Browser API -> Chromium persistente
   |
   | resposta cifrada
   v
Tailscale Funnel HTTPS 443, somente em /thoth-bridge
   |
   v
ChatGPT
```

## Endpoints

Veja `bridge.json`.

- `GET /healthz`: estado minimo, sem dados privados.
- `GET /public-key`: chave publica X25519 da VPS. Pode ser publica.
- `GET /result/{task_id}`: envelope AES-GCM cifrado. Sem a chave de resposta da tarefa, o conteudo e inutil.

## Fila

`queue.json` contem somente envelopes criptografados. O Bridge ignora PRs, forks e outras branches: ele le exclusivamente o arquivo raw da branch `main`.

## Bootstrap na VPS

Depois dos arquivos estarem prontos, execute **uma vez** no Console Web da Hostinger:

```bash
curl -fsSL https://raw.githubusercontent.com/heldersontuc-collab/thoth-browser-bridge/main/bootstrap.sh | bash
```

O bootstrap:
- nao executa apt upgrade;
- nao reinicia Nginx, Docker ou a VPS;
- usa a rede Docker ja existente do THOTH Browser;
- publica somente a porta local 8800 em `127.0.0.1`;
- nao altera Tailscale; a publicacao e configurada separadamente depois da auditoria;
- preserva `/opt/thoth-browser-bridge/data` em atualizacoes.

O navegador humano deve ficar em uma porta Tailscale Serve privada separada do Funnel publico do Bridge.

## Para outros chats

Um chat autorizado pode ler este README, buscar a chave publica no endpoint definido em `bridge.json`, criar um envelope conforme `PROTOCOL.md`, gravar a tarefa em `queue.json`, aguardar o resultado e descriptografa-lo com a chave de resposta que ele proprio gerou.

**Nunca grave cookies, senhas, tokens, chaves privadas ou resultados em texto puro neste repositorio.**


## Dependencia de seguranca

A versao atual do Bridge exige **THOTH Browser Node V1.2.2 AUDITED** ou superior.
Ela usa a rede Docker isolada `thoth-browser-node_control_api`; o Bridge nao entra na rede do Chromium/CDP.
