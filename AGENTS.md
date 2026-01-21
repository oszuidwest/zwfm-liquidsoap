# Repository Guidelines

## Project Structure & Module Organization
- `conf/lib/` contains shared Liquidsoap modules (defaults, inputs, outputs, processing, DAB, server commands).
- `conf/*.liq` are station configs (`zuidwest.liq`, `rucphen.liq`, `bredanu.liq`) that compose the shared modules.
- `Dockerfile` and `docker-compose.yml` define the container image and runtime stack.
- `install.sh` bootstraps a production install; `.env` is expected at runtime.

## Build, Test, and Development Commands
- `docker compose up -d` starts the stack locally; `docker compose logs -f` tails logs.
- `docker buildx build --platform linux/amd64,linux/arm64 -t zwfm-liquidsoap:local .` builds the multi-arch image.
- `docker run --rm -v "$PWD:/app" -w /app savonet/liquidsoap:latest liquidsoap -c conf/*.liq` validates Liquidsoap syntax.
- `docker compose config --quiet` validates Compose configuration.

## Coding Style & Naming Conventions
- Liquidsoap is the primary language; keep functional, composable sources and prefer the existing factory functions in `conf/lib/`.
- Indentation in `.liq` files uses 2 spaces for wrapped arguments; keep comments short and descriptive.
- Formatting tools used by CI: `liquidsoap-prettier` for `.liq`, `prettier` for YAML, and `dclint` for Compose files.
- Linting tools: `shellcheck *.sh`, `hadolint Dockerfile`, `yamllint .`.

## Testing Guidelines
- There are no unit tests; quality is enforced via config validation and syntax checks.
- Run Liquidsoap validation before PRs: `liquidsoap -c conf/*.liq`.
- Use Docker logs to verify behavior during manual testing.

## Commit & Pull Request Guidelines
- Commits follow Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:` (e.g., `feat: switch to minimal base image`).
- PRs should include a short description, the reason for change, and the validation steps run (commands and results).
- If behavior or configuration changes, update documentation and note any required `.env` changes.

## Configuration & Security Notes
- Secrets are provided via environment variables; do not hardcode credentials in `.liq` or Compose files.
- Required env vars (e.g., `STATION_ID`, `ICECAST_HOST`, `SRT_PASSPHRASE`) have no defaults; document new required vars.
