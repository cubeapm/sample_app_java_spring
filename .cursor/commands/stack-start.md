Start the Datadog sample mesh (detached) and wait until all five apps are ready.

Run exactly:

```bash
./scripts/stack.sh start
```

Use a long block timeout (180s warm / 300s cold). Do not poll. Do not run `docker compose up` without `-d`. Return the script summary only.
