# Heartsteel Beta

Roblox/Luau helper project for Saber Simulator.

## Repository layout

```text
src/
  testing.lua        # current main runnable script
  healthcheck.lua    # executor-side health probe

tools/
  eggdump.lua        # standalone investigation/debug scripts
  raritydump.lua
  webhook-standalone.lua

docs/
  dumps/
  prompts/

PROJECT_CONTEXT.md
```

## Branch strategy

- `main` → stable builds only
- `dev` → active testing
- `feature/*` → major rewrites/features

Suggested branches:

```text
feature/github-loader
feature/split-modules
feature/event-eggs
feature/health-api
```

## Future goals

- Split monolithic testing.lua into modules
- GitHub-based loader/update system
- Cleaner event egg tracking
- Better health monitoring
- Easier debugging + maintenance
