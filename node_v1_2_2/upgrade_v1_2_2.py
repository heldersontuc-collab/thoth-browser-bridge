#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path.cwd()


def fail(msg: str) -> None:
    raise SystemExit(f"V1.2.2 upgrade aborted: {msg}")


def read(rel: str) -> str:
    p = ROOT / rel
    if not p.is_file():
        fail(f"missing expected file: {rel}")
    return p.read_text(encoding="utf-8")


def write(rel: str, text: str) -> None:
    (ROOT / rel).write_text(text, encoding="utf-8")


def replace_once(rel: str, old: str, new: str, label: str) -> None:
    s = read(rel)
    if new in s:
        print(f"[OK] {label}: already applied")
        return
    if old not in s:
        fail(f"{label}: expected source block not found in {rel}")
    write(rel, s.replace(old, new, 1))
    print(f"[OK] {label}")


secret_block = """_SECRET_AUTOCOMPLETE = {
    "current-password",
    "new-password",
    "one-time-code",
    "cc-number",
    "cc-csc",
    "cc-exp",
    "cc-exp-month",
    "cc-exp-year",
}
"""
sensitive_block = secret_block + """
_SENSITIVE_FIELD_WORDS = re.compile(
    r"\b(password|passcode|senha|pin|otp|one[ -]?time|verification code|codigo de verificacao|"
    r"card(?: number)?|credit card|debit card|cart[aã]o|numero do cart[aã]o|cvv|cvc|security code|"
    r"expiry|expiration|validade|pix|transfer|bank account|account number|routing|iban|swift|"
    r"cpf|cnpj|social security|ssn)\b",
    re.I,
)
"""
replace_once("app/browser_manager.py", secret_block, sensitive_block, "sensitive field vocabulary")

old_meta = """    async def _target_meta(self, loc: Locator) -> dict[str, Any]:
        return await loc.evaluate(\"\"\"el => ({
            tag:(el.tagName||'').toLowerCase(),
            type:(el.getAttribute('type')||'').toLowerCase(),
            autocomplete:(el.getAttribute('autocomplete')||'').toLowerCase(),
            text:(el.innerText||el.value||el.getAttribute('aria-label')||'').trim().slice(0,240),
            href:el.href||'',
            form_action:(el.form && el.form.action)||'',
            form_method:((el.form && el.form.method)||'').toLowerCase()
        })\"\"\")
 
    def _human_only(self, meta: dict[str, Any]) -> bool:
        text = meta.get("text", "")
        href = meta.get("href", "")
        action = meta.get("form_action", "")
        ac = meta.get("autocomplete", "")
        return bool(
            meta.get("type") in _SECRET_TYPES
            or ac in _SECRET_AUTOCOMPLETE
            or _HUMAN_ONLY_WORDS.search(text)
            or _HUMAN_ONLY_HREF.search(href)
            or _HUMAN_ONLY_HREF.search(action)
        )

    def _needs_confirmation(self, meta: dict[str, Any]) -> bool:
        text = meta.get("text", "")
        href = meta.get("href", "")
        return bool(
            meta.get("type") == "submit"
            or _DANGEROUS_WORDS.search(text)
            or _DANGEROUS_HREF.search(href)
            or (meta.get("form_action") and meta.get("form_method") not in {"", "get"})
        )
"""
new_meta = """    async def _target_meta(self, loc: Locator) -> dict[str, Any]:
        return await loc.evaluate(\"\"\"el => {
            const labelFor = (node) => {
              if (node.id) {
                const lab = document.querySelector(\`label[for="\${CSS.escape(node.id)}"]\`);
                if (lab) return (lab.innerText || lab.textContent || '').trim();
              }
              const parent = node.closest('label');
              return parent ? (parent.innerText || parent.textContent || '').trim() : '';
            };
            return {
              tag:(el.tagName||'').toLowerCase(),
              type:(el.getAttribute('type')||'').toLowerCase(),
              autocomplete:(el.getAttribute('autocomplete')||'').toLowerCase(),
              text:(el.innerText||'').trim().slice(0,240),
              aria_label:(el.getAttribute('aria-label')||'').trim().slice(0,240),
              name:(el.getAttribute('name')||'').trim().slice(0,240),
              id:(el.id||'').trim().slice(0,240),
              placeholder:(el.getAttribute('placeholder')||'').trim().slice(0,240),
              label:labelFor(el).slice(0,240),
              href:el.href||'',
              form_action:(el.form && el.form.action)||'',
              form_method:((el.form && el.form.method)||'').toLowerCase()
            };
        }\"\"\")

    def _meta_descriptors(self, meta: dict[str, Any]) -> str:
        value = " ".join(
            str(meta.get(k, "") or "")
            for k in ("text", "aria_label", "name", "id", "placeholder", "label")
        )
        value = re.sub(r"([a-z])([A-Z])", r"\\1 \\2", value)
        return re.sub(r"[_-]+", " ", value)

    def _human_only(self, meta: dict[str, Any]) -> bool:
        descriptors = self._meta_descriptors(meta)
        href = str(meta.get("href", "") or "")
        action = str(meta.get("form_action", "") or "")
        ac = str(meta.get("autocomplete", "") or "").lower()
        return bool(
            str(meta.get("type", "") or "").lower() in _SECRET_TYPES
            or ac in _SECRET_AUTOCOMPLETE
            or _SENSITIVE_FIELD_WORDS.search(descriptors)
            or _HUMAN_ONLY_WORDS.search(descriptors)
            or _HUMAN_ONLY_HREF.search(href)
            or _HUMAN_ONLY_HREF.search(action)
        )

    def _needs_confirmation(self, meta: dict[str, Any]) -> bool:
        descriptors = self._meta_descriptors(meta)
        href = str(meta.get("href", "") or "")
        return bool(
            str(meta.get("type", "") or "").lower() == "submit"
            or _DANGEROUS_WORDS.search(descriptors)
            or _DANGEROUS_HREF.search(href)
            or (meta.get("form_action") and meta.get("form_method") not in {"", "get"})
        )
"""
replace_once("app/browser_manager.py", old_meta, new_meta, "target metadata and sensitive classifier")

