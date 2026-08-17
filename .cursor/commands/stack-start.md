Start the Datadog sample mesh (detached) and wait until all five apps are ready.

`stack.sh start` also runs `cloud-docker.sh ensure` (install/start Docker + bridge NAT on cloud VMs; no-op on macOS).

Run exactly:

```bash
./scripts/stack.sh start
```

On a **cloud agent**, the parent must already have a public CubeAPM ngrok URL. Then:

```bash
CUBEAPM_URL=https://<ngrok-host> ./scripts/stack.sh start
```

Use a long block timeout (180s warm / 300s cold / **420s cloud first start**). Do not poll. Do not run `docker compose up` without `-d`. Do not invent `apt-get install docker`. Return the script summary only.
