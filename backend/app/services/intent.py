import logging
import re
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path
from typing import TypeVar

import yaml

from app.domain.models import Capability, Device, DeviceSetRequest, VoiceCommandResponse
from app.services.device_service import DeviceService, UnsupportedCapabilityError

logger = logging.getLogger(__name__)
FUZZY_MATCH_THRESHOLD = 0.80
T = TypeVar("T")


@dataclass(frozen=True)
class CommandMatch:
    action: str
    target: str
    percent: int | None = None
    view: str | None = None


class CommandCatalog:
    def __init__(self, config_path: str) -> None:
        self.config_path = Path(config_path)
        self.patterns: list[tuple[str, str, re.Pattern[str], str | None]] = []
        self.load()

    def load(self) -> None:
        raw = yaml.safe_load(self.config_path.read_text()) if self.config_path.exists() else {}
        patterns: list[tuple[str, str, re.Pattern[str], str | None]] = []
        for intent in (raw or {}).get("intents", {}).values():
            action = intent["action"]
            view = intent.get("view")
            for template in intent.get("templates", []):
                patterns.append((action, template, compile_template(template), view))
        self.patterns = patterns

    def match(self, normalized: str) -> CommandMatch | None:
        for action, _template, pattern, view in self.patterns:
            match = pattern.fullmatch(normalized)
            if not match:
                continue
            target = normalize_text(match.groupdict().get("target", "") or "")
            percent_text = match.groupdict().get("percent")
            percent = clamp_percent(int(percent_text)) if percent_text is not None else None
            return CommandMatch(action=action, target=target, percent=percent, view=view)
        return None

    def commands(self) -> list[dict[str, str]]:
        commands: list[dict[str, str]] = []
        for action, template, _pattern, _view in self.patterns:
            commands.append({"action": action, "template": template})
        return commands


