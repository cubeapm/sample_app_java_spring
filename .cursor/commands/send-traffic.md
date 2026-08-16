Send HTTP traffic to the Datadog sample mesh (java, nodejs, python, php, dotnet).

Run:

```bash
./scripts/traffic.sh $ARGUMENTS
```

If `$ARGUMENTS` is empty, use `20` (request count across all apps). Examples: `20`, `50 -s java,nodejs -p /redis`, `--rounds 5 --mesh`, `200 --bg`.

Do not invent curl loops. Return the script summary only.
