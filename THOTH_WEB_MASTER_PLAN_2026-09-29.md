# THOTH Web — Rota Mestre validada (2026-09-29)

## Objetivo

Entregar um plugin público THOTH Web no diretório universal do ChatGPT/Codex que, após autenticação do usuário, opere um Browser Node persistente controlado pelo próprio usuário. O Browser Node do Helderson continuará na VPS atual e o acesso visual humano continuará privado via Tailscale.

## Decisões congeladas

1. Não usar GitHub como fila operacional.
2. Não usar Tailscale `*.ts.net` como domínio de produção do plugin.
3. Não usar DuckDNS ou outro subdomínio compartilhado como rota de produção de alta confiança.
4. Não submeter o `thoth_ping` como produto final: ele existe somente como sonda técnica.
5. Não conectar ferramentas privadas ou de escrita sem OAuth 2.1.
6. Não expor CDP/Chromium ao público.
7. Não processar senha, OTP/MFA, API key, cartão/PCI, PHI ou identificadores governamentais.
8. Não oferecer submit/pagamento/transferência/compra/destruição na V1.
9. Todo avanço depende de um gate externo comprovado antes do próximo sprint.

## Arquitetura de produção

```
ChatGPT Work / Codex
        |
        | Plugin público THOTH Web
        | OAuth 2.1 + PKCE
        v
https://mcp.<dominio-proprio>/mcp
        |
        | Nginx HTTPS
        v
THOTH Web MCP (localhost)
        |
        | autorização por usuário
        v
Browser Node pareado
        |
        v
Chromium persistente

Usuário humano -> Tailscale privado -> tela remota do Chromium
```

### Domínios

- `https://<dominio-proprio>/`: site institucional
- `https://<dominio-proprio>/privacy`: privacidade
- `https://<dominio-proprio>/terms`: termos
- `https://<dominio-proprio>/support`: suporte
- `https://mcp.<dominio-proprio>/mcp`: MCP de produção
- `https://auth.<dominio-proprio>/`: autorização OAuth/OIDC

## Gate 0 — Pré-requisitos da OpenAI

Antes de alterar produção:

- projeto OpenAI com data residency global (projetos EU não podem submeter MCP no momento);
- identidade individual ou empresarial verificada;
- Apps Management / `api.apps.write`;
- draft do plugin acessível no portal.

Se algum item falhar, parar.

## Gate 1 — Domínio próprio

Adquirir um domínio registrável sob controle do usuário e apontar os subdomínios necessários para a VPS.

Critério de sucesso:

- DNS A/AAAA correto;
- HTTPS válido;
- Nginx preserva todos os serviços existentes;
- `/.well-known/openai-apps-challenge` retorna somente o token;
- portal OpenAI marca Domain verified;
- portal consegue Scan Tools e encontra `thoth_ping`.

Se Verify Domain ou Scan Tools falhar, parar e corrigir/acionar suporte. Não construir OAuth nem Browser tools antes disso.

## Gate 2 — OAuth 2.1 compatível com MCP

Usar implementação self-hosted madura, não OAuth artesanal.

Candidato preferencial: Django + Django OAuth Toolkit 3.4.x+, pois a versão atual declara suporte ao papel de Authorization Server exigido pelo MCP, PKCE obrigatório por padrão, RFC 8414, RFC 9728, RFC 8707, DCR/CIMD opcionais e OIDC/UserInfo.

Escopos iniciais:

- `browser:read`
- `browser:control`

Contas:

- usuário real;
- `review-demo` com senha, sem MFA, dados fictícios e Browser Node isolado.

Critério de sucesso:

- ChatGPT descobre protected-resource metadata;
- Authorization Code + PKCE S256 completa;
- token contém/obedece audience/resource;
- MCP rejeita token inválido, expirado ou sem escopo;
- review-demo conecta sem SMS/email/MFA.

## Gate 3 — Ferramentas read-only

Somente após OAuth:

- `get_profile`
- `browser_status`
- `list_tabs`
- `read_page`

`read_page` devolve apenas conteúdo visível e necessário. Nunca HTML bruto, cookies, headers, hidden values ou valores de inputs.

Critério de sucesso:

- leitura do Browser Node real;
- resposta sem secrets/PII desnecessária;
- scanner de tools da OpenAI sem erro.

## Gate 4 — Controle seguro

Adicionar apenas ações cuja fronteira possa ser auditada:

- `open_url`: abre URL em nova aba;
- `switch_tab`;
- `close_tab` (destructiveHint=true);
- `click_safe`: somente controles classificados como navegação/ação reversível;
- `fill_safe`: preenche sem enviar e bloqueia campos sensíveis.

Não expor na V1:

- shell/terminal;
- JavaScript arbitrário;
- HTML bruto;
- cookies/tokens;
- screenshot irrestrito;
- Enter/press genérico;
- submit_form;
- checkout/pagamento/PIX/transferência;
- delete/revoke;
- qualquer ferramenta genérica executor.

## Gate 5 — Proteções de dados

Bloqueio e/ou redação obrigatória para:

- senhas/passcodes;
- MFA/OTP;
- API keys/tokens;
- PCI/cartão/CVV;
- PHI;
- CPF/CNPJ e outros identificadores governamentais quando presentes em conteúdo processado;
- hidden inputs e valores de formulários.

Logs: sem conteúdo bruto de páginas, sem valores preenchidos, sem tokens e sem prompts completos.

## Gate 6 — Produto para revisão

Antes de Submit for review:

- produto completo, não demo;
- identidade do publisher verificada;
- website HTTPS;
- support URL;
- privacy policy;
- terms;
- logo/listing;
- starter prompts;
- 5 testes positivos;
- 3 testes negativos;
- release notes;
- demo-recording URL;
- tool scan atual;
- domain verified;
- credenciais review-demo;
- disponibilidade de países.

## Gate 7 — Review e publicação

A aprovação final é uma decisão externa da OpenAI e não pode ser garantida antecipadamente.

Se rejeitado:
- usar o feedback da revisão;
- corrigir;
- scan novamente;
- resubmeter a mesma versão/draft conforme permitido.

## Posicionamento do produto

THOTH Web não será apresentado como conector não oficial de serviços terceiros.

Proposta:

"Opera um navegador persistente autorizado pelo usuário para leitura, navegação e preparação de interações não sensíveis. Mantém credenciais e ações sensíveis fora das ferramentas do modelo."

A V1 deve respeitar termos dos sites acessados e não contornar APIs, rate limits ou controles de acesso.

## Estado já provado

- Browser Node persistente na VPS: OK.
- tela humana privada via Tailscale: OK.
- MCP Streamable HTTP local: OK.
- `thoth_ping -> PONG`: OK local.
- MCP público por HTTPS/Tailscale: OK em cliente MCP externo.
- draft `thoth-web` criado no portal OpenAI: OK.
- verificação de domínio em `*.ts.net`: falha no portal apesar do challenge responder corretamente externamente.

## Próxima ação autorizada

Não alterar a VPS.

Primeiro:
1. confirmar Gate 0;
2. escolher/adquirir domínio próprio;
3. somente depois configurar o domínio de produção e repetir Domain Verification + Scan Tools.

Nenhum desenvolvimento de OAuth ou Browser tools antes de Gate 1 ficar verde.
