#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ -f ".venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source ".venv/bin/activate"
fi

if [[ -z "${QT_QPA_PLATFORM:-}" ]]; then
  if [[ -n "${DISPLAY:-}" ]]; then
    export QT_QPA_PLATFORM=xcb
  else
    export QT_QPA_PLATFORM=eglfs
  fi
fi

export QT_QUICK_BACKEND="${QT_QUICK_BACKEND:-software}"
exec python -m vokrr_ui.main
