#!/usr/bin/env bash


docker compose -f docker-compose.dev.yml down -v
docker logs prune -f
docker build prune -f
docker volume prune -a -f
docker image prune -a -f
docker system prune -a -f