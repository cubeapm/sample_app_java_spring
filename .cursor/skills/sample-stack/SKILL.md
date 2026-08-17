---
name: sample-stack
description: >-
  Start/stop/status the Datadog sample mesh (Java, Node, Python, PHP, .NET plus
  MySQL, Postgres, Redis, Kafka, RabbitMQ), list ports/APIs, and send HTTP
  traffic. Use when starting or stopping containers, checking stack status,
  hitting APIs, generating traffic, or asking which services/languages/ports exist.
---

# Sample stack (Datadog mesh)

Prefer these scripts. Do not invent `docker compose` / `curl` loops.

From **`cubeapm_root`**, prefix with `sample_app_java_spring/` (see workspace rule `sibling-skills`). From this repo, `./scripts/...` is fine.

## Commands

```bash
./scripts/stack.sh start      # ensure Docker (cloud), detached up, wait until apps ready
./scripts/stack.sh stop       # compose stop (warm restart later)
./scripts/stack.sh down       # compose down
./scripts/stack.sh status     # HTTP probes + compose table
./scripts/stack.sh catalog    # languages, ports, endpoints, APM names

./scripts/cloud-docker.sh ensure   # install/start Docker + bridge NAT; no-op on macOS
CUBEAPM_URL=https://<ngrok-host> ./scripts/stack.sh start

./scripts/traffic.sh 20                         # 20 hits, rotate local catalog on all apps
./scripts/traffic.sh 50 -s java,nodejs -p /mysql
./scripts/traffic.sh --rounds 5 --mesh          # 5 full local+peer sweeps
./scripts/traffic.sh 200 --bg                   # background; tmp/traffic.pid + .log
./scripts/traffic.sh status | stop
```

Legacy wrappers: `./hit_apis.sh [rounds]` → `--rounds N --mesh`; `./hit_test_apis.sh [N]` → `-p /call/all`.

## Agent rules

1. **One Shell call** for start. Waiting is inside `stack.sh` (including `cloud-docker.sh ensure`). Do not poll `docker ps`, invent `apt-get install docker`, or re-run start.
2. Use `block_until_ms` **180000** (warm) or **300000** (first build / cold). Cloud first start (Docker install + build): **420000**. Never run `docker compose up` without `-d`.
3. If start times out: run `./scripts/stack.sh status` once and report. Do not keep waiting.
4. To list APIs/ports: `./scripts/stack.sh catalog` or read [apis.md](apis.md). Do not grep service source unless catalog is wrong.
5. After `start` or `--bg` traffic, **end the turn**. Do not tail logs.
6. Stack stays up (`restart: always`). Later chats: `status` then `traffic.sh`.
7. Peer path token is **`nodejs`**, not `node`. Kafka/Rabbit names are **`topic-1`** and **`topic-2`** only.

## Cloud agents

If the compose user-bridge cannot assign IPs (nested ICC broken), `ensure` writes `tmp/cloud-net-mode=host` and `stack.sh start` applies `docker-compose.cloud.yml` (`network_mode: host` + `extra_hosts` so mysql-host/redis-host/etc. are 127.0.0.1). Egress for CubeAPM must be tested on the **compose/user bridge** (where `datadog-agent` runs), not docker0.

`host.docker.internal` on a cloud VM is **that VM**, not the user's laptop CubeAPM.

**Parent agent (before launching a cloud subagent):** stop and ask for a public CubeAPM URL (ngrok origin, no path). The user must already be tunneling CubeAPM (e.g. port 3130). Do not guess, do not reuse a URL from compose, do not use `http://host.docker.internal:3130`. Cloud subagents cannot ask the user; pass the URL in the prompt as `CUBEAPM_URL`.

**Cloud agent:** `CUBEAPM_URL=https://<ngrok> ./scripts/stack.sh start` (ingest POST probe; falls back to `http://` if HTTPS TCP fails) then `./scripts/traffic.sh 20`. Export skill: `datadog-agent-config`. Do not treat GET 200 to ngrok as proof of ingest.

## Quick facts

| App | Port | Probe |
|-----|------|--------|
| java | 8000 | `GET /external/1` → 200 |
| nodejs | 8001 | same |
| python | 8002 | same |
| php | 8003 | same |
| dotnet | 8004 | same |

- APM: Datadog agent, `DD_ENV=dd-ext2`. Details: [apis.md](apis.md)
- Agent export (Datadog vs CubeAPM): skill `datadog-agent-config` / `./scripts/dd-agent-config.sh`
