# ComfyUI Shared Platform

This repository is the common deployment layer for:

- `192.168.1.129`
- `192.168.1.70`
- local development

It pins ComfyUI, Docker configuration, public custom nodes, workflows, startup behavior, and health checks. Model weights, user databases, inputs, outputs, caches, and secrets remain on each host and are mounted into the container.

The repository is the deployment control plane, not a copy of either
machine's current installation. Existing services remain available while a
new release is validated on a canary port.

## Deployment model

The same Git commit runs everywhere. Each instance has its own `.env` containing only host-specific paths, GPU visibility, port, and Compose project name.

Start new versions on a canary port such as `8288`. Do not stop the current `8188` or `8189` service until the canary passes API and workflow checks.

```bash
cp .env.example .env
./scripts/prepare-sources.sh
./scripts/bootstrap-host.sh
./scripts/canary-up.sh
```

If Docker Hub is unavailable on a host, set `CUDA_BASE_IMAGE` in `.env`
to an accessible registry mirror containing the same NVIDIA CUDA image.

For nodes with unreliable GitHub access, prepare and verify source archives
once on a connected machine, then copy them over the LAN:

```bash
./scripts/sync-sources.sh \
  hoson1@192.168.1.129:/home/hoson1/comfyui-platform \
  hsbd@192.168.1.70:/home/hsbd/comfyui-platform
```

The `vendor/` cache is excluded from Git. Its exact revisions are defined by
`config/comfyui.lock` and `config/custom-nodes.lock`.

The host Docker daemon must expose the `nvidia` runtime. GPU selection is
controlled by `GPU_IDS` through `NVIDIA_VISIBLE_DEVICES`.

Update an existing managed node:

```bash
./scripts/update-host.sh
./scripts/healthcheck.sh
```

## Multiple GPU workers

Use one checkout or Git worktree per service instance, or invoke Compose with a separate environment file and project name. Each instance gets:

- A unique `COMPOSE_PROJECT_NAME`
- A unique `COMFYUI_PORT`
- One or more `GPU_IDS`
- Shared read-only model storage when appropriate
- Separate user database and optional output path

## Git boundaries

Committed:

- ComfyUI release pin
- Container build
- Custom-node lock file
- Shared workflows
- Health and deployment scripts

Ignored:

- Model weights
- Generated media
- Inputs and temporary files
- User databases
- Passwords, tokens, and `.env`

Private nodes such as `hoson-pattern-extract` must be moved into a separate private repository before they can be included in the common image.

ComfyUI Manager is enabled through ComfyUI's native `--enable-manager`
option. It is intentionally not installed as a second legacy custom node.
