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
```

Local default URL: `http://host.docker.internal:3130`.
