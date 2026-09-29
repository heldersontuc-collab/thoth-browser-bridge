from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

INFO = b"THOTH-BROWSER-BRIDGE-V1"

def b64e(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")

def b64d(value: str) -> bytes:
    return base64.b64decode(value.encode("ascii"), validate=True)

def load_or_create_private_key(path: Path) -> X25519PrivateKey:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raw = path.read_bytes()
        if len(raw) != 32:
            raise RuntimeError("invalid stored bridge key")
        return X25519PrivateKey.from_private_bytes(raw)
    private = X25519PrivateKey.generate()
    raw = private.private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(raw)
    os.chmod(tmp, 0o600)
    tmp.replace(path)
    return private

def public_key_b64(private: X25519PrivateKey) -> str:
    raw = private.public_key().public_bytes(
        serialization.Encoding.Raw,
        serialization.PublicFormat.Raw,
    )
    return b64e(raw)

def decrypt_task(private: X25519PrivateKey, envelope: dict[str, Any]) -> dict[str, Any]:
    task_id = str(envelope["task_id"])
    peer = X25519PublicKey.from_public_bytes(b64d(envelope["ephemeral_pub"]))
    shared = private.exchange(peer)
    key = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=INFO,
    ).derive(shared)
    plaintext = AESGCM(key).decrypt(
        b64d(envelope["nonce"]),
        b64d(envelope["ciphertext"]),
        task_id.encode("utf-8"),
    )
    obj = json.loads(plaintext)
    if obj.get("task_id") != task_id:
        raise ValueError("task id mismatch")
    return obj

def encrypt_result(task_id: str, response_key: bytes, payload: dict[str, Any]) -> dict[str, Any]:
    import secrets

    nonce = secrets.token_bytes(12)
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    ciphertext = AESGCM(response_key).encrypt(nonce, raw, task_id.encode("utf-8"))
    return {
        "v": 1,
        "task_id": task_id,
        "nonce": b64e(nonce),
        "ciphertext": b64e(ciphertext),
    }
