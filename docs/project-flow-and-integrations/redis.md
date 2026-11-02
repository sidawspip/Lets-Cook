# Redis setup

## Purpose in this stack

Redis is a separate in-network data store intended for fast/shared state. It is separate from PostgreSQL, which currently stores the application's durable room, membership, user, invite, and watch-party data. Redis is configured and started in this project, and LiveKit is configured to connect to it. **The backend currently has no Redis commands or feature-level Redis usage**: Spring Data Redis is a dependency and connection properties are set, but source search finds no `RedisTemplate`, `StringRedisTemplate`, cache annotations, or Redis repository. So adding Redis to Compose does not mean application features are currently storing data there. Persistence is enabled for the Redis container, but there is no production backup/access-control/high-availability plan in this repo.

## Current implementation

| File | Implementation |
|---|---|
| `compose.yaml` | Starts Redis 7.4 Alpine with append-only persistence, a `redis_data` named volume, an internal health check, and a host port mapping for local development. LiveKit depends on Redis health. |
| `backend/pom.xml` | Includes `spring-boot-starter-data-redis`; this provides integration libraries, but no current application code uses them. |
| `backend/src/main/resources/application.yml` | Spring Data Redis host and port defaults (`localhost:6379`); Compose overrides backend host to `redis`. |
| `infra/livekit/livekit.yaml` and `infra/livekit/livekit-public.yaml` | LiveKit uses the Docker service hostname `redis:6379`. |
| `compose.yaml` backend environment | Sets `SPRING_DATA_REDIS_HOST=redis` inside Compose. |

## Current usage by service

| Service | Current Redis use |
|---|---|
| Backend | Dependency and connection configuration exist. No feature currently reads/writes Redis; application persistence uses PostgreSQL through JDBC. |
| LiveKit | Both checked-in LiveKit configs point to `redis:6379`, and Compose starts Redis before LiveKit. This is the only explicit service-level Redis integration in the current runtime config. |
| Frontend | No direct Redis connection (correct: browsers should not connect to the datastore). |

## Local flow

1. Docker starts Redis and checks `redis-cli ping`.
2. Backend is configured with `redis:6379` but has no current feature code that opens/uses Redis commands. LiveKit is configured with the same internal address for its own coordination/state needs.
3. Redis writes append-only data under `/data`, backed by the `redis_data` Docker volume.
4. `docker compose down` keeps named-volume data. `docker compose down -v` deletes it, so only use that when intentionally resetting local data.

## Production setup steps

1. Decide whether Redis is a managed service or self-hosted. For managed Redis, use the provider hostname, TLS, and credentials. For self-hosting, keep Redis private on the service network and do not publish its port to the public Internet.
2. Set backend and LiveKit Redis connection settings through protected environment/secrets. Enable authentication and TLS as supported by the chosen deployment; rotate credentials and restrict network access.
3. Define persistence and recovery requirements. AOF is enabled locally, but configure snapshots/AOF policy, off-host backups, restore tests, storage monitoring, and retention for production.
4. Choose capacity and availability settings based on actual workload. Add monitoring for memory, evictions, connection count, latency, persistence, and health.
5. Verify application and LiveKit behavior after reconnect/restart. Do not assume ephemeral room/presence state should be restored like durable user data.

## If/when the backend starts using Redis

Choose a concrete feature first (for example rate limits, short-lived presence/cache, or a distributed coordination lock), define its expiry and failure behavior, then implement a dedicated repository/service and test it. Do not move durable room/account records from PostgreSQL into Redis by default. Update the Redis guide with the new feature, owning source files, key naming/TTL, and recovery semantics when such code is added.

## Future implementation notes

The checked-in setup has no Redis password, TLS, managed-service configuration, or backup automation. Keep those changes in deployment environment/configuration rather than adding credentials to source files. PostgreSQL migration and backup work remains separate from Redis configuration.
