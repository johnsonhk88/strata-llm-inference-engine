# Step-by-step usage

How to install, plan, launch, call, and stop Strata with this repo. **This host is 2× Tesla V100** — read [V100.md](V100.md) and use `.env.v100.example`. A Blackwell / RTX box uses `.env.example` instead.

Official engine docs: [Niko1221/Strata](https://github.com/Niko1221/Strata) (`docs/INSTALL.md`, `docs/AI_SETUP.md`, `docs/DOCKER.md`).

## Prerequisites

- Linux x86-64 (this setup is tested on Ubuntu 24.04)
- NVIDIA GPU and a matching driver
  - Tesla V100 / P100 / GTX 10: driver **575.51+**, CUDA 12 image ([V100.md](V100.md)) — **this host**
  - RTX 20 / 30 / 40 / 50 and matching RTX PRO: driver **580+**, CUDA 13 image
- Docker Engine + NVIDIA Container Toolkit (for the Docker path)
- Disk: first IQ2_XS launch here is about **74 GB** under `./data` (model ~68 GB + MTP draft layer ~5 GB + picture reader ~1 GB). Keep that on a large SSD.
- RAM: IQ2_XS wants on the order of 36 GB for experts plus ~10 GB for the OS. This host has ~62 GB. Do not start with IQ3_S on 16 GB cards.

Check the cards:

```bash
nvidia-smi
```

## 1. Get the repo

```bash
cd /path/to/strata-llm-inference-engine
```

## 2. Create `.env`

**This V100 host:**

```bash
cp .env.v100.example .env
sed -i "s/^API_KEY=.*/API_KEY=$(openssl rand -hex 24)/" .env
```

If `.env` already exists, keep that key.

**Blackwell / RTX host:** `cp .env.example .env` then set `API_KEY`. Never copy that `.env` onto this V100 box.

| Variable | Meaning |
| --- | --- |
| `STRATA_IMAGE` | Docker tag. `…-cuda12` (V100) or `…-cuda13` (RTX) |
| `FAMILY` / `MODEL` | Catalog id, e.g. `qwen` / `IQ2_XS` |
| `CONTEXT` | e.g. `32k` |
| `VISION` | `gpu`, `cpu`, or `off`. This host: `cpu` |
| `GPU` | Empty = auto. `0,1` = layer-split both cards (**required** on V100) |
| `STRATA_BIND` / `STRATA_PORT` | Default `127.0.0.1` / `8080` |
| `API_KEY` | 16+ characters. Required by the launch scripts |

## 3. Install the native Terminal

```bash
./scripts/install-native.sh
strata --version
```

This downloads the signed Terminal into `~/.local` (no source checkout, no compiler). The GPU engine package is fetched on first `strata launch`, not during this step. On Volta, that engine is **CUDA 12**.

If `strata` is missing in a new terminal:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

(`~/.profile` already adds `~/.local/bin` on this host. Interactive bash may not; the wrapper scripts prepend it.)

## 4. Pull the Docker image (this host’s usual path)

```bash
docker compose pull
docker compose config --quiet
```

The image is ~2 GB. The model is **not** inside the image. Compose defaults to `…-cuda12` on this host; `.env` from `.env.v100.example` sets the same tag. A Blackwell box must set `STRATA_IMAGE` to `…-cuda13` before `docker compose pull`.

GPU smoke test (optional):

```bash
docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi
```

## 5. Print a plan (no download)

```bash
./scripts/plan.sh
```

Read: model name, context, picture reader, **download size**, and whether the engine matches the card. On this host it must mention **CUDA 12 / sm_70** and **both GPUs**. If the plan names cuda13, stop and fix `STRATA_IMAGE` / `GPU` (see [V100.md](V100.md)).

## 6. Free the GPU

```bash
./scripts/status.sh
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
```

Stop vLLM or any other CUDA process that holds VRAM. Only one of native Strata, Docker Strata, or vLLM should run.

## 7a. Launch Docker

```bash
./scripts/launch-docker.sh
docker compose logs -f
```

Same API as native. First start downloads into `./data` (bind-mounted at `/data`). Health stays `starting` during the download.

Watch / stop from the host:

```bash
docker exec -it strata strata monitor    # q leaves; server keeps running
docker compose logs -f
./scripts/stop.sh                        # 2 minute grace to unload
```

If a coding app runs **on the host**, point it at `http://127.0.0.1:8080` with the key from `.env`. `docker exec strata strata connect …` prints addresses **inside** the container.

Run scripts with bash (`./scripts/launch-docker.sh`). `sh ./scripts/…` fails on `pipefail`. `Ctrl+C` on `docker compose logs -f` does not stop the container.

## 7b. Launch native

```bash
./scripts/launch-native.sh
```

First start:

1. Downloads the CUDA 12 engine for these GPUs (signed feed)
2. Downloads the model into `./data` (resumable; IQ2_XS ~74 GB including draft + picture reader)
3. Prepares the pack
4. Serves on `http://127.0.0.1:8080` and returns (`--no-tui`)

`--yes` does not restart a different running model. Use `./scripts/stop.sh` first if settings changed. Do not launch native while Docker Strata is up.

Connect a coding tool (native CLI on the same machine):

```bash
strata connect opencode
strata connect opencode --check
```

`--write` changes that tool’s config after a backup; only use it when you want that.

## Check Docker Strata

`docker compose up` succeeding is not the API being ready. First start downloads the model (~74 GB for IQ2_XS), prepares the pack, then loads it. Until then, health is `starting` and port 8080 refuses connections.

```bash
./scripts/status.sh
docker compose ps
docker compose logs --tail 50
ls -lh data/Strata-data/models/IQ2_XS/
docker stats --no-stream strata
curl -fsS http://127.0.0.1:8080/health
python3 scripts/test_api.py
```

| Signal | Meaning |
| --- | --- |
| `health: starting` | Download/prepare/load still running. API down. |
| `healthy` | `/v1/models` answered. Serving. |
| Growing `*.gguf.part` / rising NET I/O | Download in progress (logs often show no percent). |
| Complete `.gguf` files, no `.part` | Fetch done; prepare or load comes next. |
| Connection reset / refused on `:8080` | Not serving yet, or the process died. |
| Other CUDA process in `nvidia-smi` | Another engine owns VRAM; load will likely OOM. |

Logs may say **Downloading the draft layer (~5 GB)**. That is MTP (multi-token prediction): a small extra network that drafts upcoming tokens so the main model can verify several at once. Replies are often about twice as fast. It is not a second full model. Skip it only if you are short on memory (native: `--mtp off`; this wrapper does not expose that in `.env`).

After it is healthy: `docker exec -it strata strata monitor`.

## 8. Verify

```bash
./scripts/status.sh
curl -fsS http://127.0.0.1:8080/health
python3 scripts/test_api.py
```

Load `API_KEY` from `.env` if you curl `/v1/models` yourself (`set -a && source .env && set +a`). Exit code 0 from launch is not enough: `/health` must show `"loaded": true` and the model id must appear in `/v1/models`.

## 9. Stop

```bash
./scripts/stop.sh
```

Unloads the model and frees VRAM. Docker stop can take up to two minutes.

## API

Base URL after a successful launch: `http://127.0.0.1:8080`.

| Client | Base URL | Auth |
| --- | --- | --- |
| OpenAI-compatible | `http://127.0.0.1:8080/v1` | `Authorization: Bearer <API_KEY>` |
| Anthropic-compatible | `http://127.0.0.1:8080` | same key; client adds `/v1/messages` |
| Health | `GET /health` | none |

On this host a healthy `/health` looks like:

```json
{"status": "ok", "max_context": 32768, "model": "qwen3.8-flash-next-iq2_xs", "images": true, "api_key": true, "loaded": true, "service": "strata"}
```

Example chat (OpenAI). Use the **id from `GET /v1/models`**, not the `.env` `MODEL` short name:

```bash
set -a && source .env && set +a
curl -sS http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.8-flash-next-iq2_xs","messages":[{"role":"user","content":"Say hi in one sentence."}]}'
```

Python smoke test (stdlib only; reads `.env`, never prints the key):

```bash
python3 scripts/test_api.py
python3 scripts/test_api.py --stream --prompt "Say hi in one sentence."
```

`scripts/test_api.py` checks `/health` (must be loaded), `/v1/models`, then `/v1/chat/completions`. Flags: `--prompt`, `--max-tokens`, `--timeout`, `--stream`.

Keep `STRATA_BIND=127.0.0.1` unless you intentionally serve the LAN. Binding `0.0.0.0` requires a real API key.

## Switch model or context

1. `./scripts/stop.sh`
2. Edit `FAMILY`, `MODEL`, `CONTEXT`, `VISION`, or `GPU` in `.env`
3. `./scripts/plan.sh` and confirm disk/RAM
4. Launch again

Native and Docker can share GGUF files under `./data`, but prepared packs may still be created per runner. Prefer **one** runner to do the first download.

## Rules

- Never commit `.env`, GGUFs, or `data/` payloads
- Never run native and Docker Strata together
- Do not start a download unless you meant to launch (`plan.sh` is safe)
- Do not install GPU drivers or compilers as a side effect of `install-native.sh`

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| GPU OOM / engine dies at start | `./scripts/status.sh`; stop other CUDA jobs; keep `MODEL=IQ2_XS` on 16 GB cards |
| `strata: command not found` | `export PATH="$HOME/.local/bin:$PATH"` |
| Docker: could not select NVIDIA driver | install NVIDIA Container Toolkit, `sudo nvidia-ctk runtime configure --runtime=docker`, restart Docker |
| Plan / start says engine does not match the card | V100 → `cuda12` and `GPU=0,1`; RTX → `cuda13` |
| Port in use | change `STRATA_PORT` or stop the other server |
| Download stalled | `docker compose logs -f` or native logs; restart launch — it resumes |
| `docker stop` exit 137 | already using `stop_grace_period: 2m`; wait; do not `kill -9` mid-unload |

Official: [TROUBLESHOOTING.md](https://github.com/Niko1221/Strata/blob/main/docs/TROUBLESHOOTING.md).
