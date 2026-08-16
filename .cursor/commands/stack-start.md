Start the sample Docker stack (detached) and wait until ready.

Run exactly:

```bash
./scripts/stack.sh start
```

Use a long block timeout (120s warm / 180s cold). Do not poll. Do not run `docker compose up` without `-d`. Return the script summary only.