class IntentService:
    def __init__(self, device_service: DeviceService, command_catalog: CommandCatalog) -> None:
        self.device_service = device_service
        self.command_catalog = command_catalog

    async def handle(self, text: str) -> VoiceCommandResponse:
        normalized = clean_user_utterance(text)
        logger.info("voice.intent: raw=%r normalized=%r", text, normalized)
        if not normalized:
            return VoiceCommandResponse(understood=False, message="I did not hear a command.")

        command = self.command_catalog.match(normalized) or self._fallback_match(normalized)
        if not command:
            logger.info("voice.intent: no template or fallback matched normalized=%r", normalized)
            return VoiceCommandResponse(
                understood=False,
                message="I did not understand that command.",
            )

        logger.info(
            "voice.intent: matched action=%s target=%r percent=%s view=%s",
            command.action,
            command.target,
            command.percent,
            command.view,
        )

        if command.action == "navigate":
            view = command.view or "Dashboard"
            return VoiceCommandResponse(
                understood=True,
                message=f"Opening {view}.",
                navigate=view,
            )

        target_devices = self._match_target(command.target)
        if not target_devices:
            logger.info(
                "voice.intent: target %r did not resolve to any device", command.target
            )
            return VoiceCommandResponse(
                understood=False,
                message=f"I could not find {command.target}.",
            )
        logger.info(
            "voice.intent: resolved target=%r -> %s",
            command.target,
            [device.id for device in target_devices],
        )

        changed: list[str] = []
        errors: list[str] = []
        for device in target_devices:
            try:
                await self._apply(device, command)
                changed.append(device.id)
            except UnsupportedCapabilityError as exc:
                errors.append(str(exc))

        if not changed:
            return VoiceCommandResponse(
                understood=False,
                message=errors[0] if errors else "I could not update that device.",
            )

        return VoiceCommandResponse(
            understood=True,
            message=f"Done. Updated {len(changed)} device{'s' if len(changed) != 1 else ''}.",
            matched_device_ids=changed,
        )

    async def _apply(self, device: Device, command: CommandMatch) -> None:
        if command.action == "turn_on":
            await self.device_service.set_device(device.id, DeviceSetRequest(state=True))
        elif command.action == "turn_off":
            await self.device_service.set_device(device.id, DeviceSetRequest(state=False))
        elif command.action == "toggle":
            await self.device_service.toggle(device.id)
        elif command.action == "set_level":
            percent = command.percent if command.percent is not None else 100
            payload = (
                DeviceSetRequest(brightness=percent)
                if device.type.value == "light"
                else DeviceSetRequest(percentage=percent)
            )
            await self.device_service.set_device(device.id, payload)
        elif command.action == "warm":
            await self.device_service.set_device(device.id, DeviceSetRequest(rgb_color=[255, 180, 90]))
        elif command.action == "white":
            await self.device_service.set_device(device.id, DeviceSetRequest(rgb_color=[255, 255, 255]))
        elif command.action == "cool":
            await self.device_service.set_device(device.id, DeviceSetRequest(rgb_color=[80, 150, 255]))
        else:
            raise UnsupportedCapabilityError(f"Unsupported command action {command.action}")

    def _match_target(self, target: str) -> list[Device]:
        devices = self.device_service.devices()
        rooms = self.device_service.rooms()
        target = normalize_text(target)

        if target in {"all", "everything", "home"}:
            return [device for device in devices if Capability.toggle in device.capabilities]

        room_matches = [
            room
            for room in rooms
            if _literal_match(target, normalize_text(room.name)) or room.id == slugify(target)
        ]
        if not room_matches:
            fuzzy_room = _best_fuzzy_match(
                target,
                [(room, [room.name, room.id.replace("_", " ")]) for room in rooms],
            )
            if fuzzy_room is not None:
                room_matches = [fuzzy_room]
        if room_matches:
            room_ids = {room.id for room in room_matches}
            return [
                device
                for device in devices
                if device.room_id in room_ids and Capability.toggle in device.capabilities
            ]

        exact_matches = [
            device
            for device in devices
            if _literal_match(target, normalize_text(device.name))
            or _literal_match(target, normalize_text(f"{device.room_name} {device.name}"))
            or _literal_match(target, normalize_text(device.id.replace("_", " ")))
            or _literal_match(
                target, normalize_text(device.entity_id.replace(".", " ").replace("_", " "))
            )
        ]
        if exact_matches:
            return exact_matches

        target_folded = _space_fold(target)
        contains_matches = [
            device
            for device in devices
            if target in normalize_text(f"{device.room_name} {device.name}")
            or target in normalize_text(device.id.replace("_", " "))
            or target_folded
            in _space_fold(normalize_text(f"{device.room_name} {device.name}"))
            or target_folded in _space_fold(normalize_text(device.id.replace("_", " ")))
        ]
        if len(contains_matches) == 1:
            return contains_matches

        fuzzy_device = _best_fuzzy_match(
            target,
            [
                (
                    device,
                    [
                        device.name,
                        f"{device.room_name} {device.name}",
                        device.id.replace("_", " "),
                        device.entity_id.replace(".", " ").replace("_", " "),
                    ],
                )
                for device in devices
            ],
        )
        return [fuzzy_device] if fuzzy_device is not None else []

    @staticmethod
    def _fallback_match(normalized: str) -> CommandMatch | None:
        percent = extract_percent(normalized)
        if percent is not None:
            target = re.sub(r"\b\d{1,3}\s*(percent|%)\b", "", normalized).strip()
            target = target.removeprefix("set ").removeprefix("dim ").strip()
            return CommandMatch(action="set_level", target=target, percent=percent)

        for phrase, action in [
            ("turn on ", "turn_on"),
            ("switch on ", "turn_on"),
            ("power on ", "turn_on"),
            ("start ", "turn_on"),
            ("turn off ", "turn_off"),
            ("switch off ", "turn_off"),
            ("power off ", "turn_off"),
            ("stop ", "turn_off"),
            ("toggle ", "toggle"),
            ("change ", "toggle"),
        ]:
            if normalized.startswith(phrase):
                return CommandMatch(action=action, target=normalized.removeprefix(phrase).strip())
        return fuzzy_action_match(normalized)


def compile_template(template: str) -> re.Pattern[str]:
    escaped = re.escape(normalize_text(template))
    escaped = escaped.replace(r"\{target\}", r"(?P<target>.+?)")
    escaped = escaped.replace(r"\{percent\}", r"(?P<percent>\d{1,3})")
    escaped = escaped.replace(r"%", r"\s*(?:percent|%)")
    return re.compile(escaped)


_FILLER_PREFIX_PATTERN = re.compile(
    r"^(?:"
    r"(?:hey|ok|okay|hi|hello|please|could you|can you|would you|"
    r"jarvis|hive|vokrr|quantum(?: home)?)"
    r"[,\s]+)+"
)


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.lower().strip())


