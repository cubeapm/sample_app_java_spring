---
name: sample-stack
description: >-
  Start/stop/status the sample app Docker stack, list languages/ports/APIs, and
  send N HTTP requests. Use when starting or stopping containers, checking stack
  status, hitting APIs, generating traffic, or asking which services/ports exist.
---

# Sample stack

Prefer these scripts. Do not invent `docker compose` / `curl` loops.

## Commands

```bash
./scripts/stack.sh start      # detached up + wait until ready; then exits
./scripts/stack.sh stop       # compose stop (warm restart later)
./scripts/stack.sh down       # compose down
./scripts/stack.sh status     # compact HTTP + compose table
./scripts/stack.sh catalog    # languages, ports, endpoints

./scripts/traffic.sh 20                    # N = HTTP request count (default 20)
./scripts/traffic.sh 50 -s java -p /redis
./scripts/traffic.sh 10 -p /api
./scripts/traffic.sh --rounds 5            # legacy full-catalog sweeps
./scripts/traffic.sh 200 --bg              # background; tmp/traffic.pid + .log
./scripts/traffic.sh status | stop
```

## Agent rules

1. **One Shell call** for start. Waiting is inside `stack.sh`. Do not poll `docker ps` or re-run start.
2. Use `block_until_ms` **120000** (warm) or **180000** (first build / cold). Never run `docker compose up` without `-d`.
3. If start times out: run `./scripts/stack.sh status` once and report. Do not keep waiting.
4. To list APIs/ports: `./scripts/stack.sh catalog` or read [apis.md](apis.md). Do not grep service source.
5. After `start` or `--bg` traffic, **end the turn**. Do not tail logs.
6. Stack stays up in the background (`restart: always`). Later chats: `status` then `traffic.sh`.

## Quick facts

- App: **java** on **http://localhost:8000**
- Infra: mysql `:3306`, redis (internal)
- Ready probe: `GET /` → 200
- Details: [apis.md](apis.md)
