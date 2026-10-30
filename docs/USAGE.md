# Step-by-step usage

How to install, plan, launch, call, and stop Strata with this repo. For a second machine with two Tesla V100s, read [V100.md](V100.md) first and use `.env.v100.example` instead of `.env.example`.

Official engine docs: [Niko1221/Strata](https://github.com/Niko1221/Strata) (`docs/INSTALL.md`, `docs/AI_SETUP.md`, `docs/DOCKER.md`).

## Prerequisites

- Linux x86-64 (this setup is tested on Ubuntu 24.04)
- NVIDIA GPU and a matching driver
  - RTX 20 / 30 / 40 / 50 and matching RTX PRO: driver **580+**, CUDA 13 image
  - Tesla V100 / P100 / GTX 10: driver **575.51+**, CUDA 12 image ([V100.md](V100.md))
- Docker Engine + NVIDIA Container Toolkit (for the Docker path)
- Disk: first IQ3_S launch is about **90 GB** under `./data` (model + draft layer + picture reader). Keep that on a large SSD.
- RAM: IQ3_S wants on the order of 50 GB for experts plus ~10 GB for the OS. This host has ~94 GB.

Check the card:

```bash
nvidia-smi
```

## 1. Get the repo

```bash
cd /path/to/strata-llm-inference-engine
```

## 2. Create `.env`

**This Blackwell host:**

```bash
cp .env.example .env
sed -i "s/^API_KEY=.*/API_KEY=$(openssl rand -hex 24)/" .env
```

If `.env` already exists (this checkout generated one), keep that key.

**2× V100 host:** `cp .env.v100.example .env` then set `API_KEY`. Never copy the Blackwell `.env` across.

| Variable | Meaning |
| --- | --- |
| `STRATA_IMAGE` | Docker tag. `…-cuda13` (RTX) or `…-cuda12` (V100) |
| `FAMILY` / `MODEL` | Catalog id, e.g. `qwen` / `IQ3_S` |
| `CONTEXT` | e.g. `32k` |
| `VISION` | `gpu`, `cpu`, or `off` |
| `GPU` | Empty = auto. `0,1` = layer-split both cards (required on V100) |
| `STRATA_BIND` / `STRATA_PORT` | Default `127.0.0.1` / `8080` |
| `API_KEY` | 16+ characters. Required by the launch scripts |

## 3. Install the native Terminal

```bash
./scripts/install-native.sh
strata --version
```

This downloads the signed Terminal into `~/.local` (no source checkout, no compiler). The GPU engine package is fetched on first `strata launch`, not during this step.

If `strata` is missing in a new terminal:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

(`~/.profile` already adds `~/.local/bin` on this host.)

## 4. Pull the Docker image (optional, for the Docker path)

```bash
docker compose pull
docker compose config --quiet
```

The image is ~2 GB. The model is **not** inside the image.

## 5. Print a plan (no download)

```bash
./scripts/plan.sh
```

Read: model name, context, picture reader, **download size**, and whether the engine matches the card. If the plan names the wrong CUDA generation, stop and fix `STRATA_IMAGE` / `GPU` (see [V100.md](V100.md)).

## 6. Free the GPU

```bash
./scripts/status.sh
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
```

Stop vLLM or any other CUDA process that holds VRAM. Only one of native Strata, Docker Strata, or vLLM should run.

## 7a. Launch native

```bash
./scripts/launch-native.sh
```

First start:

1. Downloads the engine for this GPU (signed feed)
2. Downloads the model into `./data` (resumable; IQ3_S ~90 GB)
3. Prepares the pack
4. Serves on `http://127.0.0.1:8080` and returns (`--no-tui`)

`--yes` does not restart a different running model. Use `./scripts/stop.sh` first if settings changed.

Connect a coding tool (native CLI on the same machine):

```bash
strata connect opencode
strata connect opencode --check
```

`--write` changes that tool’s config after a backup; only use it when you want that.

## 7b. Launch Docker

```bash
./scripts/launch-docker.sh
docker compose logs -f
```

Same API. First start downloads into `./data` (bind-mounted at `/data`). Health stays `starting` during the download.

Watch / stop from the host:

```bash
docker exec -it strata strata monitor    # q leaves; server keeps running
docker compose logs -f
./scripts/stop.sh                        # 2 minute grace to unload
```

If a coding app runs **on the host**, point it at `http://127.0.0.1:8080` with the key from `.env`. `docker exec strata strata connect …` prints addresses **inside** the container.

## 8. Verify

```bash
./scripts/status.sh
curl -fsS http://127.0.0.1:8080/health
curl -fsS -H "Authorization: Bearer $API_KEY" http://127.0.0.1:8080/v1/models
```

Load `API_KEY` from `.env` (`set -a && source .env && set +a`). Exit code 0 from launch is not enough: the model must show in `/v1/models`.

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

Example chat (OpenAI):

```bash
set -a && source .env && set +a
curl -sS http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"IQ3_S","messages":[{"role":"user","content":"Say hi in one sentence."}]}'
```

Use the model id returned by `GET /v1/models`, not a guessed name.

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
| GPU OOM / engine dies at start | `./scripts/status.sh`; stop vLLM; pick a smaller `MODEL` |
| `strata: command not found` | `export PATH="$HOME/.local/bin:$PATH"` |
| Docker: could not select NVIDIA driver | install NVIDIA Container Toolkit, `sudo nvidia-ctk runtime configure --runtime=docker`, restart Docker |
| Plan / start says engine does not match the card | RTX → `cuda13`; V100 → `cuda12` and `GPU=0,1` |
| Port in use | change `STRATA_PORT` or stop the other server |
| Download stalled | `docker compose logs -f` or native logs; restart launch — it resumes |
| `docker stop` exit 137 | already using `stop_grace_period: 2m`; wait; do not `kill -9` mid-unload |

Official: [TROUBLESHOOTING.md](https://github.com/Niko1221/Strata/blob/main/docs/TROUBLESHOOTING.md).