def clean_user_utterance(value: str) -> str:
    """Normalize a spoken utterance: lower, drop punctuation, strip filler prefixes."""
    lowered = value.lower()
    lowered = re.sub(r"[^a-z0-9%\s]", " ", lowered)
    collapsed = re.sub(r"\s+", " ", lowered).strip()
    return _FILLER_PREFIX_PATTERN.sub("", collapsed)


def _space_fold(normalized: str) -> str:
    """Strip all spaces so e.g. STT 'tube light' matches registry name 'Tubelight'."""
    return "".join(normalized.split())


def _literal_match(target_normalized: str, candidate_normalized: str) -> bool:
    if target_normalized == candidate_normalized:
        return True
    return _space_fold(target_normalized) == _space_fold(candidate_normalized)


def fuzzy_action_match(normalized: str) -> CommandMatch | None:
    words = normalized.split()
    if not words:
        return None

    prefix_actions = [
        ("turn on", "turn_on"),
        ("switch on", "turn_on"),
        ("power on", "turn_on"),
        ("start", "turn_on"),
        ("turn off", "turn_off"),
        ("switch off", "turn_off"),
        ("power off", "turn_off"),
        ("stop", "turn_off"),
        ("shut down", "turn_off"),
        ("toggle", "toggle"),
        ("change", "toggle"),
    ]
    for phrase, action in prefix_actions:
        phrase_len = len(phrase.split())
        prefix = " ".join(words[:phrase_len])
        if _similarity(prefix, phrase) >= FUZZY_MATCH_THRESHOLD and len(words) > phrase_len:
            return CommandMatch(action=action, target=" ".join(words[phrase_len:]).strip())

    if len(words) >= 3 and _similarity(words[0], "switch") >= FUZZY_MATCH_THRESHOLD:
        suffix = words[-1]
        if _similarity(suffix, "on") >= FUZZY_MATCH_THRESHOLD:
            return CommandMatch(action="turn_on", target=" ".join(words[1:-1]).strip())
        if _similarity(suffix, "off") >= FUZZY_MATCH_THRESHOLD:
            return CommandMatch(action="turn_off", target=" ".join(words[1:-1]).strip())

    if len(words) >= 2:
        suffix = words[-1]
        if _similarity(suffix, "on") >= FUZZY_MATCH_THRESHOLD:
            target = " ".join(words[:-1])
            target = target.removeprefix("turn ").removeprefix("switch ").strip()
            return CommandMatch(action="turn_on", target=target)
        if _similarity(suffix, "off") >= FUZZY_MATCH_THRESHOLD:
            target = " ".join(words[:-1])
            target = target.removeprefix("turn ").removeprefix("switch ").strip()
            return CommandMatch(action="turn_off", target=target)

    return None


def _best_fuzzy_match(target: str, candidates: list[tuple[T, list[str]]]) -> T | None:
    scored: list[tuple[float, T]] = []
    for item, aliases in candidates:
        score = max(_similarity(target, alias) for alias in aliases if alias)
        scored.append((score, item))

    if not scored:
        return None
    scored.sort(key=lambda entry: entry[0], reverse=True)
    best_score, best_item = scored[0]
    second_score = scored[1][0] if len(scored) > 1 else 0.0
    if best_score < FUZZY_MATCH_THRESHOLD:
        return None
    if second_score >= FUZZY_MATCH_THRESHOLD and best_score - second_score < 0.05:
        logger.info(
            "voice.intent: fuzzy target ambiguous target=%r best=%.2f second=%.2f",
            target,
            best_score,
            second_score,
        )
        return None
    logger.info("voice.intent: fuzzy target matched target=%r score=%.2f", target, best_score)
    return best_item


def _similarity(left: str, right: str) -> float:
    left_normalized = normalize_text(left)
    right_normalized = normalize_text(right)
    if not left_normalized or not right_normalized:
        return 0.0

    scores = [
        SequenceMatcher(None, left_normalized, right_normalized).ratio(),
        SequenceMatcher(None, _space_fold(left_normalized), _space_fold(right_normalized)).ratio(),
        SequenceMatcher(None, _token_sort(left_normalized), _token_sort(right_normalized)).ratio(),
    ]
    return max(scores)


def _token_sort(value: str) -> str:
    return " ".join(sorted(value.split()))


def slugify(value: str) -> str:
    return normalize_text(value).replace(" ", "_")


def extract_percent(normalized: str) -> int | None:
    match = re.search(r"(\d{1,3})\s*(percent|%)", normalized)
    if not match:
        return None
    return clamp_percent(int(match.group(1)))


def clamp_percent(percent: int) -> int:
    return max(0, min(100, percent))
