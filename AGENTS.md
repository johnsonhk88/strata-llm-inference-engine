# Project: strata-llm-inference-engine

Ops wrapper around official Strata (Niko1221/Strata). Do not clone or build the engine unless the user asks for a source install.

## Tech stack

- Official Strata Terminal (`strata launch`) installed to `~/.local/bin`
- Official Docker images `ghcr.io/niko1221/strata:<ver>-cuda13` (RTX / Blackwell) and `…-cuda12` (V100 / Pascal)
- Docker Compose, NVIDIA Container Toolkit

## Commands

- Native install: `./scripts/install-native.sh`
- Plan (no download): `./scripts/plan.sh`
- Native serve: `./scripts/launch-native.sh`
- Docker serve: `./scripts/launch-docker.sh`
- Status: `./scripts/status.sh`
- Stop: `./scripts/stop.sh`

## Boundaries

- Never commit `.env`, GGUF files, or `data/` contents
- Never start a model download without the user wanting a launch (plan is fine)
- Never run native and Docker Strata together
- Check GPU compute processes before launch; this host often has vLLM using VRAM
- Keep the API on `127.0.0.1` unless the user asks to bind the LAN, and then require a real API key
- Do not install GPU drivers or build tools as a side effect of a normal Terminal install
- Do not copy this host’s `.env` onto a V100 machine (wrong CUDA image)

## Defaults

- This host: family `qwen`, model `IQ3_S`, context `32k`, vision `gpu`, image `cuda13`, `GPU` empty
- 2× V100: `.env.v100.example` — image `cuda12`, `GPU=0,1`, vision `cpu`, model `IQ2_XS`
- Data dir: repo `./data`

## Docs

- `README.md` — first-run index
- `docs/USAGE.md` — full steps and API
- `docs/V100.md` — dual Tesla V100
