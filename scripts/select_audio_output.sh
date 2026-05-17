#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ENV="${VOKRR_AUDIO_OUTPUT_ENV:-${ROOT_DIR}/backend/data/audio-output.env}"
FALLBACK_DEVICE="${VOKRR_AUDIO_FALLBACK_DEVICE:-plughw:CARD=MAX98357A,DEV=0}"

usage() {
  cat <<'EOF'
Usage: select_audio_output.sh [--test]

Detects the preferred ALSA playback device for Vokrr and writes an env file.
Priority is aux/headphone/USB playback first, then MAX98357A fallback.
EOF
}

test_output=0
for arg in "$@"; do
  case "${arg}" in
    --test) test_output=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: ${arg}" >&2; usage >&2; exit 2 ;;
  esac
done

sanitize_env_value() {
  printf '%s' "$1" | tr -d '\r' | sed 's/[[:space:]]*$//'
}

detect_device() {
  local best_kind="" best_card="" best_dev="" best_label="" best_priority=999
  local line card_id dev label card_desc priority kind

  while IFS= read -r line; do
    [[ "${line}" =~ ^card[[:space:]]+([0-9]+):[[:space:]]+([^[:space:]]+)[[:space:]]+\[([^]]+)\],[[:space:]]+device[[:space:]]+([0-9]+):[[:space:]]+(.+)$ ]] || continue
    card_id="${BASH_REMATCH[2]}"
    card_desc="${BASH_REMATCH[3]}"
    dev="${BASH_REMATCH[4]}"
    label="${BASH_REMATCH[5]}"
    priority=999
    kind="unknown"

    if [[ "${card_id} ${card_desc} ${label}" =~ MAX98357A ]]; then
      priority=90
      kind="max98357a"
    elif [[ "${card_id} ${card_desc} ${label}" =~ [Hh]ead(phone|set)|[Aa]nalog|[Aa]ux ]]; then
      priority=10
      kind="aux"
    elif [[ "${card_id} ${card_desc} ${label}" =~ USB|usb|PnP|PCM2902|C-Media ]] &&
         [[ ! "${card_id} ${card_desc} ${label}" =~ Webcam|webcam|046d|Logitech ]]; then
      priority=20
      kind="aux"
    elif [[ "${VOKRR_AUDIO_ALLOW_HDMI:-0}" == "1" ]] &&
         [[ "${card_id} ${card_desc} ${label}" =~ HDMI|hdmi|vc4 ]]; then
      priority=80
      kind="hdmi"
    fi

    if (( priority < best_priority )); then
      best_priority="${priority}"
      best_kind="${kind}"
      best_card="${card_id}"
      best_dev="${dev}"
      best_label="${card_desc} ${label}"
    fi
  done < <(aplay -l 2>/dev/null || true)

  if [[ -n "${best_card}" && "${best_priority}" != "999" ]]; then
    printf '%s\t%s\t%s\n' "plughw:CARD=${best_card},DEV=${best_dev}" "${best_kind}" "${best_label}"
  else
    printf '%s\t%s\t%s\n' "${FALLBACK_DEVICE}" "max98357a" "fallback"
  fi
}

IFS=$'\t' read -r device kind label < <(detect_device)
device="$(sanitize_env_value "${device}")"
kind="$(sanitize_env_value "${kind}")"
label="$(sanitize_env_value "${label}")"

mkdir -p "$(dirname "${OUTPUT_ENV}")"
tmp_file="$(mktemp "${OUTPUT_ENV}.XXXXXX")"
{
  printf 'DEVICE=%s\n' "${device}"
  printf 'VOICE_OUTPUT_DEVICE=%s\n' "${device}"
  printf 'VOKRR_AUDIO_DEVICE=%s\n' "${device}"
  printf 'VOKRR_AUDIO_OUTPUT_KIND=%s\n' "${kind}"
  printf 'VOKRR_AUDIO_OUTPUT_LABEL=%q\n' "${label}"
} > "${tmp_file}"
mv "${tmp_file}" "${OUTPUT_ENV}"

echo "Selected Vokrr audio output: ${device} (${kind}: ${label})"

if (( test_output )); then
  echo "Playing a 3-second test tone on ${device}..."
  timeout 3s speaker-test -D "${device}" -c2 -t sine -f 1000 -r 48000
fi
