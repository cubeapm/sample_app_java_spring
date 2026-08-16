Send HTTP traffic to the sample stack.

Run:

```bash
./scripts/traffic.sh $ARGUMENTS
```

If `$ARGUMENTS` is empty, use `20` (request count). Examples: `20`, `50 -p /redis`, `200 --bg`, `--rounds 5`.

Do not invent curl loops. Return the script summary only.
