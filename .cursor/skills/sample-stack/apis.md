# APIs and ports

Datadog-instrumented mesh. Every app exposes the same local routes and proxies to the other four.

## Apps

| `-s` name | Language | Port | Base URL | `DD_SERVICE` |
|-----------|----------|------|----------|--------------|
| java | Spring Boot | 8000 | http://localhost:8000 | `cube_sample_java_spring_boot_datadog` |
| nodejs | Express | 8001 | http://localhost:8001 | `cube_sample_node_express_datadog` |
| python | Flask | 8002 | http://localhost:8002 | `cube_sample_python_flask_datadog` |
| php | PHP built-in | 8003 | http://localhost:8003 | `cube_sample_php_datadog` |
| dotnet | ASP.NET | 8004 | http://localhost:8004 | `cube_sample_dotnet_aspnet_datadog` |

`DD_ENV=dd-ext2`. Ready probe: `GET /external/1` → 200.

Peer URL token is **`nodejs`** (never `node`). Example: Java → Node error is `GET http://localhost:8000/nodejs/error`.

## Infra

| Service | Host port | Container / alias |
|---------|-----------|-------------------|
| mysql | 3306 | `cube_java_springboot_mysql` / `mysql-host` |
| postgres | 5432 | `cube_java_springboot_postgres` / `postgres-host` |
| redis | (internal) | `cube_java_springboot_redis` / `redis-host` |
| kafka | 9092 | `cube_java_springboot_kafka` / `kafka-host` |
| rabbitmq | 5672, UI 15672 | `cube_java_springboot_rabbitmq` / `rabbitmq-host` |
| datadog-agent | (internal 8126) | `datadog-agent` |

Kafka/Rabbit publish names: **`topic-1`**, **`topic-2`** only.

## Local endpoints (every app)

Source of truth: `scripts/endpoints.txt`

| Method | Path | Expect | Notes |
|--------|------|--------|-------|
| GET | `/external/{id}` | 200 | identity JSON |
| GET | `/error` | 500 | expected server error |
| GET | `/mysql` | 200 | `SELECT NOW()` |
| GET | `/redis` | 200 | set/get |
| GET | `/postgres` | 200 | `SELECT NOW()` |
| GET | `/publish/kafka/{topic}/{text}` | 200 | topic-1 or topic-2 |
| GET | `/publish/rabbit/{topic}/{text}` | 200 | topic-1 or topic-2 |
| GET | `/call/all` | 200 | GET `/external/all` on every peer |

## Peer proxy (every app → other langs)

`{lang}` ∈ `java` \| `nodejs` \| `python` \| `php` \| `dotnet` except self.

| Method | Path | Expect | Notes |
|--------|------|--------|-------|
| GET | `/{lang}/external/{id}` | 200 | outbound HTTP |
| GET | `/{lang}/error` | 200 | caller 200; peer returns 500 (client span) |
| GET | `/{lang}/mysql` | 200 | |
| GET | `/{lang}/redis` | 200 | |
| GET | `/{lang}/postgres` | 200 | |
| GET | `/{lang}/publish/kafka/{topic}/{text}` | 200 | |
| GET | `/{lang}/publish/rabbit/{topic}/{text}` | 200 | |

`/{lang}/error` is **200 on the caller**. The error is on the **peer server span** and the **caller client span** (when the tracer tags HTTP 5xx as error).

## Traffic

```bash
./scripts/traffic.sh 20                    # local catalog, all 5 apps
./scripts/traffic.sh 40 -s php -p /error
./scripts/traffic.sh --rounds 3 --mesh     # local + all peer proxies
./scripts/traffic.sh 30 -p /call/all
```
