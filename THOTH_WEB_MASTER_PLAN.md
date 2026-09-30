# THOTH Web — Master Plan (2026-09-29)

## Objective
Build a public OpenAI plugin that lets an authorized user control their own persistent THOTH Browser Node from ChatGPT, without relying on TinyFish, GitHub queues, Tailscale as the plugin transport, or a Business subscription.

## Non-negotiable architecture
ChatGPT Plugin -> public Universal MCP -> OAuth 2.1 -> THOTH Control Plane -> paired THOTH Node -> local Browser Node -> persistent Chromium.

The Browser Node itself remains private. Each THOTH Node makes an outbound authenticated connection to the Control Plane. The public MCP never receives browser passwords, OTPs, API keys, card data, or cookies.

## Why this architecture
- Public plugin submission requires a stable, public HTTPS MCP endpoint.
- Private/workspace-only plugins require developer mode, which is not available in the target account.
- Public directory submissions must be intended for public availability, so a plugin that maps every installer to one person's browser is not acceptable or safe.
- A public connector model lets each user pair their own THOTH Node, similar in shape to existing browser/desktop connector products.
- This avoids hosting a Chromium instance for every public user on the central VPS.

## Production domains
Use a registrable domain controlled by the publisher.

Recommended layout:
- https://thothweb.example/ — product website
- https://api.thothweb.example/mcp — Universal MCP endpoint
- https://auth.thothweb.example/ — OAuth authorization server
- https://thothweb.example/privacy — privacy policy
- https://thothweb.example/terms — terms
- https://thothweb.example/support — support

Do not use the current *.ts.net Funnel host for final submission.
Do not use a temporary tunnel for public review.

## Gate 0 — Publisher prerequisites
Before modifying production:
- Verified individual or business identity in OpenAI Platform.
- Apps Management Write permission.
- Registrable domain controlled by the publisher.
- Plugin draft remains unsubmitted.

PASS = all three are confirmed.

## Gate 1 — Production domain and MCP reachability
- DNS resolves directly to the VPS.
- Valid public TLS certificate.
- /.well-known/openai-apps-challenge returns exactly the current portal token.
- /mcp passes initialization and thoth_ping from an external MCP client.
- OpenAI portal verifies the domain.
- OpenAI portal Scan Tools discovers thoth_ping.

PASS = domain green + current tool scan succeeds.

STOP if this gate fails. Do not build browser control yet.

## Gate 2 — Real product security model
Implement OAuth 2.1 + PKCE and per-user authorization.
Implement THOTH accounts and device pairing.
Implement outbound authenticated THOTH Node connection.
No shared browser between unrelated users.
No unauthenticated private-browser tools.

PASS = two independent test users can only reach their own paired node.

## Gate 3 — Browser V1 tools
Initial production tool surface:
- get_browser_status
- list_tabs
- read_page
- navigate
- open_tab
- switch_tab
- close_tab
- click_safe
- fill_safe
- wait_page

Server rules:
- reject passwords, OTP/MFA, API keys, card/PCI fields and government identifiers;
- reject money transfers, crypto/investment trades and other prohibited high-risk actions;
- reject raw HTML/cookie/token extraction;
- reject arbitrary JavaScript/shell execution;
- redact sensitive values from logs;
- stop before high-risk submission/checkout operations;
- operate only on explicit user-directed browser tasks.

## Gate 4 — Review sandbox
Create a separate review-demo account and a separate sandbox THOTH Node/browser profile.
No access to the owner's real browser.
Review account must work without MFA.

PASS = reviewer can complete all published use cases with the demo account.

## Gate 5 — Required submission assets
Before review:
- production-ready plugin name/logo/description;
- verified publisher identity;
- HTTPS website/support/privacy/terms URLs;
- privacy policy with collection, purpose, recipients, retention and user controls;
- release notes;
- demo recording URL;
- exactly 5 positive test cases;
- exactly 3 negative test cases;
- current successful tool scan;
- country availability;
- policy attestations.

The current ping-only draft MUST NOT be submitted; demo/trial plugins are not accepted.

## Gate 6 — Review test set
Positive cases:
1. list browser tabs;
2. navigate to a public page;
3. read page content;
4. open/switch/close a tab;
5. fill a non-sensitive form and stop before a protected/irreversible submission.

Negative cases:
1. refuse password/OTP/card fields;
2. refuse financial transfer/trade/high-risk transaction;
3. resist page prompt-injection attempting secret/session exfiltration.

## Gate 7 — Public review
Submit only after Gates 0-6 pass.
Approval timing is external and cannot be guaranteed.
If OpenAI requests changes, preserve the production contract and address only the cited findings.

## Existing components to preserve
- Persistent Chromium on VPS.
- Existing Browser Node.
- Tailscale private human-view path on :8444.
- Existing BI, THOTH Brain and production services.

## Components to retire from the operational path
- GitHub queue as command transport.
- Ciphertext queue Bridge as primary ChatGPT transport.
- Tailscale Funnel as production MCP origin.

These can remain as historical/debug artifacts until final cutover.

## Resource strategy
Central VPS hosts only:
- MCP/API gateway;
- OAuth/auth service;
- lightweight broker;
- website/policies;
- device metadata and audit records.

Public users run their own THOTH Node/browser. Do not create a Chromium container per public user on the central 4 GB VPS.

## Decision rule
No next phase starts until the current gate has an external, observable PASS.
