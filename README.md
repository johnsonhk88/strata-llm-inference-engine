# Strata LLM inference

Local setup for [Niko1221/Strata](https://github.com/Niko1221/Strata) on this machine: **native Terminal** and **Docker**, sharing `./data` on this disk.

This repo does not vendor the engine. It installs the official CLI and runs the official NVIDIA CUDA 13 image.

## Hardware on this host

| | |
| --- | --- |
| GPU | NVIDIA RTX PRO 4500 Blackwell, 32 GB, driver 580, CUDA 13 |
| RAM | ~94 GB |
| OS | Ubuntu 24.04 x86-64 |
| Default model | ISTA-DASLab Qwen3.8-Flash-Next **IQ3_S** (plan: ~90 GB download, 32K context, GPU vision) |

Only one runner may own the GPU. A vLLM process on this host already uses ~26 GB VRAM — stop it before launching Strata.

## One-time setup

```bash
cp .env.example .env
# .env is created with a random API_KEY by the install script if missing
./scripts/install-native.sh
docker compose pull
./scripts/plan.sh          # prints download size; does not start the model
```

Add `~/.local/bin` to `PATH` if `strata` is not found after install.

## Run (pick one)

Native Terminal (best for `strata connect` with OpenCode and other tools):

```bash
./scripts/launch-native.sh
./scripts/status.sh
strata connect opencode
```

Docker (same OpenAI/Anthropic API on `http://127.0.0.1:8080`):

```bash
./scripts/launch-docker.sh
docker compose logs -f
./scripts/status.sh
```

First start downloads the model into `./data` (resumable, tens of GB). Stop with `./scripts/stop.sh`.

Clients:

- OpenAI-compatible: `http://127.0.0.1:8080/v1` plus `Authorization: Bearer <API_KEY>`
- Anthropic-compatible: `http://127.0.0.1:8080` (client adds `/v1/messages`)
- `GET /health` does not need a key

## Layout

| Path | Role |
| --- | --- |
| `.env` | Model, port, API key (gitignored) |
| `docker-compose.yml` | Official `cuda13` image, bind-mount `./data`, localhost:8080 |
| `data/` | Shared model/runtime files |
| `scripts/` | Install, plan, launch, stop, status |

Do not run native and Docker at the same time. Compose `restart` is off so a reboot does not steal the GPU.
