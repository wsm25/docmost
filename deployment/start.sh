#!/usr/bin/env bash
podman compose --env-file .env -f docker-compose.yml up -d --build
