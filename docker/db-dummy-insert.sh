#!/usr/bin/env bash

set -euo pipefail

docker compose -f docker-compose.dev.yml exec database-mysql-server mysql --default-character-set=utf8mb4 -u root -p ocrdb && \
SOURCE /opt/db-verify/container-delivery-insert-db.sql;