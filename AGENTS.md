# Project: strata-llm-inference-engine

Ops wrapper around official Strata (Niko1221/Strata). Do not clone or build the engine unless the user asks for a source install.

## Tech stack

- Official Strata Terminal (`strata launch`) installed to `~/.local/bin`
- Official Docker images `ghcr.io/niko1221/strata:<ver>-cuda12` (V100 / Pascal) and `…-cuda13` (RTX / Blackwell)
- Docker Compose, NVIDIA Container Toolkit

## Commands

- Native install: `./scripts/install-native.sh`
- Plan (no download): `./scripts/plan.sh`
- Native serve: `./scripts/launch-native.sh`
- Docker serve: `./scripts/launch-docker.sh`
- Status: `./scripts/status.sh`
- Stop: `./scripts/stop.sh`
- API smoke test: `python3 scripts/test_api.py`

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

## Defaults

- This host (2× V100-SXM2-16GB): `.env.v100.example` — family `qwen`, model `IQ2_XS`, context `32k`, vision `cpu`, image `cuda12`, `GPU=0,1`
- Other host (Blackwell, 1× RTX PRO 4500 32 GB): `.env.example` — image `cuda13`, `GPU=0`, vision `gpu`, model `IQ3_S`
- Helm vLLM on the Blackwell box: `kubectl scale deployment vllm -n default --replicas=0` before Strata; scale back to 1 only after Strata is stopped
- Data dir: repo `./data`

## Docs

- `README.md` — first-run index
- `docs/USAGE.md` — full steps and API
- `docs/V100.md` — dual Tesla V100
