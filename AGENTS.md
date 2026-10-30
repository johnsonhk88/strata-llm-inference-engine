# Project: strata-llm-inference-engine

Ops wrapper around official Strata (Niko1221/Strata). Do not clone or build the engine unless the user asks for a source install.

## Tech stack

- Official Strata Terminal (`strata launch`) installed to `~/.local/bin`
- Official Docker image `ghcr.io/niko1221/strata:<ver>-cuda13`
- Docker Compose, NVIDIA Container Toolkit, CUDA 13 / driver 580+

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

## Defaults

- Family `qwen`, model `IQ3_S`, context `32k`, vision `gpu`
- Data dir: repo `./data`
