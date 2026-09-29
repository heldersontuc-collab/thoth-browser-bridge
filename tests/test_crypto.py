import base64
import json
import secrets

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from bridge_crypto import INFO, decrypt_task, encrypt_result


def test_task_crypto_roundtrip():
    server = X25519PrivateKey.generate()
    client = X25519PrivateKey.generate()
    client_pub = client.public_key().public_bytes(
        serialization.Encoding.Raw,
        serialization.PublicFormat.Raw,
    )
    shared = client.exchange(server.public_key())
    key = HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=INFO).derive(shared)

    task_id = "audit-task-1"
    response_key = secrets.token_bytes(32)
    payload = {
        "v": 1,
        "task_id": task_id,
        "created_at": 1,
        "expires_at": 9999999999,
        "response_key": base64.b64encode(response_key).decode(),
        "action": "health",
        "args": {},
    }
    nonce = secrets.token_bytes(12)
    ciphertext = AESGCM(key).encrypt(
        nonce,
        json.dumps(payload, separators=(",", ":")).encode(),
        task_id.encode(),
    )
    envelope = {
        "v": 1,
        "task_id": task_id,
        "ephemeral_pub": base64.b64encode(client_pub).decode(),
        "nonce": base64.b64encode(nonce).decode(),
        "ciphertext": base64.b64encode(ciphertext).decode(),
    }

    assert decrypt_task(server, envelope) == payload

    result_payload = {"ok": True, "result": {"browser_api": "authenticated"}}
    result = encrypt_result(task_id, response_key, result_payload)
    clear = AESGCM(response_key).decrypt(
        base64.b64decode(result["nonce"]),
        base64.b64decode(result["ciphertext"]),
        task_id.encode(),
    )
    assert json.loads(clear) == result_payload
