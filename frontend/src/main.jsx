import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

const API_BASE =
  window.location.port === "3000"
    ? `${window.location.protocol}//${window.location.hostname}:8080`
    : "";
const TOKEN_KEY = "quantum_home_token";
const KIOSK_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

function App() {
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) || "");
  const [rooms, setRooms] = useState([]);
  const [scenes, setScenes] = useState([]);
  const [selectedRoomId, setSelectedRoomId] = useState(null);
  const [health, setHealth] = useState(null);
  const [assistantMessage, setAssistantMessage] = useState("Voice ready");
  const [assistantDisplay, setAssistantDisplay] = useState("Voice ready");
  const [assistantStatus, setAssistantStatus] = useState("idle");
  const [loginError, setLoginError] = useState("");
  const [appMessage, setAppMessage] = useState("");
  const [kioskLoginPending, setKioskLoginPending] = useState(false);

  useEffect(() => {
    if (!token) {
      return;
    }
    loadSnapshot();
    loadHealth();
  }, [token]);

  useEffect(() => {
    if (!token) {
      return;
    }
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    const wsHost =
      window.location.port === "3000"
        ? `${window.location.hostname}:8080`
        : window.location.host;
    const ws = new WebSocket(`${protocol}://${wsHost}/ws?token=${encodeURIComponent(token)}`);

    ws.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (message.event === "snapshot") {
        setRooms(message.payload.rooms);
        setSelectedRoomId((current) => current ?? message.payload.rooms?.[0]?.id ?? null);
      }
      if (message.event === "device.updated") {
        mergeDevice(message.payload);
      }
      if (message.event === "voice.command") {
        setAssistantFeedback(message.payload.message, message.payload.understood ? "done" : "error");
      }
      if (message.event === "voice.status") {
        setAssistantFeedback(message.payload.message, message.payload.status);
      }
      if (message.event === "scene.ran") {
        setAppMessage(`${message.payload.name} ran`);
      }
    });

    return () => ws.close();
  }, [token]);

  useEffect(() => {
    if (token || !KIOSK_HOSTS.has(window.location.hostname)) {
      return;
    }
    setKioskLoginPending(true);
    fetch(`${API_BASE}/api/auth/kiosk`, { method: "POST" })
      .then((response) => {
        if (!response.ok) {
          throw new Error("Kiosk login unavailable");
        }
        return response.json();
      })
      .then((data) => {
        localStorage.setItem(TOKEN_KEY, data.token);
        setToken(data.token);
      })
      .catch(() => {
        setLoginError("Sign in on this device.");
      })
      .finally(() => setKioskLoginPending(false));
  }, [token]);

  useEffect(() => {
    setAssistantDisplay("");
    if (!assistantMessage) {
      return;
    }
    let index = 0;
    const timer = window.setInterval(() => {
      index += 1;
      setAssistantDisplay(assistantMessage.slice(0, index));
      if (index >= assistantMessage.length) {
        window.clearInterval(timer);
      }
    }, 18);
    return () => window.clearInterval(timer);
  }, [assistantMessage]);

  const selectedRoom = useMemo(
    () => rooms.find((room) => room.id === selectedRoomId) ?? rooms[0],
    [rooms, selectedRoomId],
  );

  async function loadSnapshot() {
    const response = await authFetch("/api/rooms");
    if (response.ok) {
      const data = await response.json();
      setRooms(data);
      setSelectedRoomId((current) => current ?? data?.[0]?.id ?? null);
    }
    const scenesResponse = await authFetch("/api/scenes");
    if (scenesResponse.ok) {
      setScenes(await scenesResponse.json());
    }
  }

  async function loadHealth() {
    const response = await fetch(`${API_BASE}/api/system/health`);
    setHealth(await response.json());
  }

  function mergeDevice(updatedDevice) {
    setRooms((currentRooms) =>
      currentRooms.map((room) => ({
        ...room,
        devices: room.devices.map((device) =>
          device.id === updatedDevice.id ? updatedDevice : device,
        ),
      })),
    );
  }

  function setAssistantFeedback(message, status = "idle") {
    setAssistantStatus(status || "idle");
    setAssistantMessage(message || "Voice ready");
  }

  async function toggleDevice(device) {
    setAppMessage("");
    const response = await authFetch(`/api/devices/${device.id}/toggle`, {
      method: "POST",
    });
    await handleDeviceResponse(response, `${device.name} updated`);
  }

  async function setDevice(device, payload) {
    setAppMessage("");
    const response = await authFetch(`/api/devices/${device.id}/set`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    await handleDeviceResponse(response, `${device.name} updated`);
  }

  async function runScene(scene) {
    setAppMessage("");
    const response = await authFetch(`/api/scenes/${scene.id}/run`, {
      method: "POST",
    });
    if (!response.ok) {
      await showApiError(response, `Could not run ${scene.name}`);
      return;
    }
    setAppMessage(`${scene.name} ran`);
    await loadSnapshot();
  }

  async function handleDeviceResponse(response, successMessage) {
    if (!response.ok) {
      await showApiError(response, "Device action failed");
      return;
    }
    mergeDevice(await response.json());
    setAppMessage(successMessage);
  }

  async function showApiError(response, fallback) {
    let detail = fallback;
    try {
      const data = await response.json();
      detail = data.detail || detail;
    } catch {
      detail = fallback;
    }
    setAppMessage(detail);
  }

  async function authFetch(path, options = {}) {
    const response = await fetch(`${API_BASE}${path}`, {
      ...options,
      headers: {
        ...(options.headers || {}),
        Authorization: `Bearer ${token}`,
      },
    });
    if (response.status === 401) {
      localStorage.removeItem(TOKEN_KEY);
      setToken("");
      setRooms([]);
      setLoginError("Sign in again.");
    }
    return response;
  }

  async function handleLogin(event) {
    event.preventDefault();
    setLoginError("");
    const form = new FormData(event.currentTarget);
    const response = await fetch(`${API_BASE}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        username: form.get("username"),
        password: form.get("password"),
      }),
    });
    if (!response.ok) {
      setLoginError("Username or password is incorrect.");
      return;
    }
    const data = await response.json();
    localStorage.setItem(TOKEN_KEY, data.token);
    setToken(data.token);
  }

  function logout() {
    localStorage.removeItem(TOKEN_KEY);
    setToken("");
    setRooms([]);
    setScenes([]);
    setSelectedRoomId(null);
  }

  if (!token) {
    if (kioskLoginPending) {
      return (
        <main className="loginShell">
          <div className="loginPanel">
            <p className="eyebrow">Quantum Home</p>
            <h1>Starting</h1>
            <p className="loginHint">Opening the base app.</p>
          </div>
        </main>
      );
    }
    return <LoginScreen error={loginError} onLogin={handleLogin} />;
  }

  return (
    <main className="shell">
      <aside className="rooms">
        <div>
          <p className="eyebrow">Quantum Home</p>
          <h1>Control</h1>
        </div>
        <nav className="roomList" aria-label="Rooms">
          {rooms.map((room) => (
            <button
              className={room.id === selectedRoom?.id ? "roomButton active" : "roomButton"}
              key={room.id}
              onClick={() => setSelectedRoomId(room.id)}
            >
              <span>{room.name}</span>
              <small>{room.devices.length}</small>
            </button>
          ))}
        </nav>
        <SystemStatus health={health} onLogout={logout} />
      </aside>

      <section className="roomPanel">
        <header className="topBar">
          <div>
            <p className="eyebrow">Room</p>
            <h2>{selectedRoom?.name ?? "No room configured"}</h2>
          </div>
          <div className={`voiceStatus ${appMessage ? "warnText" : ""} ${assistantStatus}`}>
            <span>{appMessage || assistantDisplay || "Voice ready"}</span>
            {!appMessage && <i aria-hidden="true" />}
          </div>
        </header>

        <SceneStrip scenes={scenes} onRun={runScene} />

        <div className="deviceGrid">
          {selectedRoom?.devices.map((device) => (
            <DeviceCard
              device={device}
              key={device.id}
              onToggle={() => toggleDevice(device)}
              onSet={(payload) => setDevice(device, payload)}
            />
          ))}
        </div>
      </section>
    </main>
  );
}

function SceneStrip({ scenes, onRun }) {
  if (!scenes.length) {
    return null;
  }

  return (
    <section className="sceneStrip" aria-label="Scenes">
      {scenes.map((scene) => (
        <button key={scene.id} onClick={() => onRun(scene)}>
          {scene.name}
        </button>
      ))}
    </section>
  );
}

function LoginScreen({ error, onLogin }) {
  return (
    <main className="loginShell">
      <form className="loginPanel" onSubmit={onLogin}>
        <p className="eyebrow">Quantum Home</p>
        <h1>Sign In</h1>
        <label>
          <span>Username</span>
          <input name="username" autoComplete="username" required />
        </label>
        <label>
          <span>Password</span>
          <input name="password" type="password" autoComplete="current-password" required />
        </label>
        {error && <p className="loginError">{error}</p>}
        <button type="submit">Open Controls</button>
      </form>
    </main>
  );
}

function SystemStatus({ health, onLogout }) {
  const haOk = health?.home_assistant?.ok;
  return (
    <>
      <div className="status">
        <span className={haOk ? "dot ok" : "dot warn"} />
        <span>{haOk ? "Home Assistant online" : "Checking Home Assistant"}</span>
      </div>
      <button className="logoutButton" onClick={onLogout}>Sign Out</button>
    </>
  );
}

function DeviceCard({ device, onToggle, onSet }) {
  const hasBrightness = device.capabilities.includes("brightness");
  const hasPercentage = device.capabilities.includes("percentage");
  const hasColorTemperature = device.capabilities.includes("color_temperature");
  const hasColor = device.capabilities.includes("color");
  const level = device.state.brightness ?? device.state.percentage ?? 0;
  const unavailable = device.state.state === "unavailable" || device.state.state === "unknown";

  return (
    <article className={device.state.is_on ? "deviceCard on" : "deviceCard"}>
      <div className="deviceHeader">
        <div>
          <p className="deviceType">{device.type}</p>
          <h3>{device.name}</h3>
        </div>
        <button
          className="toggle"
          onClick={onToggle}
          aria-pressed={device.state.is_on}
          disabled={unavailable}
        >
          {unavailable ? "Offline" : device.state.is_on ? "On" : "Off"}
        </button>
      </div>

      <p className={unavailable ? "stateText unavailable" : "stateText"}>
        {unavailable ? "Unavailable" : device.state.state}
      </p>

      {hasBrightness && (
        <label className="slider">
          <span>Brightness {device.state.brightness ?? 0}%</span>
          <input
            type="range"
            min="0"
            max="100"
            value={device.state.brightness ?? 0}
            disabled={unavailable}
            onChange={(event) => onSet({ brightness: Number(event.target.value) })}
          />
        </label>
      )}

      {hasColorTemperature && (
        <label className="slider">
          <span>Warmth {device.state.color_temp_kelvin ?? 6500}K</span>
          <input
            type="range"
            min="2000"
            max="6500"
            step="100"
            value={device.state.color_temp_kelvin ?? 6500}
            disabled={unavailable}
            onChange={(event) => onSet({ color_temp_kelvin: Number(event.target.value) })}
          />
        </label>
      )}

      {hasColor && (
        <div className="colorPresets" aria-label="Color presets">
          {[
            ["Warm", [255, 180, 90]],
            ["White", [255, 255, 255]],
            ["Blue", [80, 150, 255]],
          ].map(([label, rgb]) => (
            <button
              key={label}
              disabled={unavailable}
              onClick={() => onSet({ rgb_color: rgb })}
              type="button"
            >
              {label}
            </button>
          ))}
        </div>
      )}

      {hasPercentage && (
        <label className="slider">
          <span>Speed {device.state.percentage ?? 0}%</span>
          <input
            type="range"
            min="0"
            max="100"
            value={device.state.percentage ?? 0}
            disabled={unavailable}
            onChange={(event) => onSet({ percentage: Number(event.target.value) })}
          />
        </label>
      )}

      {!hasBrightness && !hasPercentage && <div className="spacer" />}
      <div className="levelBar">
        <span style={{ width: `${level}%` }} />
      </div>
    </article>
  );
}

createRoot(document.getElementById("root")).render(<App />);