replace_once(
    "app/browser_manager.py",
    """            if meta.get("type") in _SECRET_TYPES or meta.get("autocomplete") in _SECRET_AUTOCOMPLETE:
                self.store.add(session_id=session_id, profile=s.profile, action="fill.blocked_human", success=False, detail={**kwargs, "value": "<redacted>", "reason": "secret_field"})
                return {
                    "ok": False,
                    "human_required": True,
                    "reason": "Passwords, OTP codes and card fields are human-only. Use the remote browser screen.",
                    "secret": True,
                }
            if self._human_only(meta):
""",
    """            if self._human_only(meta):
""",
    "unified fill sensitive guard",
)

s = read("app/browser_manager.py")
s = s.replace('"value": "<redacted>" if secret else value[:200]', '"value": "<redacted>"')
s = s.replace('detail = {**kwargs, "value": "<redacted>" if secret else value[:200], "allow_side_effect": allow_side_effect}', 'detail = {**kwargs, "value": "<redacted>", "allow_side_effect": allow_side_effect}')
write("app/browser_manager.py", s)
print("[OK] fill event values always redacted")

replace_once(
    "app/browser_manager.py",
    """            if self._human_only(meta) and key.lower() in {"enter", "space"}:
                self.store.add(session_id=session_id, profile=s.profile, action="press.blocked_human", success=False, detail={**kwargs, "key": key, "reason": "human_required"})
                return {"ok": False, "human_required": True, "reason": "This sensitive action must be completed in the remote browser."}
""",
    """            if self._human_only(meta):
                self.store.add(session_id=session_id, profile=s.profile, action="press.blocked_human", success=False, detail={**kwargs, "key": "<redacted>", "reason": "human_required"})
                return {"ok": False, "human_required": True, "reason": "Sensitive fields and actions are human-only in the remote browser."}
""",
    "keypress bypass closed",
)

