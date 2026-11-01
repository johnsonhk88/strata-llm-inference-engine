# Strata LLM inference

Local launch wrappers for [Niko1221/Strata](https://github.com/Niko1221/Strata): **native Terminal** and **Docker**, sharing `./data`.

This repo does not vendor the engine. It installs the official CLI and pulls the official NVIDIA image.

| Machine | Profile | Image |
| --- | --- | --- |
| **This host** — RTX PRO 4500 Blackwell 32 GB, driver 580, CUDA 13, ~94 GB RAM | `.env.example` | `…:0.2.8-cuda13` |
| **Other host** — 2× Tesla V100 | `.env.v100.example` | `…:0.2.8-cuda12` — see [docs/V100.md](docs/V100.md) |

Do not copy this host’s `.env` onto the V100 box. CUDA 13 cannot run Volta.

**Guides:** [docs/USAGE.md](docs/USAGE.md) (full steps, API, troubleshooting) · [docs/V100.md](docs/V100.md) (dual V100)

---

## 1. One-time setup (this host)

1. Install NVIDIA driver **580+**, Docker, and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). Confirm `nvidia-smi` and `docker run --rm --gpus all nvidia/cuda:13.0.0-base-ubuntu24.04 nvidia-smi`.
2. In this repo:

   ```bash
   cp .env.example .env
   # replace API_KEY, or keep the generated key if .env already exists
   ./scripts/install-native.sh
   docker compose pull
   ```

3. Add `export PATH="$HOME/.local/bin:$PATH"` to your shell if `strata` is not found.
4. Inspect the download **without starting** the model:

   ```bash
   ./scripts/plan.sh
   ```

   Default here is ISTA-DASLab Qwen3.8-Flash-Next **IQ3_S**, 32K, GPU vision (~90 GB first download).

## 2. Free the GPU

Only **one** engine may own the card. On this host a **vLLM** process often holds ~26 GB VRAM. Stop it (and any other CUDA job) before Strata.

```bash
./scripts/status.sh    # lists GPU compute processes
```

## 3. Launch (pick one)

**A. Native Terminal** (best for `strata connect` / OpenCode):

```bash
./scripts/launch-native.sh
./scripts/status.sh
strata connect opencode
```

**B. Docker** (same API):

```bash
./scripts/launch-docker.sh
docker compose logs -f     # first start: model download, resumable
./scripts/status.sh
```

Do not run A and B at the same time. Compose `restart` is off so a reboot does not steal the GPU.

Run the scripts with **bash** (`./scripts/launch-docker.sh`). `sh ./scripts/…` fails (`set: Illegal option -o pipefail`).

## 4. Check Docker Strata is running

`docker compose up` succeeding is **not** the same as the API being ready. First start downloads ~90 GB, then prepares the pack, then loads the model. Until that finishes, health stays `starting` and `http://127.0.0.1:8080` is not reachable. `Ctrl+C` on `docker compose logs -f` only leaves the log view; the container keeps running.

**1. Container and health**

```bash
./scripts/status.sh
docker compose ps
```

| `STATUS` | Meaning |
| --- | --- |
| `Up … (health: starting)` | Container is alive. Model download/prepare/load is still in progress. API is down. |
| `Up … (healthy)` | Engine answered `/v1/models`. This is the “it works” signal. |
| `Exited` / `unhealthy` | Failed. Read `docker compose logs --tail 80`. |

**2. API (only works when healthy)**

```bash
curl -fsS http://127.0.0.1:8080/health
set -a && source .env && set +a
curl -fsS -H "Authorization: Bearer ${API_KEY}" http://127.0.0.1:8080/v1/models
```

`/health` needs no key. `/v1/models` must list the model. Connection reset or refused = not serving yet (or crashed).

**3. Download still going?**

Compose logs often stay on “Getting your model ready” with no percent. Check the partial file instead:

```bash
docker compose logs --tail 50
ls -lh data/Strata-data/models/IQ3_S/
docker stats --no-stream strata    # NET I/O climbing = download
```

A growing `*.gguf.part` (and later a second `…-00002-of-00002.gguf.part`) means the fetch is working. IQ3_S is two shards, tens of GB each. When `.part` files are gone and you have complete `.gguf` files, setup moves on to prepare + load.

**4. GPU**

```bash
nvidia-smi
```

If `VLLM::EngineCore` (or another job) still holds most of the VRAM, Strata can download but will likely OOM when it tries to load. Stop the other engine first.

**5. Live monitor (after it is healthy)**

```bash
docker exec -it strata strata monitor
```

More detail: [docs/USAGE.md](docs/USAGE.md#check-docker-strata).

## 5. Use the API

- OpenAI-compatible: `http://127.0.0.1:8080/v1` with `Authorization: Bearer <API_KEY>`
- Anthropic-compatible: `http://127.0.0.1:8080` (client adds `/v1/messages`)
- `GET /health` needs no key

Details and curl examples: [docs/USAGE.md](docs/USAGE.md#api).

## 6. Stop

```bash
./scripts/stop.sh
```

---

## Layout

| Path | Role |
| --- | --- |
| `.env` | Model, port, API key, image, GPUs (gitignored) |
| `.env.example` | Blackwell / CUDA 13 defaults |
| `.env.v100.example` | 2× V100 / CUDA 12 defaults |
| `docker-compose.yml` | Official image, bind-mount `./data`, localhost:8080 |
| `data/` | Shared model and runtime files |
| `scripts/` | install, plan, launch, stop, status |
| `docs/` | Step-by-step usage and V100 notes |

## Scripts

| Script | What it does |
| --- | --- |
| `./scripts/install-native.sh` | Official Terminal install into `~/.local` |
| `./scripts/plan.sh` | Print download size and engine plan; no download |
| `./scripts/launch-native.sh` | Serve with `strata launch` |
| `./scripts/launch-docker.sh` | `docker compose up -d` |
| `./scripts/status.sh` | GPU, native, Docker, `/health` |
| `./scripts/stop.sh` | Stop native and/or Docker |
