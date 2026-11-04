# Step-by-step usage

How to install, plan, launch, call, and stop Strata with this repo. **This host is 2× Tesla V100** — read [V100.md](V100.md) and use `.env.v100.example`. A Blackwell / RTX box uses `.env.example` and **must keep `GPU=0`**. Native Terminal is 0.2.10; Docker images are pinned **0.2.9** until GHCR publishes 0.2.10.

Official engine docs: [Niko1221/Strata](https://github.com/Niko1221/Strata) (`docs/INSTALL.md`, `docs/AI_SETUP.md`, `docs/DOCKER.md`).

## Prerequisites

- Linux x86-64 (this setup is tested on Ubuntu 24.04)
- NVIDIA GPU and a matching driver
  - Tesla V100 / P100 / GTX 10: driver **575.51+**, CUDA 12 image ([V100.md](V100.md)) — **this host**
  - RTX 20 / 30 / 40 / 50 and matching RTX PRO: driver **580+**, CUDA 13 image
- Docker Engine + NVIDIA Container Toolkit (for the Docker path)
- Disk: first IQ2_XS launch here is about **74 GB** under `./data` (model ~68 GB + MTP draft layer ~5 GB + picture reader ~1 GB). Blackwell IQ3_S is about **85 GB** of model files. DeepSeek ISTA-DAS Coder is about **191 GB** (Blackwell native only). Keep that on a large SSD.
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

**Blackwell / RTX host:** `cp .env.example .env` then set `API_KEY`. Keep `GPU=0`. Never copy that `.env` onto this V100 box, and never copy a V100 `.env` (`GPU=0,1`, `cuda12`) onto the Blackwell box.

| Variable | Meaning |
| --- | --- |
| `STRATA_IMAGE` | Docker tag. `0.2.9-cuda12` (V100) or `0.2.9-cuda13` (RTX). Native CLI is 0.2.10 |
| `FAMILY` / `MODEL` | Catalog id, e.g. `qwen` / `IQ2_XS`, or `deepseek41` / `ISTA-DAS-Coder` |
| `CONTEXT` | e.g. `32k` (Qwen) or `8k` (DeepSeek default) |
| `VISION` | `gpu`, `cpu`, or `off`. V100: `cpu`. Blackwell 32 GB: `gpu` |
| `GPU` | **Must be set.** Unset/empty becomes `0,1` in Compose and `scripts/common.sh`. V100: `0,1`. One card (Blackwell / RTX): `0`. Confirm with `docker compose config` |
| `SPEED` | DeepSeek only: `faster` or `full`. Empty = engine Auto |
| `DRAFTING` | Qwen: `auto` / `mtp` / `dflash2` / `off`. Empty = Auto. DeepSeek uses DSpark, not DFlash2 |
| `STRATA_BIND` / `STRATA_PORT` | Default `127.0.0.1` / `8080` |
| `API_KEY` | 16+ characters. Required by the launch scripts |

Blackwell first IQ3_S fetch is about **85 GB** of model files (Strata reports ~84.5 GB), plus helpers. V100 IQ2_XS is about **74 GB** including draft + picture reader.

## 3. Install the native Terminal

```bash
./scripts/install-native.sh
strata --version
```

This downloads the signed Terminal into `~/.local` (no source checkout, no compiler). The GPU engine package is fetched on first `strata launch`, not during this step. On Volta, that engine is **CUDA 12**. If you already had 0.2.9, run `strata update`. Coming from 0.2.9 with DeepSeek, run it a **second** time for `engine-dsv41`.

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

The image is ~2 GB. The model is **not** inside the image. Compose defaults to `…-cuda12` on this host; `.env` from `.env.v100.example` sets the same tag. A Blackwell box must set `STRATA_IMAGE` to `…-cuda13` and `GPU=0` before `docker compose pull`. Check interpolation with `docker compose config | grep -E 'GPU|image:'`.

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

On the Blackwell box, vLLM is often a Helm deploy in `default`. Scaling is the clean stop (a kill will be recreated):

```bash
kubectl get deploy vllm -n default
kubectl scale deployment vllm -n default --replicas=0
# bring it back later, after Strata is stopped:
# kubectl scale deployment vllm -n default --replicas=1
```

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
ls -lh data/Strata-data/models/IQ2_XS/    # or IQ3_S/ on Blackwell
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
| `Exited (6)` / `GPU 1 cannot be used` | One-card host got `GPU=0,1`. Set `GPU=0`; see Troubleshooting. |

Logs may say **Downloading the draft layer (~5 GB)**. That is MTP (multi-token prediction): a small extra network that drafts upcoming tokens so the main model can verify several at once. Replies are often about twice as fast. It is not a second full model. Skip it only if you are short on memory (native: `--mtp off` or `DRAFTING=off`). On native 0.2.10, Qwen Auto picks **DFlash2** (~0.7 GB) on sm_86+ cards (Blackwell); V100 stays on MTP. DeepSeek uses **DSpark**, not DFlash2.

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

## Speed and metrics

Wait until `./scripts/status.sh` shows **healthy** and `/health` has `"loaded": true`. Two speeds:

| Name | What it is | Trust this field |
| --- | --- | --- |
| **Prompt tok/s** | How fast the model **reads** your input | `timing.prompt_per_second` on a **long fresh** prompt (thousands of tokens). A 50–70 token chat looks slow because of per-request overhead |
| **Decode tok/s** | How fast it **writes** the answer. This is “tokens per second” | `timing.predicted_per_second` on a generation of ~100+ tokens. MTP/DFlash2 drafts raise this when they are accepted |

Do not divide `completion_tokens` by wall-clock of a non-stream request unless you say so: that mix includes queue + prompt read.

### Live monitor

```bash
docker exec -it strata strata monitor          # q leaves; server keeps running
docker exec strata strata monitor --once       # one snapshot for scripts
# native:
strata monitor
```

While a request is in flight you see answer speed, prompt reading, GPU, VRAM, context fill. Idle: speed shows `--`.

### `GET /metrics`

Needs the API key. JSON is the Monitor’s source. Prometheus text (`Accept: text/plain`) uses vLLM names plus `strata:`.

```bash
set -a && source .env && set +a
curl -fsS -H "Authorization: Bearer ${API_KEY}" http://127.0.0.1:8080/metrics
curl -fsS -H "Authorization: Bearer ${API_KEY}" -H "Accept: text/plain" \
  http://127.0.0.1:8080/metrics
```

| JSON | Meaning |
| --- | --- |
| `live.tok_s` | Decode rate of the request in flight (`null` when idle) |
| `live.prefill_tok_s_mean` | Prompt-read rate while prefill is running |
| `totals.prompt_tokens` / `totals.prompt_ms` | Lifetime prompt tok/s = `1000 * prompt_tokens / prompt_ms` |
| `totals.output_tokens` / `totals.decode_ms` | Lifetime decode tok/s = `1000 * output_tokens / decode_ms` |
| `totals.drafts_offered` / `totals.drafts_accepted` | MTP (or other drafter) accept rate |
| `hardware.gpu_util`, VRAM in `hardware` | Cards |

Prometheus: `strata:live_tok_s`, `vllm:time_to_first_token_seconds`, `vllm:inter_token_latency_seconds`, `vllm:spec_decode_num_draft_tokens_total` / `_accepted_tokens_total`.

### One chat (engine `timing`)

```bash
set -a && source .env && set +a
curl -sS http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.8-flash-next-iq2_xs","temperature":0,"max_tokens":128,"messages":[{"role":"user","content":"Write a detailed technical paragraph about Tesla V100 GPUs. Do not stop early."}]}'
```

Read `timing`:

| Field | Meaning |
| --- | --- |
| `prompt_n` / `prompt_ms` / `prompt_per_second` | Prefill |
| `predicted_n` / `predicted_ms` / `predicted_per_second` | Decode |
| `draft_n` / `draft_n_accepted` | Drafter |

`python3 scripts/test_api.py --max-tokens 128` prints **wall-clock only**, not tok/s. For time-to-first-token, stream (`--stream`) and clock from the first `delta` to the last.

### Official bench (comparable suite)

Against the **already running** server (does not start a second engine). Native `strata` on `PATH` (`export PATH="$HOME/.local/bin:$PATH"`):

```bash
set -a && source .env && set +a
export STRATA_BENCH_KEY="$API_KEY"
strata bench run --url http://127.0.0.1:8080 --credential-env STRATA_BENCH_KEY --skip-model-hash
```

Reports decode tok/s, prompt tok/s at 4K/16K, and time to first token. Several minutes after load. `--skip-model-hash` skips hashing tens of GB of GGUFs (the run is then marked nonconforming). Help: `strata bench run --help`.

### This host (2× V100 IQ2_XS, Docker 0.2.9, one run)

Not a guarantee. First request after load is slower; ignore it.

| Workload | Prompt tok/s | Decode tok/s |
| --- | ---: | ---: |
| 128 new tokens, short prompt | overhead (~70 on 70 tokens) | **~98** (`predicted_per_second`); stream from first token **~103**; TTFT ~0.28 s |
| ~8K fresh prompt, 8 new tokens | **~775** | too few decode tokens to use |

RTX 5070 IQ2_XS in upstream docs is ~80 decode / ~2k prompt at 32K — Volta is the experimental CUDA 12 path.

## Switch model or context

1. `./scripts/stop.sh`
2. Edit `FAMILY`, `MODEL`, `CONTEXT`, `VISION`, or `GPU` in `.env`
3. `./scripts/plan.sh` and confirm disk/RAM
4. Launch again

Native and Docker can share GGUF files under `./data`, but prepared packs may still be created per runner. Prefer **one** runner to do the first download.

## DeepSeek V4.1-Flash (ISTA-DAS Coder)

Official engine: [DEEPSEEK41.md](https://github.com/Niko1221/Strata/blob/main/docs/DEEPSEEK41.md). This wrapper’s Coder profile is **native 0.2.10 on the Blackwell box**. Docker 0.2.9 has no Coder catalog entry. This V100 host has **no** official DeepSeek engine (CUDA 13 / sm_86+ only).

| Set | Download | Notes |
| --- | ---: | --- |
| **ISTA-DAS Coder** (this profile) | ~191 GB | 72 GB weights + 111 GB Engram + 8 GB DSpark. Coding/agent prune (192 of 384 experts) |
| 1.75 / 2.00 / 2.25 bpw | 239 / 257 / 274 GB | Full expert count; not the default here |

**Blackwell (the real path):**

```bash
# keep the existing API_KEY
cp .env.blackwell.deepseek.example .env
# restore API_KEY if the copy overwrote it
kubectl scale deployment vllm -n default --replicas=0
./scripts/plan.sh
# only if the plan names CUDA 13, ISTA-DAS-Coder, and ~191 GB:
./scripts/launch-native.sh
```

Scale vLLM back to 1 only after `./scripts/stop.sh`. Context default is **8k**. Empty `SPEED` lets the engine choose (Full quality on 32 GB). DeepSeek reads pictures with its own tower (`VISION=gpu` on that box).

**This V100 host:** copy `.env.v100.deepseek.example` only to run `./scripts/plan.sh`. Launch scripts refuse unless `STRATA_FORCE_UNSUPPORTED=1`. That can still download ~191 GB and then fail to serve. Do not clone or build `strata-dsv41` unless you explicitly want a source install.

## Rules

- Never commit `.env`, GGUFs, or `data/` payloads
- Never run native and Docker Strata together
- Always set `GPU` in `.env` (unset becomes `0,1`; one-card Blackwell needs `0`)
- Do not start a download unless you meant to launch (`plan.sh` is safe)
- Do not install GPU drivers or compilers as a side effect of `install-native.sh`

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| GPU OOM / engine dies at start | `./scripts/status.sh`; stop other CUDA jobs; keep `MODEL=IQ2_XS` on 16 GB cards |
| `GPU 1 cannot be used: not found` / container **Exited (6)** | One-card box (Blackwell) with missing `GPU=` — wrapper sent `0,1`. Set `GPU=0` in `.env`. `docker compose config` must show `GPU: "0"`. Details: `data/state/strata/launch/docker.setup.log`. Logs may still say `Main: GPU 1 RTX PRO 4500 Blackwell` (Strata’s card label). That is OK once it passes `Checking your computer` |
| Helm/K8s vLLM holds VRAM | `kubectl scale deployment vllm -n default --replicas=0`. Do not `kill` the engine; the ReplicaSet restarts it. Scale Strata down before setting replicas back to 1 |
| `strata: command not found` | `export PATH="$HOME/.local/bin:$PATH"` |
| Docker: could not select NVIDIA driver | install NVIDIA Container Toolkit, `sudo nvidia-ctk runtime configure --runtime=docker`, restart Docker |
| Plan / start says engine does not match the card | V100 → `cuda12` and `GPU=0,1`; RTX / Blackwell → `cuda13` and `GPU=0` |
| `Refusing DeepSeek on this CUDA 12 / Volta host` | Expected on this box. Use the Blackwell native Coder profile. Plan is allowed |
| `ISTA-DAS-Coder needs Strata 0.2.10` | Docker is still 0.2.9. Use `./scripts/launch-native.sh` on Blackwell after native 0.2.10 |
| Port in use | change `STRATA_PORT` or stop the other server |
| Download stalled | `docker compose logs -f` or native logs; restart launch — it resumes |
| `docker stop` exit 137 | already using `stop_grace_period: 2m`; wait; do not `kill -9` mid-unload |

Official: [TROUBLESHOOTING.md](https://github.com/Niko1221/Strata/blob/main/docs/TROUBLESHOOTING.md).
