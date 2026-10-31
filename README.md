# Main Project for Infra Manager

## Development web proxy

The web container forwards `/api` requests to
`http://spring-boot-application:60001` through `VITE_API_PROXY_TARGET`.
Inside the web container, `localhost` refers to the web container itself, not
Spring. Spring does not need a published host port for this connection.

## Development database storage

In [the development Compose configuration](docker/docker-compose.dev.yml), MySQL
uses `database-data`, while Qdrant retains the existing `default` volume.
Never mount the same data volume into both database services.

Spring waits for an authenticated MySQL health check before starting.
Initialization scripts run only when MySQL initializes an empty data directory.

When separating an existing shared volume, inspect and back up its contents first.
The new MySQL volume does not automatically migrate old MySQL data.
Do not use `docker compose down --volumes` when preserving database data.

From the repository root, validate and start the database with:

```powershell
docker compose --env-file .\docker\.env -f .\docker\docker-compose.dev.yml config --quiet
docker compose --env-file .\docker\.env -f .\docker\docker-compose.dev.yml up -d --wait database-mysql-server
```
