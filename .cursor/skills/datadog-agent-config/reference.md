# Datadog agent export blocks

Markers in `docker-compose.yml`: `# BEGIN DD_AGENT_EXPORT` … `# END DD_AGENT_EXPORT`.

CubeAPM additional-endpoint dummy key is always `1234`.

## dual (Datadog + CubeAPM)

Keeps `DD_SITE` (default `us5.datadoghq.com`) and dual-ships via additional endpoints. CubeAPM `DD_DD_URL` lines stay **commented**.

```yaml
- DD_API_KEY=<user Datadog API key>
- DD_SITE=us5.datadoghq.com
- DD_ADDITIONAL_ENDPOINTS={"<cubeapm-url>":["1234"]}
- DD_APM_ADDITIONAL_ENDPOINTS={"<cubeapm-url>":["1234"]}
```

`<cubeapm-url>` is the origin only (no path), e.g. `https://clicker-scenic-gallon.ngrok-free.dev`.

## cubeapm (CubeAPM only)

Comments `DD_SITE` / `DD_ADDITIONAL_ENDPOINTS`. Sets intake URLs to the user-provided CubeAPM base.

```yaml
- DD_API_KEY=<user key or 1234>
- DD_DD_URL=<cubeapm-url>
- DD_APM_DD_URL=<cubeapm-url>
- DD_LOGS_CONFIG_LOGS_DD_URL=<cubeapm-url>
- DD_LOGS_ENABLED=true
- DD_LOGS_INJECTION=true
- DD_LOGS_CONFIG_USE_HTTP=true
- DD_LOGS_CONFIG_LOGS_NO_SSL=true   # only when URL is http://
- DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true
- DD_FORWARDER_TIMEOUT=60
- DD_FORWARDER_NUM_WORKERS=1
- DD_SKIP_SSL_VALIDATION=true
- DD_LOGS_CONFIG_BATCH_WAIT=5
```

Local default URL: `http://host.docker.internal:3130`.

Cloud / ngrok: origin only, publicly reachable HTTPS, e.g. `https://clicker-scenic-gallon.ngrok-free.dev`. Never `host.docker.internal` on a cloud VM (that is the VM loopback, not the laptop).

Ingest check: `./scripts/dd-agent-config.sh probe` POSTs `/intake/` from inside `datadog-agent`. Do not treat a GET 200 as proof of ingest.
