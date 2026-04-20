import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

const API_BASE =
  window.location.port === "3000" || window.location.port === "5173"
    ? `${window.location.protocol}//${window.location.hostname}:8080`
    : "";
const TOKEN_KEY = "quantum_home_token";
const KIOSK_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);
const NAV_ITEMS = ["Home", "Devices", "Routines", "Activity"];

function App() {
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) || "");
  const [rooms, setRooms] = useState([]);
  const [scenes, setScenes] = useState([]);
  const [selectedRoomId, setSelectedRoomId] = useState(null);
  const [health, setHealth] = useState(null);
  const [healthError, setHealthError] = useState("");
  const [activeView, setActiveView] = useState("Home");
  const [assistantMessage, setAssistantMessage] = useState("Listening for Jarvis");
  const [assistantDisplay, setAssistantDisplay] = useState("Listening for Jarvis");
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
    const timer = window.setInterval(loadHealth, 5000);
    return () => window.clearInterval(timer);
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
  const allDevices = useMemo(() => rooms.flatMap((room) => room.devices), [rooms]);

  async function loadSnapshot() {
    try {
      const response = await authFetch("/api/rooms");
      if (response.ok) {
        const data = await response.json();
        setRooms(data);
        setSelectedRoomId((current) => current ?? data?.[0]?.id ?? null);
      } else if (response.status !== 401) {
        await showApiError(response, "Could not load configured rooms");
      }
      const scenesResponse = await authFetch("/api/scenes");
      if (scenesResponse.ok) {
        setScenes(await scenesResponse.json());
      }
    } catch {
      setAppMessage("Backend unavailable. Retrying when the service is back.");
    }
  }

  async function loadHealth() {
    try {
      const response = await fetch(`${API_BASE}/api/system/health`);
      if (!response.ok) {
        throw new Error(`Backend health returned HTTP ${response.status}`);
      }
      setHealth(await response.json());
      setHealthError("");
    } catch (error) {
      setHealth(null);
      setHealthError(error instanceof Error ? error.message : "Backend unavailable");
    }
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
    setAssistantMessage(message || "Listening for Jarvis");
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

  function refreshApp() {
    window.location.reload();
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
      <section className="homeScreen">
        <header className="heroBar">
          <div>
            <p className="eyebrow">Quantum Home</p>
            <h1>Good evening, sir</h1>
          </div>
          <SystemStatus health={health} error={healthError} onRefresh={refreshApp} onLogout={logout} />
        </header>

        <SceneStrip scenes={scenes} onRun={runScene} />

        <section className="contentGrid">
          <PrimaryView
            activeView={activeView}
            rooms={rooms}
            selectedRoom={selectedRoom}
            scenes={scenes}
            allDevices={allDevices}
            onSelectRoom={setSelectedRoomId}
            onToggle={toggleDevice}
            onSet={setDevice}
            onRunScene={runScene}
            health={health}
            healthError={healthError}
          />

          <aside className={`assistantPanel ${assistantStatus}`}>
            <p className="eyebrow">Jarvis</p>
            <div className="assistantOrb">
              <span />
            </div>
            <h2>{assistantStatus === "listening" ? "Listening" : "Assistant"}</h2>
            <p className={appMessage ? "assistantText warnText" : "assistantText"}>
              {appMessage || assistantDisplay || "Listening for Jarvis"}
              {!appMessage && <i aria-hidden="true" />}
            </p>
            <div className="assistantHints">
              <span>Say “Jarvis”</span>
              <span>Try “turn off bedroom”</span>
            </div>
          </aside>
        </section>

        <nav className="bottomNav" aria-label="Primary">
          {NAV_ITEMS.map((item) => (
            <button
              className={activeView === item ? "active" : ""}
              key={item}
              onClick={() => setActiveView(item)}
              type="button"
            >
              {item}
            </button>
          ))}
        </nav>
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

function PrimaryView({
  activeView,
  rooms,
  selectedRoom,
  scenes,
  allDevices,
  onSelectRoom,
  onToggle,
  onSet,
  onRunScene,
  health,
  healthError,
}) {
  if (activeView === "Devices") {
    return (
      <div className="deviceColumn">
        <div className="sectionTitle">
          <div>
            <p className="eyebrow">All Devices</p>
            <h2>{allDevices.length ? `${allDevices.length} configured` : "No devices loaded"}</h2>
          </div>
        </div>
        <DeviceGrid devices={allDevices} onToggle={onToggle} onSet={onSet} />
      </div>
    );
  }

  if (activeView === "Routines") {
    return (
      <div className="deviceColumn">
        <div className="sectionTitle">
          <div>
            <p className="eyebrow">Routines</p>
            <h2>{scenes.length ? "Ready" : "No routines configured"}</h2>
          </div>
        </div>
        <div className="routineGrid">
          {scenes.map((scene) => (
            <button className="routineCard" key={scene.id} onClick={() => onRunScene(scene)}>
              {scene.name}
            </button>
          ))}
        </div>
      </div>
    );
  }

  if (activeView === "Activity") {
    const haOk = health?.home_assistant?.ok;
    const detail = healthError || health?.home_assistant?.error || "No recent errors.";
    return (
      <div className="deviceColumn">
        <div className="sectionTitle">
          <div>
            <p className="eyebrow">Activity</p>
            <h2>{haOk ? "Systems online" : "System needs attention"}</h2>
          </div>
        </div>
        <div className="activityPanel">
          <p>Rooms loaded: {rooms.length}</p>
          <p>Devices loaded: {allDevices.length}</p>
          <p>Home Assistant: {haOk ? "online" : "offline"}</p>
          {!haOk && <p className="warnText">{detail}</p>}
        </div>
      </div>
    );
  }

  return (
    <div className="deviceColumn">
      <div className="sectionTitle">
        <div>
          <p className="eyebrow">Devices</p>
          <h2>{selectedRoom?.name ?? (rooms.length ? "Select a room" : "Rooms are loading")}</h2>
        </div>
      </div>

      <nav className="roomTabs" aria-label="Rooms">
        {rooms.map((room) => (
          <button
            className={room.id === selectedRoom?.id ? "roomButton active" : "roomButton"}
            key={room.id}
            onClick={() => onSelectRoom(room.id)}
          >
            {room.name}
          </button>
        ))}
      </nav>

      <DeviceGrid devices={selectedRoom?.devices ?? []} onToggle={onToggle} onSet={onSet} />
    </div>
  );
}

function DeviceGrid({ devices, onToggle, onSet }) {
  return (
    <div className="deviceGrid">
      {devices.map((device) => (
        <DeviceCard
          device={device}
          key={device.id}
          onToggle={() => onToggle(device)}
          onSet={(payload) => onSet(device, payload)}
        />
      ))}
    </div>
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

function SystemStatus({ health, error, onRefresh, onLogout }) {
  const haOk = health?.home_assistant?.ok;
  const label = error
    ? "Backend offline"
    : health
      ? haOk
        ? "Home Assistant online"
        : "Home Assistant offline"
      : "Checking Home Assistant";
  return (
    <div className="systemCluster">
      <div className="status">
        <span className={haOk ? "dot ok" : health ? "dot error" : "dot warn"} />
        <span>{label}</span>
      </div>
      <button className="refreshButton" onClick={onRefresh} type="button">Refresh</button>
      <button className="logoutButton" onClick={onLogout}>Sign Out</button>
    </div>
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
          <div className="deviceIcon">{deviceIcon(device.type)}</div>
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

function deviceIcon(type) {
  if (type === "light") return "◐";
  if (type === "switch") return "▣";
  if (type === "fan") return "✣";
  return "•";
}

createRoot(document.getElementById("root")).render(<App />);
