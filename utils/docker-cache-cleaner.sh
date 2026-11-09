#!/usr/bin/env bash

docker builder prune --all --force
docker buildx prune -f

docker system prune -f
docker system prune --volumes -af