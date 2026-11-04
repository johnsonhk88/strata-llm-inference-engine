# Project: strata-llm-inference-engine

Ops wrapper around official Strata (Niko1221/Strata). Do not clone or build the engine unless the user asks for a source install.

## Tech stack

- Official Strata Terminal (`strata launch`) installed to `~/.local/bin`
- Official Docker images `ghcr.io/niko1221/strata:<ver>-cuda12` (V100 / Pascal) and `…-cuda13` (RTX / Blackwell)
- Docker Compose, NVIDIA Container Toolkit

## Commands

- Native install: `./scripts/install-native.sh` (latest Terminal, currently 0.2.10). From 0.2.9 with DeepSeek, run `strata update` a second time for `engine-dsv41`.
- Plan (no download): `./scripts/plan.sh`
- Native serve: `./scripts/launch-native.sh`
- Docker serve: `./scripts/launch-docker.sh` (images pinned **0.2.9** until GHCR publishes 0.2.10)
- Status: `./scripts/status.sh`
- Stop: `./scripts/stop.sh`
- API smoke test: `python3 scripts/test_api.py`
- Tok/s: wait until `/health` `"loaded": true`. Live: `docker exec strata strata monitor --once`. Engine numbers: `timing.predicted_per_second` (decode) and `timing.prompt_per_second` (prompt) on `/v1/chat/completions`. JSON/Prometheus: `GET /metrics` with the API key. Suite: `strata bench run --url http://127.0.0.1:8080 --credential-env STRATA_BENCH_KEY --skip-model-hash`. Do not treat a short-prompt wall-clock as decode tok/s. Details: `docs/USAGE.md#speed-and-metrics`

## Boundaries

- Never commit `.env`, GGUF files, or `data/` contents
- Never start a model download without the user wanting a launch (plan is fine)
- Never run native and Docker Strata together
- Check GPU compute processes before launch (including Helm/K8s `vllm`; scale the deploy, do not only kill the PID)
- Keep the API on `127.0.0.1` unless the user asks to bind the LAN, and then require a real API key
- Do not install GPU drivers or build tools as a side effect of a normal Terminal install
- Do not copy a Blackwell `.env` onto this V100 machine (wrong CUDA image)
- Do not copy a V100 `.env` onto the Blackwell machine (`GPU=0,1` → Strata exit 6)
- Never leave `GPU` unset: Compose and `scripts/common.sh` default to `0,1`
- Do not launch DeepSeek on the V100 / CUDA 12 host (no official `strata-dsv41` package). `plan.sh` is allowed; `launch-*.sh` refuse unless `STRATA_FORCE_UNSUPPORTED=1`
- Do not Docker-launch `ISTA-DAS-Coder` on 0.2.9 images (catalog is 0.2.10). Native 0.2.10 on Blackwell is the path
- Do not start the ~191 GB Coder download unless the user asked to launch DeepSeek

## Defaults

- This host (2× V100-SXM2-16GB): `.env.v100.example` — family `qwen`, model `IQ2_XS`, context `32k`, vision `cpu`, image `0.2.9-cuda12`, `GPU=0,1`. Qwen Auto stays MTP (DFlash2 needs sm_86+)
- Other host (Blackwell, 1× RTX PRO 4500 32 GB): `.env.example` — image `0.2.9-cuda13`, `GPU=0`, vision `gpu`, model `IQ3_S`. Native 0.2.10 Auto picks DFlash2 for Qwen
- DeepSeek ISTA-DAS Coder: `.env.blackwell.deepseek.example` — family `deepseek41`, model `ISTA-DAS-Coder`, context `8k`, native 0.2.10, ~191 GB. Uses DSpark, not DFlash2
- V100 DeepSeek profile `.env.v100.deepseek.example` is plan-only
- Helm vLLM on the Blackwell box: `kubectl scale deployment vllm -n default --replicas=0` before Strata; scale back to 1 only after Strata is stopped
- Data dir: repo `./data`

## Docs

- `README.md` — first-run index
- `docs/USAGE.md` — full steps, API, speed and metrics
- `docs/V100.md` — dual Tesla V100
