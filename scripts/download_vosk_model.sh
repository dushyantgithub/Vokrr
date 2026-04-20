#!/usr/bin/env bash
set -euo pipefail

MODEL_URL="${MODEL_URL:-https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip}"
MODEL_DIR="${MODEL_DIR:-/home/quantum-hive/Projects/quantum-home/voice-pipeline/models}"
TARGET_DIR="${MODEL_DIR}/vosk"
TMP_ZIP="/tmp/vosk-model.zip"

mkdir -p "${MODEL_DIR}"

if [[ -d "${TARGET_DIR}" ]]; then
  echo "Vosk model already present at ${TARGET_DIR}"
  exit 0
fi

curl -L "${MODEL_URL}" -o "${TMP_ZIP}"
unzip -q "${TMP_ZIP}" -d "${MODEL_DIR}"
EXTRACTED="$(find "${MODEL_DIR}" -maxdepth 1 -type d -name 'vosk-model-*' | head -n 1)"
if [[ -z "${EXTRACTED}" ]]; then
  echo "Could not find extracted Vosk model" >&2
  exit 1
fi
mv "${EXTRACTED}" "${TARGET_DIR}"
rm -f "${TMP_ZIP}"
echo "Installed Vosk model at ${TARGET_DIR}"

