#!/usr/bin/env python3
"""Smoke-test the local Strata OpenAI-compatible API (health, models, chat)."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.is_file():
        return env
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip("'").strip('"')
    return env


def request(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    body: dict | None = None,
    timeout: float = 30,
) -> tuple[int, object, float]:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    if data is not None:
        req.add_header("Content-Type", "application/json")
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            elapsed = time.perf_counter() - started
            payload: object
            if not raw:
                payload = None
            else:
                try:
                    payload = json.loads(raw.decode())
                except json.JSONDecodeError:
                    payload = raw.decode(errors="replace")
            return resp.status, payload, elapsed
    except urllib.error.HTTPError as exc:
        elapsed = time.perf_counter() - started
        raw = exc.read()
        try:
            payload = json.loads(raw.decode()) if raw else {"error": str(exc)}
        except json.JSONDecodeError:
            payload = raw.decode(errors="replace") if raw else str(exc)
        return exc.code, payload, elapsed


def fail(message: str) -> None:
    print(f"FAIL  {message}", file=sys.stderr)
    raise SystemExit(1)


def ok(label: str, detail: str, elapsed: float) -> None:
    print(f"OK    {label:<10} {elapsed:6.2f}s  {detail}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prompt",
        default="Say hi in one sentence.",
        help="User message for /v1/chat/completions",
    )
    parser.add_argument("--max-tokens", type=int, default=64)
    parser.add_argument("--timeout", type=float, default=180, help="Chat request timeout (seconds)")
    parser.add_argument("--stream", action="store_true", help="Use streaming chat completions")
    args = parser.parse_args()

    file_env = load_env(ROOT / ".env")
    bind = file_env.get("STRATA_BIND") or os.environ.get("STRATA_BIND") or "127.0.0.1"
    port = file_env.get("STRATA_PORT") or os.environ.get("STRATA_PORT") or "8080"
    api_key = file_env.get("API_KEY") or os.environ.get("API_KEY") or ""
    base = f"http://{bind}:{port}"
    auth = {"Authorization": f"Bearer {api_key}"}

    print(f"Target  {base}")
    if not api_key or api_key == "change-me-please-use-a-long-random-key":
        fail("Set a real API_KEY in .env")

    status, health, elapsed = request(f"{base}/health", timeout=10)
    if status != 200 or not isinstance(health, dict) or health.get("status") != "ok":
        fail(f"/health -> HTTP {status}: {health!r}")
    if health.get("loaded") is not True:
        fail(f"/health reports loaded={health.get('loaded')!r} (model not serving yet)")
    ok("health", f"model={health.get('model')}  ctx={health.get('max_context')}", elapsed)

    status, models, elapsed = request(f"{base}/v1/models", headers=auth, timeout=15)
    if status != 200 or not isinstance(models, dict):
        fail(f"/v1/models -> HTTP {status}: {models!r}")
    ids = [item.get("id") for item in models.get("data") or [] if isinstance(item, dict)]
    if not ids:
        fail(f"/v1/models returned no ids: {models!r}")
    model_id = str(ids[0])
    ok("models", f"id={model_id}", elapsed)

    body = {
        "model": model_id,
        "messages": [{"role": "user", "content": args.prompt}],
        "max_tokens": args.max_tokens,
        "stream": bool(args.stream),
    }

    if args.stream:
        req = urllib.request.Request(
            f"{base}/v1/chat/completions",
            data=json.dumps(body).encode(),
            method="POST",
            headers={**auth, "Content-Type": "application/json", "Accept": "text/event-stream"},
        )
        started = time.perf_counter()
        chunks: list[str] = []
        try:
            with urllib.request.urlopen(req, timeout=args.timeout) as resp:
                for raw_line in resp:
                    line = raw_line.decode(errors="replace").strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        event = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    delta = (
                        event.get("choices", [{}])[0]
                        .get("delta", {})
                        .get("content")
                    )
                    if delta:
                        chunks.append(delta)
                        print(delta, end="", flush=True)
        except urllib.error.HTTPError as exc:
            fail(f"stream chat -> HTTP {exc.code}: {exc.read().decode(errors='replace')}")
        except Exception as exc:
            fail(f"stream chat failed: {exc}")
        elapsed = time.perf_counter() - started
        text = "".join(chunks).strip()
        if not text:
            fail("stream chat returned no content")
        print()
        ok("chat", f"streamed {len(text)} chars", elapsed)
        return 0

    status, chat, elapsed = request(
        f"{base}/v1/chat/completions",
        method="POST",
        headers=auth,
        body=body,
        timeout=args.timeout,
    )
    if status != 200 or not isinstance(chat, dict):
        fail(f"/v1/chat/completions -> HTTP {status}: {chat!r}")
    try:
        text = chat["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        fail(f"unexpected chat payload: {chat!r}")
    if not str(text).strip():
        fail("chat returned empty content")
    usage = chat.get("usage") or {}
    usage_bits = []
    for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
        if key in usage:
            usage_bits.append(f"{key}={usage[key]}")
    extra = "  ".join(usage_bits) if usage_bits else "no usage field"
    ok("chat", extra, elapsed)
    print()
    print(text.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
