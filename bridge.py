from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from bridge_crypto import b64d, decrypt_task, encrypt_result, load_or_create_private_key, public_key_b64

QUEUE_URL = os.getenv("BRIDGE_QUEUE_URL", "https://raw.githubusercontent.com/heldersontuc-collab/thoth-browser-bridge/main/queue.json")
DATA_DIR = Path(os.getenv("BRIDGE_DATA_DIR", "/data"))
POLL_SECONDS = max(2, int(os.getenv("BRIDGE_POLL_SECONDS", "4")))
RESULT_TTL = max(60, int(os.getenv("BRIDGE_RESULT_TTL_SECONDS", "1800")))
MAX_QUEUE_TASKS = 50
MAX_TASK_AGE = 900

DATA_DIR.mkdir(parents=True, exist_ok=True)
KEY_DIR = DATA_DIR / "keys"
RESULT_DIR = DATA_DIR / "results"
KEY_DIR.mkdir(exist_ok=True)
RESULT_DIR.mkdir(exist_ok=True)
PROCESSED_FILE = DATA_DIR / "processed.json"
PRIVATE_KEY_FILE = KEY_DIR / "vps_x25519.key"

app = FastAPI(title="THOTH Browser Bridge", version="1.1.0", docs_url=None, redoc_url=None, openapi_url=None)
_worker: asyncio.Task | None = None
log = logging.getLogger("thoth.bridge")
PRIVATE_KEY = load_or_create_private_key(PRIVATE_KEY_FILE)
STATUS: dict[str, Any] = {
    "last_poll_at": None,
    "last_poll_error": None,
    "last_seen_task_id": None,
    "last_processed_task_id": None,
    "last_result_task_id": None,
}

def load_processed() -> set[str]:
    try:
        obj = json.loads(PROCESSED_FILE.read_text("utf-8"))
        return set(obj.get("ids", []))
    except Exception:
        return set()

def save_processed(ids: set[str]) -> None:
    kept = list(ids)[-5000:]
    tmp = PROCESSED_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps({"ids": kept}, separators=(",", ":")), "utf-8")
    tmp.replace(PROCESSED_FILE)

PROCESSED = load_processed()

async def execute_via_mcp(task: dict[str, Any]) -> Any:
    from bridge_mcp_client import call_tool
    action = str(task["action"])
    args = dict(task.get("args") or {})
    return await call_tool(action, args)

def write_result(task_id: str, envelope: dict[str, Any]) -> None:
    p = RESULT_DIR / f"{task_id}.json"
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(envelope, separators=(",", ":")), "utf-8")
    tmp.replace(p)

def cleanup_results() -> None:
    cutoff = time.time() - RESULT_TTL
    for p in RESULT_DIR.glob("*.json"):
        try:
            if p.stat().st_mtime < cutoff:
                p.unlink(missing_ok=True)
        except OSError:
            pass

async def process_one(envelope: dict[str, Any]) -> None:
    task_id = str(envelope.get("task_id", ""))
    STATUS["last_seen_task_id"] = task_id or None
    if not task_id or task_id in PROCESSED:
        return
    response_key: bytes | None = None
    try:
        task = decrypt_task(PRIVATE_KEY, envelope)
        now = int(time.time())
        created = int(task.get("created_at", now))
        expires = int(task.get("expires_at", now + 1))
        if expires < now or created > now + 120 or now - created > MAX_TASK_AGE:
            raise ValueError("task expired or timestamp invalid")
        response_key = b64d(task["response_key"])
        if len(response_key) != 32:
            raise ValueError("invalid response key")
        result = await execute_via_mcp(task)
        payload = {"ok": True, "task_id": task_id, "finished_at": int(time.time()), "result": result}
    except Exception as exc:
        if response_key is None:
            log.warning("task_rejected task_id=%s error_type=%s", task_id[:128], type(exc).__name__)
            PROCESSED.add(task_id)
            save_processed(PROCESSED)
            return
        log.warning("task_failed task_id=%s error_type=%s", task_id[:128], type(exc).__name__)
        payload = {"ok": False, "task_id": task_id, "finished_at": int(time.time()), "error": str(exc)[:1000]}

    write_result(task_id, encrypt_result(task_id, response_key, payload))
    log.info("task_result_ready task_id=%s", task_id[:128])
    STATUS["last_result_task_id"] = task_id
    STATUS["last_processed_task_id"] = task_id
    PROCESSED.add(task_id)
    save_processed(PROCESSED)

async def poll_loop() -> None:
    while True:
        try:
            STATUS["last_poll_at"] = int(time.time())
            STATUS["last_poll_error"] = None
            async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
                r = await client.get(QUEUE_URL, headers={"Cache-Control": "no-cache"}, params={"_": int(time.time())})
                r.raise_for_status()
                queue = r.json()
            tasks = list(queue.get("tasks") or [])[-MAX_QUEUE_TASKS:]
            for envelope in tasks:
                if isinstance(envelope, dict):
                    await process_one(envelope)
            cleanup_results()
        except Exception as exc:
            STATUS["last_poll_error"] = f"{type(exc).__name__}: {str(exc)[:300]}"
            log.warning("queue_poll_failed error_type=%s", type(exc).__name__)
        await asyncio.sleep(POLL_SECONDS)

@app.on_event("startup")
async def startup() -> None:
    global _worker
    _worker = asyncio.create_task(poll_loop(), name="thoth-bridge-poller")

@app.on_event("shutdown")
async def shutdown() -> None:
    if _worker:
        _worker.cancel()

@app.get("/healthz")
async def healthz() -> dict[str, Any]:
    return {"ok": True, "service": "THOTH Browser Bridge", "version": "1.1.0"}

@app.get("/readyz")
async def readyz():
    poll_age = None if STATUS["last_poll_at"] is None else int(time.time()) - int(STATUS["last_poll_at"])
    queue_ok = STATUS["last_poll_at"] is not None and STATUS["last_poll_error"] is None and poll_age <= max(20, POLL_SECONDS * 4)
    browser_api_ok = False
    try:
        from bridge_mcp_client import call_tool
        result = await call_tool("health", {})
        browser_api_ok = bool(result.get("ok"))
    except Exception as exc:
        log.warning("browser_api_readiness_failed error_type=%s", type(exc).__name__)
    body = {
        "ok": bool(queue_ok and browser_api_ok),
        "queue_ok": bool(queue_ok),
        "browser_api_ok": bool(browser_api_ok),
        "poll_age_seconds": poll_age,
    }
    if not body["ok"]:
        raise HTTPException(status_code=503, detail=body)
    return body

@app.get("/public-key")
async def public_key() -> dict[str, Any]:
    return {"v": 1, "alg": "X25519", "public_key": public_key_b64(PRIVATE_KEY)}

@app.get("/result/{task_id}")
async def get_result(task_id: str):
    if not task_id or len(task_id) > 128 or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for c in task_id):
        raise HTTPException(status_code=400, detail="invalid task id")
    p = RESULT_DIR / f"{task_id}.json"
    if not p.exists():
        raise HTTPException(status_code=404, detail="not ready")
    return JSONResponse(json.loads(p.read_text("utf-8")), headers={"Cache-Control": "no-store"})