old_inspect = """            elements = await s.page.evaluate(\"\"\"
                () => {
                  const nodes = [...document.querySelectorAll('a,button,input,textarea,select,[role="button"],[role="link"]')].slice(0,250);
                  const labelFor = (el) => {
                    if (el.id) {
                      const lab = document.querySelector(\`label[for="\${CSS.escape(el.id)}"]\`);
                      if (lab) return lab.innerText.trim();
                    }
                    const p = el.closest('label');
                    return p ? p.innerText.trim() : '';
                  };
                  const isSecret = (el) => {
                    const type=(el.getAttribute('type')||'').toLowerCase();
                    const ac=(el.getAttribute('autocomplete')||'').toLowerCase();
                    return type==='password' || ['current-password','new-password','one-time-code','cc-number','cc-csc','cc-exp','cc-exp-month','cc-exp-year'].includes(ac);
                  };
                  return nodes.map((el, i) => ({
                    index: i,
                    tag: el.tagName.toLowerCase(),
                    type: el.getAttribute('type') || '',
                    role: el.getAttribute('role') || '',
                    text: isSecret(el) ? '<redacted>' : (el.innerText || el.value || '').trim().slice(0,300),
                    aria_label: el.getAttribute('aria-label') || '',
                    name: el.getAttribute('name') || '',
                    id: el.id || '',
                    placeholder: isSecret(el) ? '<redacted>' : (el.getAttribute('placeholder') || ''),
                    label: labelFor(el).slice(0,300),
                    href: el.href || '',
                    disabled: !!el.disabled,
                    secret: isSecret(el)
                  }));
                }
            \"\"\")
"""
new_inspect = """            elements = await s.page.evaluate(\"\"\"
                () => {
                  const nodes = [...document.querySelectorAll('a,button,input,textarea,select,[role="button"],[role="link"]')].slice(0,250);
                  const sensitive = /(password|passcode|senha|pin|otp|one[ -]?time|verification code|codigo de verificacao|card(?: number)?|credit card|debit card|cart[aã]o|numero do cart[aã]o|cvv|cvc|security code|expiry|expiration|validade|pix|transfer|bank account|account number|routing|iban|swift|cpf|cnpj|social security|ssn)/i;
                  const labelFor = (el) => {
                    if (el.id) {
                      const lab = document.querySelector(\`label[for="\${CSS.escape(el.id)}"]\`);
                      if (lab) return (lab.innerText || lab.textContent || '').trim();
                    }
                    const p = el.closest('label');
                    return p ? (p.innerText || p.textContent || '').trim() : '';
                  };
                  const descriptors = (el) => [
                    el.getAttribute('aria-label')||'', el.getAttribute('name')||'', el.id||'',
                    el.getAttribute('placeholder')||'', labelFor(el), el.innerText||''
                  ].join(' ').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/[_-]+/g, ' ');
                  const isSensitive = (el) => {
                    const type=(el.getAttribute('type')||'').toLowerCase();
                    const ac=(el.getAttribute('autocomplete')||'').toLowerCase();
                    return type==='password' || ['current-password','new-password','one-time-code','cc-number','cc-csc','cc-exp','cc-exp-month','cc-exp-year'].includes(ac) || sensitive.test(descriptors(el));
                  };
                  return nodes.map((el, i) => {
                    const secret = isSensitive(el);
                    return {
                      index: i,
                      tag: el.tagName.toLowerCase(),
                      type: el.getAttribute('type') || '',
                      role: el.getAttribute('role') || '',
                      text: secret ? '<redacted>' : (el.innerText || el.value || '').trim().slice(0,300),
                      aria_label: el.getAttribute('aria-label') || '',
                      name: el.getAttribute('name') || '',
                      id: el.id || '',
                      placeholder: secret ? '<redacted>' : (el.getAttribute('placeholder') || ''),
                      label: labelFor(el).slice(0,300),
                      href: el.href || '',
                      disabled: !!el.disabled,
                      secret
                    };
                  });
                }
            \"\"\")
"""
replace_once("app/browser_manager.py", old_inspect, new_inspect, "inspect sensitive redaction")

replace_once(
    "app/browser_manager.py",
    """            elif mode == "html":
                value = (await s.page.content())[:settings.max_text_chars]
            elif mode == "links":
""",
    """            elif mode == "html":
                raise ValueError("raw HTML extraction is disabled because it may expose hidden credentials or tokens")
            elif mode == "links":
""",
    "raw HTML extraction disabled",
)
replace_once(
    "app/browser_manager.py",
    'raise ValueError("mode must be text, html, or links")',
    'raise ValueError("mode must be text or links")',
    "extract error contract",
)

