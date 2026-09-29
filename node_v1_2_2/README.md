# THOTH Browser Node V1.2.2 AUDITED

Use **only** `upgrade_v1_2_2.py` through the root `deploy_audited_stack.sh`.

The old `patch.part01..05` files are retained only as audit history. They are **not** the current deployment path and must not be applied manually.

The current upgrader was tested locally against the original V1.2.1 ZIP, including a VPS state where the Caddy `/api/healthz` rewrite had already been hot-fixed. It is idempotent: a second run makes no additional source changes.

Security corrections in the current upgrader include:

- card/password/OTP/PIX/bank field detection using type, autocomplete, label, name, id, placeholder and aria-label;
- camelCase and underscore/hyphen normalization such as `cardNumber`;
- sensitive keypress bypass blocked;
- fill values always redacted from event logs;
- historical event details redacted when read;
- raw HTML extraction disabled;
- Browser Node version set to 1.2.2;
- Caddy health rewrite made canonical;
- dedicated `thoth-browser-node_control_api` network added to the API so the public Bridge does not join the Chromium/CDP network.

The audited deployment script stages and compiles the upgrade before changing the live files, creates a reversible backup, recreates only API/MCP, keeps Chromium running, validates Playwright shared-browser connectivity, validates the Bridge `/readyz`, and only then publishes the encrypted Bridge path.
