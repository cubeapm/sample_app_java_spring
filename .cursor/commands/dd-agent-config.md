Configure the sample-stack Datadog agent export (dual-ship to Datadog+CubeAPM, or CubeAPM only).

If the user did not give mode, CubeAPM URL, and (for dual) Datadog API key, ask first.

On a **cloud agent**, the URL must be a public ngrok origin (not `host.docker.internal`). Ask the user in the parent chat before launching the cloud agent.

Then run exactly one of:

```bash
./scripts/dd-agent-config.sh dual --url $URL --api-key $API_KEY
./scripts/dd-agent-config.sh cubeapm --url $URL
./scripts/dd-agent-config.sh cubeapm --url $URL --require-public
./scripts/dd-agent-config.sh probe
./scripts/dd-agent-config.sh show
```

Do not hand-edit compose. Do not `docker restart` (recreate is inside the script). Never print the API key. Return the script summary only.
