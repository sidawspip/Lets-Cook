# XYNK production deployment on the MSI

## 1. Verify the MSI and Docker

In RDP at `192.168.0.29`, open **Applications → About Xfce → System**. This showed device `Xynk-Server`, Ubuntu 26.04.1 LTS (64-bit, Xubuntu), Xfce 4.20, Intel Core i7-9750H at 2.60 GHz with 12 logical CPUs, and 22.8 GiB RAM. In the same RDP session, open **File System** on the desktop. Thunar showed 422.9 GiB free at `/`. Docker access, its storage location, and existing containers are pending verification. No production services have been started. SSH on port 22 refused the connection. Run these commands in the MSI's Linux terminal to identify the host and check available resources and Docker access.

```bash
hostname
cat /etc/os-release
lscpu
free -h
df -h / /var/lib/docker 2>/dev/null
docker version
docker compose version
docker info --format '{{.DockerRootDir}}'
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
```

`docker version` needs to show both Client and Server. Review available space on the filesystem reported by `docker info` before restoring backups or building images. Inventory existing containers before selecting a Compose project name or reusing volumes.

In the MSI RDP terminal, `docker version` initially returned `command not found`. The command `sudo apt install docker.io docker-compose-v2` installed Ubuntu's Docker Engine 29.1.3 and Compose 2.40.3. Docker answered `sudo docker ps -a` and `sudo docker volume ls`. Both lists were empty before deployment.

The repository's `compose.msi.yaml` defines the production infrastructure. Its syntax was checked locally using `docker compose -f compose.msi.yaml config --quiet` with placeholder values. It uses the custom Keycloak build and binds its HTTP port to loopback for a host-based reverse proxy or tunnel. PostgreSQL and Redis have no published ports. Transfer the Compose file and `infra/keycloak/` together before using the manifest on the MSI.

## 2. Start PostgreSQL

On the MSI, PostgreSQL was started as `xynk-postgres` on `xynk-production` with no published port and persistent volume `xynk-production_postgres_data`. Its generated password is stored outside Git in `/home/home-server/xynk-secrets/postgres-password` and mounted read-only. `sudo docker exec xynk-postgres pg_isready -U postgres` reported accepting connections. The application and Keycloak databases still need provisioning or restore.

Use the repository's PostgreSQL 17 image and persistent storage. Use separate application and Keycloak databases and credentials. Keep both reachable over the Docker network. The current `infra/postgres/init.sql` creates `keycloak` only when PostgreSQL first initializes an empty data directory. For a fresh deployment, create the databases and roles before starting Keycloak. For a migration, take backups of both databases and restore them before starting consumers. Store production credentials on the MSI with restricted permissions. The existing Compose file references a Windows secrets path that needs an MSI-specific replacement.

Check PostgreSQL health with `pg_isready`, then authenticate to each database using its service account and run `SELECT current_database(), current_user;`. Confirm the restore before moving on.

## 3. Start Redis

Redis was started as `xynk-redis` on `xynk-production` with no published port and persistent volume `xynk-production_redis_data`. `sudo docker exec xynk-redis redis-cli ping` returned `PONG`. Both containers were launched directly. Before moving them under Compose, stop the direct containers and ensure Compose reuses their existing volumes without running two processes against either volume.

Use the repository's Redis 7.4 image with append-only persistence and a dedicated volume. Keep port 6379 on the Docker network. Check `redis-cli ping` returns `PONG`. Preserve any persistent Redis state required by the app if this is a migration.

## 4. Start Keycloak

Created the empty `keycloak` database on the MSI with `sudo docker exec xynk-postgres createdb -U postgres keycloak` and requested the base image `quay.io/keycloak/keycloak:26.8.0`. The database is initially owned by `postgres`. Create the dedicated `keycloak` login and assign it ownership before starting the service. The custom provider and Compose manifest are packaged in `artifacts/xynk-msi-infra.zip`. The MSI's `master` checkout does not contain those files.

Build the repository's custom Keycloak image from `infra/keycloak` so the X identity-provider mapper is available. Use Keycloak production mode with the public hostname `https://auth.xynk.in`. If TLS terminates at the reverse proxy, configure Keycloak to accept forwarded headers from that proxy and keep its HTTP listener private. Use the Keycloak database role from step 2. For a fresh deployment, review the realm export and supply production provider credentials on the MSI. For a migrated deployment, start against the restored Keycloak database.

Check startup and readiness, then verify `https://auth.xynk.in/realms/xynk/.well-known/openid-configuration` returns an issuer of `https://auth.xynk.in/realms/xynk`. Test sign-in and client redirects before moving any client traffic.

## 5. Deploy the applications

Sign in to GitHub when ready to connect the repository. Configure CI/CD to build and redeploy the backend and frontend based on their changed paths, with shared changes triggering both as needed. Deploy and verify the backend first, including database migrations, auth, Redis, and the existing LiveKit connection. Deploy the frontend to `xynk.in` and verify sign-in and a room flow. Build the Android APK and Windows release on the local laptop against the verified production endpoints.
