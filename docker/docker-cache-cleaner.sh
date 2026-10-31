#!/usr/bin/env bash


docker compose down -v
docker volume prune -a -f
docker image prune -a -f
docker system prune -a -f