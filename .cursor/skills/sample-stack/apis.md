# APIs and ports

## Services

| Service | Port | Base URL |
|---------|------|----------|
| java | 8000 | http://localhost:8000 |
| mysql | 3306 | container `cube_java_springboot_mysql` |
| redis | 6379 | container `cube_java_springboot_redis` (not published) |

Language: Java (Spring Boot).

## Endpoints

Source of truth: `scripts/endpoints.txt`

| Method | Path | Expect | Notes |
|--------|------|--------|-------|
| GET | `/` | 200 | index |
| GET | `/param/{param}` | 200 | path param (traffic uses `/param/sample`) |
| GET | `/api` | 200 | outbound HTTP to self |
| GET | `/redis` | 200 | redis cache |
| GET | `/all` | 200 | list mysql users |
| POST | `/mysql/add?name=&email=` | 200 | insert user |
| GET | `/exception` | 500 | expected error |

## Traffic

```bash
./scripts/traffic.sh 20              # 20 requests, rotating catalog
./scripts/traffic.sh 50 -p /mysql    # only mysql-related paths
./scripts/traffic.sh --rounds 3      # 3 full catalog sweeps
```
