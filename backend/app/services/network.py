import subprocess
import shutil
from dataclasses import dataclass

from app.core.config import Settings


@dataclass
class NetworkService:
    settings: Settings

    def _run(self, args: list[str], timeout: int = 12) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

    def _configured_networks(self) -> list[dict[str, str]]:
        networks: list[dict[str, str]] = []
        if self.settings.primary_ssid:
            networks.append({"key": "primary", "ssid": self.settings.primary_ssid})
        if self.settings.secondary_ssid:
            networks.append({"key": "secondary", "ssid": self.settings.secondary_ssid})
        return networks

    def _connection_names_for_ssid(self, ssid: str) -> list[str]:
        result = self._run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"])
        if result.returncode != 0:
            return []

        names: list[str] = []
        for line in result.stdout.splitlines():
            parts = line.split(":")
            if len(parts) < 2 or parts[1] != "802-11-wireless":
                continue

            connection_name = parts[0]
            ssid_result = self._run(
                ["nmcli", "-g", "802-11-wireless.ssid", "connection", "show", connection_name]
            )
            if ssid_result.returncode == 0 and ssid_result.stdout.strip() == ssid:
                names.append(connection_name)
        return names

    def wifi_status(self) -> dict:
        if not shutil.which("nmcli"):
            return {
                "available": False,
                "connected": False,
                "ssid": "",
                "configured": self._configured_networks(),
                "error": "nmcli is not installed",
            }

        device_result = self._run(
            ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]
        )
        connected_ssid = ""
        ethernet_connection = ""
        wifi_state = "unknown"
        if device_result.returncode == 0:
            for line in device_result.stdout.splitlines():
                parts = line.split(":")
                if len(parts) >= 4 and parts[0] == self.settings.wifi_interface:
                    wifi_state = parts[2]
                if len(parts) >= 4 and parts[1] == "ethernet" and parts[2] == "connected":
                    ethernet_connection = parts[3]

        wifi_result = self._run(
            ["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi", "list", "ifname", self.settings.wifi_interface]
        )
        if wifi_result.returncode == 0:
            for line in wifi_result.stdout.splitlines():
                active, _, ssid = line.partition(":")
                if active == "yes":
                    connected_ssid = ssid
                    break

        return {
            "available": True,
            "connected": bool(connected_ssid),
            "ssid": connected_ssid,
            "connection_type": "wifi" if connected_ssid else ("ethernet" if ethernet_connection else ""),
            "ethernet": ethernet_connection,
            "interface": self.settings.wifi_interface,
            "state": wifi_state,
            "configured": self._configured_networks(),
        }

    def connect_wifi(self, network_key: str) -> dict:
        networks = {
            "primary": (self.settings.primary_ssid, self.settings.primary_ssid_password),
            "secondary": (self.settings.secondary_ssid, self.settings.secondary_ssid_password),
        }
        ssid, password = networks.get(network_key, ("", ""))
        if not ssid:
            raise ValueError("Unknown Wi-Fi network")

        self._run(["nmcli", "radio", "wifi", "on"])
        self._run(["nmcli", "device", "set", self.settings.wifi_interface, "managed", "yes"])
        self._run(["nmcli", "device", "wifi", "rescan", "ifname", self.settings.wifi_interface])

        attempts: list[list[str]] = []
        for connection_name in self._connection_names_for_ssid(ssid):
            attempts.append(["nmcli", "connection", "up", connection_name, "ifname", self.settings.wifi_interface])

        connect_args = [
            "nmcli",
            "device",
            "wifi",
            "connect",
            ssid,
            "password",
            password,
            "ifname",
            self.settings.wifi_interface,
        ]
        attempts.append(connect_args)
        attempts.append(connect_args + ["hidden", "yes"])

        result = None
        errors: list[str] = []
        for attempt in attempts:
            result = self._run(attempt, timeout=30)
            if result.returncode == 0:
                return self.wifi_status()
            error = result.stderr.strip() or result.stdout.strip()
            if error:
                errors.append(error)

        if result is None:
            raise RuntimeError("Could not connect to Wi-Fi")
        if result.returncode != 0:
            error = errors[-1] if errors else "Could not connect to Wi-Fi"
            raise RuntimeError(error)
        return self.wifi_status()
