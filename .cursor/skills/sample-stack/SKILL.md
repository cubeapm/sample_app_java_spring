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

## Commands

```bash
./scripts/stack.sh start      # detached up + wait until all 5 apps ready
./scripts/stack.sh stop       # compose stop (warm restart later)
./scripts/stack.sh down       # compose down
./scripts/stack.sh status     # HTTP probes + compose table
./scripts/stack.sh catalog    # languages, ports, endpoints, APM names

./scripts/traffic.sh 20                         # 20 hits, rotate local catalog on all apps
./scripts/traffic.sh 50 -s java,nodejs -p /mysql
./scripts/traffic.sh --rounds 5 --mesh          # 5 full local+peer sweeps
./scripts/traffic.sh 200 --bg                   # background; tmp/traffic.pid + .log
./scripts/traffic.sh status | stop
```

Legacy wrappers: `./hit_apis.sh [rounds]` → `--rounds N --mesh`; `./hit_test_apis.sh [N]` → `-p /call/all`.

## Agent rules

1. **One Shell call** for start. Waiting is inside `stack.sh`. Do not poll `docker ps` or re-run start.
2. Use `block_until_ms` **180000** (warm) or **300000** (first build / cold). Never run `docker compose up` without `-d`.
3. If start times out: run `./scripts/stack.sh status` once and report. Do not keep waiting.
4. To list APIs/ports: `./scripts/stack.sh catalog` or read [apis.md](apis.md). Do not grep service source unless catalog is wrong.
5. After `start` or `--bg` traffic, **end the turn**. Do not tail logs.
6. Stack stays up (`restart: always`). Later chats: `status` then `traffic.sh`.
7. Peer path token is **`nodejs`**, not `node`. Kafka/Rabbit names are **`topic-1`** and **`topic-2`** only.

## Quick facts

| App | Port | Probe |
|-----|------|--------|
| java | 8000 | `GET /external/1` → 200 |
| nodejs | 8001 | same |
| python | 8002 | same |
| php | 8003 | same |
| dotnet | 8004 | same |

- APM: Datadog agent, `DD_ENV=dd-ext2`. Details: [apis.md](apis.md)