db_marker = 'from typing import Any\n\n\nclass EventStore:'
db_new = """from typing import Any

_SENSITIVE_DETAIL_KEYS = {
    "value", "password", "passcode", "pin", "otp", "token", "secret", "api_key",
    "authorization", "cookie", "card", "card_number", "cvv", "cvc", "security_code",
}


def _redact_detail(value: Any, key: str | None = None) -> Any:
    if key and key.lower() in _SENSITIVE_DETAIL_KEYS:
        return "<redacted>"
    if isinstance(value, dict):
        return {str(k): _redact_detail(v, str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [_redact_detail(v) for v in value]
    return value


class EventStore:"""
replace_once("app/db.py", db_marker, db_new, "event redaction helper")
replace_once(
    "app/db.py",
    'payload = json.dumps(detail or {}, ensure_ascii=False, separators=(",", ":"))',
    'payload = json.dumps(_redact_detail(detail or {}), ensure_ascii=False, separators=(",", ":"))',
    "event redaction on write",
)
replace_once(
    "app/db.py",
    'd["detail"] = json.loads(d.pop("detail_json"))',
    'd["detail"] = _redact_detail(json.loads(d.pop("detail_json")))',
    "event redaction on read",
)

for old, new, label in [
    ('version="1.2.0"', 'version="1.2.2"', "FastAPI version"),
    ('"version": "1.2.0"', '"version": "1.2.2"', "health version"),
    ('pattern="^(text|html|links)$"', 'pattern="^(text|links)$"', "API extract modes"),
]:
    replace_once("app/main.py", old, new, label)

replace_once(
    "mcp_server.py",
    """async def browser_extract(session_id: str, mode: str = "text") -> dict[str, Any]:
    \"\"\"Extract text, HTML or links from the current page.\"\"\"
    return await api("GET", f"/v1/sessions/{session_id}/extract?mode={quote(mode)}")
""",
    """async def browser_extract(session_id: str, mode: str = "text") -> dict[str, Any]:
    \"\"\"Extract visible text or links from the current page. Raw HTML is intentionally disabled.\"\"\"
    mode = mode.lower().strip()
    if mode not in {"text", "links"}:
        raise ValueError("mode must be text or links")
    return await api("GET", f"/v1/sessions/{session_id}/extract?mode={quote(mode)}")
""",
    "MCP extract modes",
)

caddy = read("deploy/Caddyfile")
if "rewrite * /healthz" not in caddy:
    old = """    handle /api/healthz {
        reverse_proxy api:8080
    }
"""
    new = """    handle /api/healthz {
        rewrite * /healthz
        reverse_proxy api:8080
    }
"""
    if old not in caddy:
        fail("Caddy health route shape is unexpected")
    write("deploy/Caddyfile", caddy.replace(old, new, 1))
print("[OK] Caddy health rewrite")

compose = read("docker-compose.yml")
if "      - control_api\n" not in compose:
    old = """    expose:
      - "8080"
    shm_size: "512mb"
"""
    new = """    expose:
      - "8080"
    networks:
      - default
      - control_api
    shm_size: "512mb"
"""
    if old not in compose:
        fail("api expose block in docker-compose.yml is unexpected")
    compose = compose.replace(old, new, 1)
if "\nnetworks:\n  control_api:\n    internal: true\n" not in compose:
    marker = "\nvolumes:\n"
    if marker not in compose:
        fail("volumes marker in docker-compose.yml is missing")
    compose = compose.replace(marker, "\nnetworks:\n  control_api:\n    internal: true\n\nvolumes:\n", 1)
write("docker-compose.yml", compose)
print("[OK] isolated control_api network")

for rel in (".env.example", "README.md", "VPS_ALVO_AUDITADA.txt", "instalar.sh"):
    s = read(rel)
    s = s.replace("THOTH Browser Node V1.2.1", "THOTH Browser Node V1.2.2 AUDITED")
    s = s.replace("THOTH BROWSER NODE V1.2.1", "THOTH BROWSER NODE V1.2.2 AUDITED")
    s = s.replace("THOTH Browser Node V1.2 - arquivo criado automaticamente pelo instalador.", "THOTH Browser Node V1.2.2 AUDITED - arquivo criado automaticamente pelo instalador.")
    write(rel, s)
print("[OK] version labels")

pyproject = read("pyproject.toml")
if 'version = "0.1.2.2"' not in pyproject:
    if 'version = "0.1.2"' not in pyproject:
        fail("pyproject version is unexpected")
    pyproject = pyproject.replace('version = "0.1.2"', 'version = "0.1.2.2"', 1)
    write("pyproject.toml", pyproject)
print("[OK] package version")

(ROOT / "VERSION_AUDITED").write_text("THOTH Browser Node V1.2.2 AUDITED\n", encoding="utf-8")
print("V1_2_2_SOURCE_UPGRADE_OK")
