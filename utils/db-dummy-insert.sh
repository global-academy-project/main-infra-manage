#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/../docker/docker-compose.dev.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
	printf 'Compose file not found: %s\n' "$COMPOSE_FILE" >&2
	exit 1
fi

docker compose -f "$COMPOSE_FILE" exec database-mysql-server mysql --default-character-set=utf8mb4 -u root -p ocrdb <<'EOF'
SOURCE /opt/db-verify/container-delivery-insert-db.sql;
EOF