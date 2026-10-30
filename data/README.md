# Model and runtime data

This folder is the shared library for both runners.

- **Docker** bind-mounts it at `/data` inside the container.
- **Native** `strata launch` uses `--data-dir` pointing here.

Do not commit GGUF files, packs, or keys. First IQ3_S launch on this host downloads about 90 GB (model + draft layer + picture reader). A 2× V100 box should use its own `./data` unless you deliberately share GGUFs (see docs/V100.md).
