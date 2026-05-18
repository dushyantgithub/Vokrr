#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

scripts/select_audio_output.sh
docker compose -f infra/docker-compose.yml up -d --force-recreate spotify-connect voice-listener
docker compose -f infra/docker-compose.yml ps spotify-connect voice-listener
