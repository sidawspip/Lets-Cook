# Let's Cook backend

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
docker compose build backend
docker compose up -d --force-recreate backend
```

Then verify the core flows:

```powershell
.\scripts\test-core-two-accounts.ps1
node .\scripts\test-notification-push.mjs
```

The API listens on <http://localhost:8080>. Health information is available at <http://localhost:8080/actuator/health>.
