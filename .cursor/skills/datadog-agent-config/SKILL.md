---
name: datadog-agent-config
description: >-
  Configure the sample-stack Datadog agent to dual-ship traces/metrics to
  Datadog and CubeAPM, or to send only to CubeAPM. Use when the user mentions
  Datadog agent config, DD_API_KEY, DD_ADDITIONAL_ENDPOINTS, ngrok, CubeAPM
  intake URL, dual-ship, or switching export between Datadog and CubeAPM.
---

# Datadog agent export

Prefer `./scripts/dd-agent-config.sh`. From **`cubeapm_root`**, use `sample_app_java_spring/scripts/dd-agent-config.sh`. Do not hand-edit `docker-compose.yml` or run `docker restart` (env will not reload). Recreate the agent after every change.

## Ask first (do not guess)

If anything is missing, **stop and ask**. Do not reuse a key already in the file.

| Mode | Ask for |
|------|---------|
| **dual** (Datadog + CubeAPM) | CubeAPM base URL **and** Datadog `DD_API_KEY` |
| **cubeapm** (CubeAPM only) | CubeAPM base URL. API key optional (dummy `1234` if omitted) |

URL examples: `https://clicker-scenic-gallon.ngrok-free.dev` (cloud or laptop ngrok) or `http://host.docker.internal:3130` (**local Docker Desktop only**).

If the user did not pick a mode, ask: dual-ship vs CubeAPM-only.

### Cloud agents

A cloud VM cannot reach CubeAPM on the user's laptop. **Stop and ask** for a public HTTPS origin (ngrok) before starting the stack. Parent agent asks; cloud subagent only applies the given URL.

```bash
./scripts/dd-agent-config.sh cubeapm --url URL --require-public
# or
CUBEAPM_URL=https://<ngrok> ./scripts/stack.sh start
```

`--require-public` rejects `localhost` / `host.docker.internal`. Do not reuse the URL already in `docker-compose.yml`.

## Commands

```bash
./scripts/dd-agent-config.sh show
./scripts/dd-agent-config.sh dual --url URL --api-key KEY
./scripts/dd-agent-config.sh cubeapm --url URL
./scripts/dd-agent-config.sh cubeapm --url URL --api-key KEY
./scripts/dd-agent-config.sh cubeapm --url URL --require-public
./scripts/dd-agent-config.sh probe
./scripts/dd-agent-config.sh restart          # if applied with --no-restart
```

Default is to **force-recreate** `datadog-agent` after writing compose. Use `--no-restart` only if the user asked not to bounce it yet.

## Agent rules

1. One script invocation applies compose **and** recreates the agent.
2. Never print the API key. `show` already redacts it.
3. After apply, run `show` (or trust script output) and report **mode + URL** only.
4. Do not `docker compose up` the whole stack for this. Only `datadog-agent` is recreated.
5. Exact env blocks: [reference.md](reference.md).
