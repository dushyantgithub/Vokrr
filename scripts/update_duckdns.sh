#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ -f scripts/.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source scripts/.env
  set +a
elif [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DUCK_DNS_TOKEN="${DUCK_DNS_TOKEN:-}"
DUCK_DNS_DOMAIN="${DUCK_DNS_DOMAIN:-}"

if [[ -z "${DUCK_DNS_TOKEN}" || -z "${DUCK_DNS_DOMAIN}" ]]; then
  echo "DUCK_DNS_TOKEN and DUCK_DNS_DOMAIN must be set" >&2
  exit 1
fi

DUCK_DNS_SUBDOMAIN="${DUCK_DNS_DOMAIN%%.duckdns.org}"
if [[ -z "${DUCK_DNS_SUBDOMAIN}" || "${DUCK_DNS_SUBDOMAIN}" == "${DUCK_DNS_DOMAIN}" ]]; then
  echo "DUCK_DNS_DOMAIN must be a duckdns.org hostname" >&2
  exit 1
fi

response="$(
  curl -fsS "https://www.duckdns.org/update?domains=${DUCK_DNS_SUBDOMAIN}&token=${DUCK_DNS_TOKEN}&ip="
)"

if [[ "${response}" != "OK" ]]; then
  echo "DuckDNS update failed: ${response}" >&2
  exit 1
fi

echo "DuckDNS updated for ${DUCK_DNS_DOMAIN}"
