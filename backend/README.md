# Xynk backend API

The backend is a Java 21 / Spring Boot API using PostgreSQL, Flyway, Keycloak JWT authentication, STOMP WebSockets and LiveKit token issuance.

Read the full [backend architecture and development guide](../docs/BACKEND_ARCHITECTURE.md) before adding or moving functionality.

## Code convention

Every feature must follow:

```text
Controller → Service interface → Service implementation → Repository
```

- Controllers handle HTTP/STOMP transport and delegate.
- Service interfaces define use cases.
- Service implementations handle validation, authorization and orchestration.
- Repositories contain SQL, row mapping and provider-specific data access.
- Request and response records live in the feature's `Models` or `Dtos` class.

## Build and run

From the repository root:

```powershell
.\backend\scripts\dev\run.ps1
```

This launcher uses the root `compose.yaml` and `backend/Dockerfile`; Compose starts the required database, Redis, and Keycloak services. Run `docker compose build backend` separately when only an image build is needed.

Then verify the core flows:

```powershell
.\backend\scripts\dev\test-core-two-accounts.ps1
node .\backend\scripts\dev\test-notification-push.mjs
```

The API listens on <http://localhost:8080>. Health information is available at <http://localhost:8080/actuator/health>.
