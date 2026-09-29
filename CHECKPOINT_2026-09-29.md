# THOTH Browser Bridge — CHECKPOINT 2026-09-29

## Objetivo original
Permitir que um chat do ChatGPT opere o mesmo Chromium persistente que roda 24h na VPS, preservando as sessoes humanas e exigindo intervencao manual para senha, 2FA e pagamento.

## Estado comprovado
- Chromium 24h na VPS: OK.
- Acesso humano via Tailscale Serve privado em 8444: OK.
- Browser nao acessivel publicamente: OK.
- Bridge local em 127.0.0.1:8800: OK.
- Bridge /healthz: OK.
- Bridge /readyz: queue_ok=true e browser_api_ok=true.
- Bridge conectado a API autenticada do Browser Node: OK.
- GitHub conectado ao ChatGPT: OK para codigo/configuracao.
- Funnel publico somente para /thoth-bridge: OK.

## Objetivo ainda NAO atingido
O chat atual nao possui um canal suportado para enviar comandos arbitrarios diretamente ao Bridge da VPS nem para ingressar na Tailnet. O GitHub connector permite codigo/configuracao, mas bloqueia payloads opacos/ciphertext arbitrarios usados como fila operacional.

Portanto:
ChatGPT -> VPS Browser control: NAO COMPROVADO / NAO DISPONIVEL COM AS FERRAMENTAS ATUAIS.

## Regra para qualquer retomada
Nao alterar Browser Node, Docker, Tailscale ou Bridge antes de provar primeiro um canal ChatGPT -> VPS com um teste minimo e reversivel.

Criterio de entrada:
1. ChatGPT envia um comando de teste simples para a VPS.
2. VPS devolve a resposta ao mesmo chat.
3. Nenhum comando manual do operador e necessario no meio.

Somente depois disso integrar esse canal ao Chromium existente.

## Preservar
Nao remover ou reconstruir o Browser Node atual. O navegador 24h privado e o acesso pelo celular estao funcionais e devem permanecer congelados ate existir um transporte realmente suportado.
