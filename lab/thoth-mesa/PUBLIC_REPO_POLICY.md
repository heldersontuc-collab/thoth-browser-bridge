# THOTH MESA public-repository policy

This repository may contain **sanitized laboratory evidence only** for THOTH MESA.

Never commit:
- API keys, tokens, passwords, private keys, cookies, service-role credentials or vault contents.
- THOTH production/private source code or private VPS paths.
- Industrial/OT identifiers, PLC tags, plant dumps, credentials or company data.
- User-private files, account data, or unredacted third-party responses containing secrets.

The persistent source of truth for THOTH MESA is the private Supabase `thoth_mesa` schema and its audit/event records. GitHub lab files are evidence and test harnesses, not the operational memory bus.
