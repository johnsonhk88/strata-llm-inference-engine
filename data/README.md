# Model and runtime data

This folder is the shared library for both runners.

- **Docker** bind-mounts it at `/data` inside the container.
- **Native** `strata launch` uses `--data-dir` pointing here.

Do not commit GGUF files, packs, or keys. First IQ2_XS launch on this 2× V100 host downloads about 74 GB (model + MTP draft layer + picture reader). A Blackwell box should use its own `./data` unless you deliberately share GGUFs (see docs/V100.md).
