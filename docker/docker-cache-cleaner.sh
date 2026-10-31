#!/usr/bin/env bash

docker system prune -af
docker image rm $(docker images -a -q)