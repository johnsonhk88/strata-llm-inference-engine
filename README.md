# Strata LLM inference

Local launch wrappers for [Niko1221/Strata](https://github.com/Niko1221/Strata): **native Terminal** and **Docker**, sharing `./data`.

This repo does not vendor the engine. It installs the official CLI and pulls the official NVIDIA image.

| Machine | Profile | Image | `GPU` |
| --- | --- | --- | --- |
| **This host** — 2× Tesla V100-SXM2-16GB, Volta sm_70, driver 580, ~62 GB RAM | `.env.v100.example` | `…:0.2.8-cuda12` — see [docs/V100.md](docs/V100.md) | `0,1` (required) |
| **Other host** — RTX PRO 4500 Blackwell 32 GB, CUDA 13, ~94 GB RAM | `.env.example` | `…:0.2.8-cuda13` | `0` (required) |

Do not copy a Blackwell `.env` onto this box. CUDA 13 cannot run Volta. Do not copy a V100 `.env` onto the Blackwell box (`GPU=0,1` exits 6 on one card).

If `GPU=` is missing, Compose and `scripts/common.sh` default to `0,1`. On the Blackwell box that is `strata: GPU 1 cannot be used` / container **Exited (6)**. Keep `GPU=0` from `.env.example`. Confirm with `docker compose config` (`GPU: "0"`).

**Guides:** [docs/USAGE.md](docs/USAGE.md) (full steps, API, troubleshooting) · [docs/V100.md](docs/V100.md) (dual V100)

---

## 1. One-time setup (this host)

1. NVIDIA driver **575.51+** (580 is fine), Docker, and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). Confirm `nvidia-smi` and `docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi`.
2. In this repo:

   ```bash
   cp .env.v100.example .env
   sed -i "s/^API_KEY=.*/API_KEY=$(openssl rand -hex 24)/" .env
   ./scripts/install-native.sh
   docker compose pull          # pulls cuda12 because of STRATA_IMAGE
   ```

3. Add `export PATH="$HOME/.local/bin:$PATH"` to your shell if `strata` is not found.
4. Inspect the download **without starting** the model:

   ```bash
   ./scripts/plan.sh
   ```

   Default here is ISTA-DASLab Qwen3.8-Flash-Next **IQ2_XS**, 32K, CPU vision, `GPU=0,1` (~74 GB first download: model + MTP draft layer + picture reader). The plan must name CUDA 12 / both V100s.

**Blackwell / RTX host** instead:

```bash
cp .env.example .env
sed -i "s/^API_KEY=.*/API_KEY=$(openssl rand -hex 24)/" .env
# keep GPU=0
docker compose pull          # pulls cuda13 because of STRATA_IMAGE
./scripts/plan.sh
```

IQ3_S first fetch is about **85 GB**. `GPU=` must stay `0`.

## 2. Free the GPU

Only **one** engine may own the cards. Stop native/Docker Strata, vLLM, or a Helm `vllm` deploy before launch. `kill` on the engine process is not enough if Kubernetes will recreate the pod.

```bash
./scripts/status.sh    # lists GPU compute processes
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
# If Helm vLLM owns the card (this Blackwell box):
# kubectl scale deployment vllm -n default --replicas=0
```

## 3. Launch (pick one)

**A. Docker** (this host’s usual path):

```bash
./scripts/launch-docker.sh
docker compose logs -f     # first start: model download, resumable
./scripts/status.sh
```

**B. Native Terminal** (best for `strata connect` / OpenCode):

```bash
./scripts/launch-native.sh
./scripts/status.sh
strata connect opencode
```

Do not run A and B at the same time. Compose `restart` is off so a reboot does not steal the GPU.

Run the scripts with **bash** (`./scripts/launch-docker.sh`). `sh ./scripts/…` fails (`set: Illegal option -o pipefail`).

## 4. Check Docker Strata is running

`docker compose up` succeeding is **not** the same as the API being ready. First start downloads ~74 GB, then prepares the pack, then loads the model. Until that finishes, health stays `starting` and `http://127.0.0.1:8080` is not reachable. `Ctrl+C` on `docker compose logs -f` only leaves the log view; the container keeps running.

**1. Container and health**

```bash
./scripts/status.sh
docker compose ps
```

| `STATUS` | Meaning |
| --- | --- |
| `Up … (health: starting)` | Container is alive. Model download/prepare/load is still in progress. API is down. |
| `Up … (healthy)` | Engine answered `/v1/models`. This is the “it works” signal. |
| `Exited` / `unhealthy` | Failed. Read `docker compose logs --tail 80` and `data/state/strata/launch/docker.setup.log`. Exit **6** with `GPU 1 cannot be used` means `.env` sent `0,1` to a one-card machine — set `GPU=0`. |

**2. API (only works when healthy)**

```bash
curl -fsS http://127.0.0.1:8080/health
python3 scripts/test_api.py
```

`/health` needs no key and should show `"loaded": true` and `"model": "qwen3.8-flash-next-iq2_xs"`. The Python script also checks `/v1/models` and a short chat (reads `API_KEY` from `.env`). Connection reset or refused = not serving yet (or crashed).

**3. Download still going?**

Compose logs often stay on “Getting your model ready” with no percent. Check the partial file instead:

```bash
docker compose logs --tail 50
ls -lh data/Strata-data/models/IQ2_XS/    # or IQ3_S/ on Blackwell
docker stats --no-stream strata    # NET I/O climbing = download
```

A growing `*.gguf.part` (and later a second `…-00002-of-00002.gguf.part`) means the fetch is working. After the model shards, Strata also downloads the **MTP draft layer** (~5 GB; speculative decoding, faster replies) and the picture reader. When `.part` files are gone and you have complete `.gguf` files, setup moves on to prepare + load.

**4. GPU**

```bash
nvidia-smi
```

If another job still holds most of the VRAM, Strata can download but will likely OOM when it tries to load. Stop the other engine first.

**5. Live monitor (after it is healthy)**

```bash
docker exec -it strata strata monitor
```

More detail: [docs/USAGE.md](docs/USAGE.md#check-docker-strata).

## 5. Use the API

- OpenAI-compatible: `http://127.0.0.1:8080/v1` with `Authorization: Bearer <API_KEY>`
- Anthropic-compatible: `http://127.0.0.1:8080` (client adds `/v1/messages`)
- `GET /health` needs no key
- Smoke test: `python3 scripts/test_api.py`

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
| `.env.v100.example` | This host: 2× V100 / CUDA 12 |
| `.env.example` | Other host: Blackwell / CUDA 13 / `GPU=0` |
| `docker-compose.yml` | Official image, bind-mount `./data`, localhost:8080 |
| `data/` | Shared model and runtime files |
| `scripts/` | install, plan, launch, stop, status, API smoke test |
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
| `python3 scripts/test_api.py` | Health, `/v1/models`, short chat (reads `.env`) |
