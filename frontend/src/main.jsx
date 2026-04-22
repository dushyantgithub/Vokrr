import React, { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import SoftAurora from "./components/SoftAurora/SoftAurora.jsx";
import "./styles.css";

const API_BASE =
  window.location.port === "3000" || window.location.port === "5173"
    ? `${window.location.protocol}//${window.location.hostname}:8080`
    : "";
const TOKEN_KEY = "vokrr_token";
const KIOSK_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

const NAV_ITEMS = [
  { key: "Dashboard", label: "Dashboard", icon: "grid" },
  { key: "Devices", label: "Devices", icon: "devices" },
  { key: "Routines", label: "Routines", icon: "bookmark" },
  { key: "Activity", label: "Activity", icon: "clock" },
  { key: "News", label: "News", icon: "news" },
  { key: "Settings", label: "Settings", icon: "settings", action: "settings" },
];

const NEWS_URL = "/news-proxy/";
const NEWS_URL_EXTERNAL = "https://www.worldmonitor.app";
const VALID_VIEW_KEYS = new Set(["Dashboard", "Devices", "Routines", "Activity", "News"]);

const MAX_NOTIFICATIONS = 15;
const JARVIS_STATUS_LABELS = {
  idle: "Waiting for Jarvis",
  listening: "Listening",
  processing: "Processing",
  done: "Ready",
  error: "Error",
  command_error: "Command failed",
};

const AC_PRESETS = [
  { key: "cool", icon: "snow", label: "Cool" },
  { key: "boost", icon: "flash", label: "Boost" },
  { key: "fan", icon: "wind", label: "Fan" },
  { key: "dry", icon: "drop", label: "Dry" },
  { key: "night", icon: "moon", label: "Night" },
];

function useMicLevel() {
  const levelRef = useRef(0);
  useEffect(() => {
    if (typeof window === "undefined") return undefined;
    if (!navigator.mediaDevices?.getUserMedia || !(window.AudioContext || window.webkitAudioContext)) {
      return undefined;
    }
    let cancelled = false;
    let stream;
    let ctx;
    let raf;
    navigator.mediaDevices
      .getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } })
      .then((mediaStream) => {
        if (cancelled) {
          mediaStream.getTracks().forEach((t) => t.stop());
          return;
        }
        stream = mediaStream;
        ctx = new (window.AudioContext || window.webkitAudioContext)();
        const source = ctx.createMediaStreamSource(mediaStream);
        const analyser = ctx.createAnalyser();
        analyser.fftSize = 1024;
        analyser.smoothingTimeConstant = 0.3;
        source.connect(analyser);
        const data = new Uint8Array(analyser.fftSize);
        let smoothed = 0;
        const tick = () => {
          analyser.getByteTimeDomainData(data);
          let sum = 0;
          for (let i = 0; i < data.length; i += 1) {
            const v = (data[i] - 128) / 128;
            sum += v * v;
          }
          const rms = Math.sqrt(sum / data.length);
          const norm = Math.min(1, rms * 4);
          smoothed = smoothed * 0.85 + norm * 0.15;
          levelRef.current = smoothed;
          raf = requestAnimationFrame(tick);
        };
        tick();
      })
      .catch(() => {
        // Mic permission denied or unavailable; leave level at 0.
      });
    return () => {
      cancelled = true;
      if (raf) cancelAnimationFrame(raf);
      if (stream) stream.getTracks().forEach((t) => t.stop());
      if (ctx) ctx.close().catch(() => {});
    };
  }, []);
  return levelRef;
}

function App() {
  const micLevelRef = useMicLevel();
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) || "");
  const [rooms, setRooms] = useState([]);
  const [scenes, setScenes] = useState([]);
  const [selectedRoomId, setSelectedRoomId] = useState(null);
  const [health, setHealth] = useState(null);
  const [healthError, setHealthError] = useState("");
  const [activeView, setActiveView] = useState("Dashboard");
  const [assistantMessage, setAssistantMessage] = useState("Listening for Jarvis");
  const [assistantDisplay, setAssistantDisplay] = useState("Listening for Jarvis");
  const [assistantStatus, setAssistantStatus] = useState("idle");
  const [loginError, setLoginError] = useState("");
  const [notifications, setNotifications] = useState([]);
  const [kioskLoginPending, setKioskLoginPending] = useState(false);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);

  useEffect(() => {
    if (!token) return;
    loadSnapshot();
    loadHealth();
    const timer = window.setInterval(loadHealth, 5000);
    return () => window.clearInterval(timer);
  }, [token]);

  useEffect(() => {
    if (!token) return;
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
      if (message.event === "device.updated") mergeDevice(message.payload);
      if (message.event === "voice.command") {
        setAssistantFeedback(message.payload.message, message.payload.understood ? "done" : "error");
        if (message.payload.navigate && VALID_VIEW_KEYS.has(message.payload.navigate)) {
          setActiveView(message.payload.navigate);
          setSettingsOpen(false);
          setNotificationsOpen(false);
        }
      }
      if (message.event === "voice.status") {
        setAssistantFeedback(message.payload.message, message.payload.status);
      }
      if (message.event === "scene.ran") pushNotification(`${message.payload.name} ran`, "info");
    });
    return () => ws.close();
  }, [token]);

  useEffect(() => {
    if (token || !KIOSK_HOSTS.has(window.location.hostname)) return;
    setKioskLoginPending(true);
    fetch(`${API_BASE}/api/auth/kiosk`, { method: "POST" })
      .then((response) => {
        if (!response.ok) throw new Error("Kiosk login unavailable");
        return response.json();
      })
      .then((data) => {
        localStorage.setItem(TOKEN_KEY, data.access_token);
        setToken(data.access_token);
      })
      .catch(() => setLoginError("Sign in on this device."))
      .finally(() => setKioskLoginPending(false));
  }, [token]);

  useEffect(() => {
    setAssistantDisplay("");
    if (!assistantMessage) return;
    let index = 0;
    const timer = window.setInterval(() => {
      index += 1;
      setAssistantDisplay(assistantMessage.slice(0, index));
      if (index >= assistantMessage.length) window.clearInterval(timer);
    }, 18);
    return () => window.clearInterval(timer);
  }, [assistantMessage]);

  const selectedRoom = useMemo(
    () => rooms.find((room) => room.id === selectedRoomId) ?? rooms[0],
    [rooms, selectedRoomId],
  );
  const allDevices = useMemo(() => rooms.flatMap((room) => room.devices), [rooms]);
  const visibleDevices = selectedRoom?.devices ?? [];
  const lights = useMemo(
    () => allDevices.filter((d) => d.capabilities?.includes("brightness")),
    [allDevices],
  );
  const heroDevice = useMemo(() => {
    const candidates = visibleDevices.length ? visibleDevices : allDevices;
    return (
      candidates.find((d) => d.capabilities?.includes("brightness")) ||
      candidates.find((d) => d.capabilities?.includes("percentage")) ||
      candidates[0]
    );
  }, [visibleDevices, allDevices]);

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
      if (scenesResponse.ok) setScenes(await scenesResponse.json());
    } catch {
      pushNotification("Backend unavailable. Retrying when the service is back.", "warn");
    }
  }

  function pushNotification(message, level = "info") {
    if (!message) return;
    const entry = { id: `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, message, level, createdAt: Date.now() };
    setNotifications((current) => [entry, ...current].slice(0, MAX_NOTIFICATIONS));
  }

  async function loadHealth() {
    try {
      const response = await fetch(`${API_BASE}/api/system/health`);
      if (!response.ok) throw new Error(`Backend health returned HTTP ${response.status}`);
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
    const nextStatus = status || "idle";
    setAssistantStatus(nextStatus);
    setAssistantMessage(message || JARVIS_STATUS_LABELS.idle);
    if (nextStatus === "command_error" || nextStatus === "error") {
      pushNotification(message, "error");
    }
  }

  async function toggleDevice(device) {
    const response = await authFetch(`/api/devices/${device.id}/toggle`, { method: "POST" });
    await handleDeviceResponse(response, `${device.name} updated`);
  }

  async function setDevice(device, payload) {
    const response = await authFetch(`/api/devices/${device.id}/set`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    await handleDeviceResponse(response, `${device.name} updated`);
  }

  async function runScene(scene) {
    const response = await authFetch(`/api/scenes/${scene.id}/run`, { method: "POST" });
    if (!response.ok) return showApiError(response, `Could not run ${scene.name}`);
    pushNotification(`${scene.name} ran`, "info");
    await loadSnapshot();
  }

  async function handleDeviceResponse(response, successMessage) {
    if (!response.ok) return showApiError(response, "Device action failed");
    mergeDevice(await response.json());
    pushNotification(successMessage, "info");
  }

  async function showApiError(response, fallback) {
    let detail = fallback;
    try {
      const data = await response.json();
      detail = data.detail || detail;
    } catch {
      detail = fallback;
    }
    pushNotification(detail, "error");
  }

  async function authFetch(path, options = {}) {
    const response = await fetch(`${API_BASE}${path}`, {
      ...options,
      headers: { ...(options.headers || {}), Authorization: `Bearer ${token}` },
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
    localStorage.setItem(TOKEN_KEY, data.access_token);
    setToken(data.access_token);
  }

  function logout() {
    localStorage.removeItem(TOKEN_KEY);
    setToken("");
    setRooms([]);
    setScenes([]);
    setSelectedRoomId(null);
    setSettingsOpen(false);
    setNotifications([]);
  }

  function hardRefresh() {
    setSettingsOpen(false);
    try {
      if (window.caches && typeof window.caches.keys === "function") {
        window.caches.keys().then((keys) => keys.forEach((k) => window.caches.delete(k)));
      }
    } catch {
      // ignore
    }
    const url = new URL(window.location.href);
    url.searchParams.set("_ts", String(Date.now()));
    window.location.replace(url.toString());
  }

  function onNavSelect(item) {
    if (item.action === "settings") {
      setNotificationsOpen(false);
      setSettingsOpen((open) => !open);
      return;
    }
    if (item.disabled) return;
    setActiveView(item.key);
    setSettingsOpen(false);
    setNotificationsOpen(false);
  }

  function toggleNotifications() {
    setSettingsOpen(false);
    setNotificationsOpen((open) => !open);
  }

  function clearNotifications() {
    setNotifications([]);
  }

  const aurora = <AuroraBackground audioLevelRef={micLevelRef} />;

  if (!token) {
    if (kioskLoginPending) {
      return (
        <>
          {aurora}
          <main className="loginShell">
            <div className="loginPanel">
              <p className="eyebrow">Vokrr</p>
              <h1>Starting</h1>
              <p className="loginHint">Opening the base app.</p>
            </div>
          </main>
        </>
      );
    }
    return (
      <>
        {aurora}
        <LoginScreen error={loginError} onLogin={handleLogin} />
      </>
    );
  }

  return (
    <>
    {aurora}
    <main className="shell">
      <Sidebar
        activeView={activeView}
        onSelect={onNavSelect}
        settingsOpen={settingsOpen}
        onHardRefresh={hardRefresh}
        onLogout={logout}
      />
      <section className="workspace">
        <Header
          title={activeView}
          assistantStatus={assistantStatus}
          assistantDisplay={assistantDisplay}
          health={health}
          healthError={healthError}
          notifications={notifications}
          notificationsOpen={notificationsOpen}
          onToggleNotifications={toggleNotifications}
          onClearNotifications={clearNotifications}
        />

        {activeView === "Dashboard" && (
          <DashboardView
            rooms={rooms}
            selectedRoom={selectedRoom}
            onSelectRoom={setSelectedRoomId}
            scenes={scenes}
            onRunScene={runScene}
            heroDevice={heroDevice}
            visibleDevices={visibleDevices}
            lights={lights}
            onToggle={toggleDevice}
            onSet={setDevice}
          />
        )}

        {activeView === "Devices" && (
          <DevicesView
            allDevices={allDevices}
            onToggle={toggleDevice}
            onSet={setDevice}
          />
        )}

        {activeView === "Routines" && (
          <RoutinesView scenes={scenes} onRunScene={runScene} />
        )}

        {activeView === "News" && <NewsView url={NEWS_URL} externalUrl={NEWS_URL_EXTERNAL} />}

        {activeView === "Activity" && (
          <ActivityView
            rooms={rooms}
            allDevices={allDevices}
            health={health}
            healthError={healthError}
            assistantStatus={assistantStatus}
            assistantDisplay={assistantDisplay}
          />
        )}
      </section>
    </main>
    </>
  );
}

function AuroraBackground({ audioLevelRef }) {
  return (
    <div className="auroraBackground" aria-hidden="true">
      <SoftAurora
        speed={1}
        scale={1.5}
        brightness={1}
        color1="#f7f7f7"
        color2="#e100ff"
        noiseFrequency={2}
        noiseAmplitude={2}
        bandHeight={0.5}
        bandSpread={1}
        octaveDecay={0.1}
        layerOffset={0}
        colorSpeed={1}
        enableMouseInteraction={false}
        mouseInfluence={0.25}
        audioLevelRef={audioLevelRef}
      />
    </div>
  );
}

function Sidebar({ activeView, onSelect, settingsOpen, onHardRefresh, onLogout }) {
  return (
    <aside className="sidebar" aria-label="Primary">
      <div className="brand">
        <div className="brandMark"><Icon name="logo" /></div>
        <span>Vokrr</span>
      </div>
      <nav className="sideNav">
        {NAV_ITEMS.map((item) => {
          const active = activeView === item.key || (item.action === "settings" && settingsOpen);
          const isSettings = item.action === "settings";
          return (
            <div key={item.key} className={`sideNavSlot ${isSettings && settingsOpen ? "open" : ""}`}>
              <button
                className={`sideNavItem ${active ? "active" : ""}`}
                onClick={() => onSelect(item)}
                type="button"
                disabled={item.disabled}
                aria-expanded={isSettings ? settingsOpen : undefined}
              >
                {active && <span className="activeRail" aria-hidden="true" />}
                <Icon name={item.icon} />
                <span>{item.label}</span>
                {isSettings && (
                  <span className={`caret ${settingsOpen ? "open" : ""}`} aria-hidden="true">
                    <Icon name="chevron" />
                  </span>
                )}
              </button>
              {isSettings && settingsOpen && (
                <div className="settingsMenu" role="menu">
                  <button type="button" role="menuitem" onClick={onHardRefresh}>
                    <Icon name="refresh" />
                    <span>Hard refresh</span>
                  </button>
                  <button type="button" role="menuitem" onClick={onLogout}>
                    <Icon name="logout" />
                    <span>Sign out</span>
                  </button>
                </div>
              )}
            </div>
          );
        })}
      </nav>
    </aside>
  );
}

function Header({
  title,
  assistantStatus,
  assistantDisplay,
  health,
  healthError,
  notifications,
  notificationsOpen,
  onToggleNotifications,
  onClearNotifications,
}) {
  const haOk = health?.home_assistant?.ok;
  const statusLabel = healthError
    ? "Offline"
    : haOk
      ? "Online"
      : health
        ? "HA offline"
        : "…";
  const unreadCount = notifications.length;
  const jarvisLabel = JARVIS_STATUS_LABELS[assistantStatus] ?? assistantStatus;
  const showTranscript = Boolean(assistantDisplay) && assistantStatus !== "idle";
  return (
    <header className="topBar">
      <h1 className="pageTitle">{title}</h1>
      <div className={`jarvisBar ${assistantStatus}`} aria-live="polite">
        <div className="jarvisBarOrb">
          <span />
        </div>
        <div className="jarvisBarText">
          <span className="jarvisLabel">{jarvisLabel}</span>
          <span className="jarvisTranscript">
            {showTranscript ? (
              <>
                {assistantDisplay}
                <i aria-hidden="true" />
              </>
            ) : (
              <span className="muted">Say "Jarvis" to start</span>
            )}
          </span>
        </div>
      </div>
      <div className="topActions">
        <div className="notifWrap">
          <button
            className="iconButton"
            type="button"
            onClick={onToggleNotifications}
            aria-label="Notifications"
            aria-expanded={notificationsOpen}
          >
            <Icon name="bell" />
            {unreadCount > 0 && <span className="notifBadge">{unreadCount > 9 ? "9+" : unreadCount}</span>}
          </button>
          {notificationsOpen && (
            <div className="notifDropdown" role="dialog" aria-label="Notifications">
              <div className="notifHead">
                <span>Notifications</span>
                <button type="button" onClick={onClearNotifications} disabled={!unreadCount}>
                  Clear
                </button>
              </div>
              <ul className="notifList">
                {notifications.length === 0 && <li className="notifEmpty">No notifications yet.</li>}
                {notifications.map((entry) => (
                  <li key={entry.id} className={`notifItem ${entry.level}`}>
                    <span className="notifDot" />
                    <div>
                      <p>{entry.message}</p>
                      <time>{formatRelative(entry.createdAt)}</time>
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
        <div className={`hostStatus ${haOk ? "ok" : health ? "err" : "warn"}`} title={healthError || ""}>
          <span className="dot" />
          <span>{statusLabel}</span>
        </div>
      </div>
    </header>
  );
}

function formatRelative(timestamp) {
  const diff = Math.max(0, Date.now() - timestamp);
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return new Date(timestamp).toLocaleString();
}

function RoomTabs({ rooms, selectedRoom, onSelect, onAddDevice }) {
  return (
    <nav className="roomTabs" aria-label="Rooms">
      <div className="roomTabsInner">
        {rooms.map((room) => {
          const active = room.id === selectedRoom?.id;
          return (
            <button
              key={room.id}
              onClick={() => onSelect(room.id)}
              className={`roomTab ${active ? "active" : ""}`}
              type="button"
            >
              {room.name}
            </button>
          );
        })}
        <button className="roomTab add" type="button" disabled>+ Add</button>
      </div>
      <button className="addDevice" type="button" onClick={onAddDevice} disabled>
        + Add Device
      </button>
    </nav>
  );
}

function DashboardView({
  rooms,
  selectedRoom,
  onSelectRoom,
  scenes,
  onRunScene,
  heroDevice,
  visibleDevices,
  lights,
  onToggle,
  onSet,
}) {
  return (
    <div className="dashboard">
      <RoomTabs rooms={rooms} selectedRoom={selectedRoom} onSelect={onSelectRoom} />

      <section className="topGrid">
        <HeroDeviceCard device={heroDevice} onToggle={onToggle} onSet={onSet} />
      </section>

      <section className="devicesRow">
        <div className="sectionHead">
          <h2>My Devices</h2>
          <span className="muted">{visibleDevices.length} in {selectedRoom?.name ?? "room"}</span>
        </div>
        <div className="deviceGrid">
          {visibleDevices.map((device) => (
            <DeviceTile
              key={device.id}
              device={device}
              onToggle={() => onToggle(device)}
              onSet={(payload) => onSet(device, payload)}
            />
          ))}
          {!visibleDevices.length && <EmptyPanel text="No devices for this room." />}
        </div>
      </section>

      <aside className="lightsPanel">
        <div className="sectionHead">
          <h2>Light</h2>
          <span className="muted">{lights.length}</span>
        </div>
        <div className="lightsList">
          {lights.map((light) => (
            <LightRow
              key={light.id}
              device={light}
              onToggle={() => onToggle(light)}
              onSet={(payload) => onSet(light, payload)}
            />
          ))}
          {!lights.length && <EmptyPanel text="No dimmable lights configured." />}
        </div>
      </aside>
    </div>
  );
}

function HeroDeviceCard({ device, onToggle, onSet }) {
  if (!device) return <div className="heroCard empty">Select a room with devices.</div>;

  const hasBrightness = device.capabilities?.includes("brightness");
  const hasPercentage = device.capabilities?.includes("percentage");
  const level = device.state?.brightness ?? device.state?.percentage ?? 0;
  const unavailable = device.state?.state === "unavailable" || device.state?.state === "unknown";
  const kelvin = device.state?.color_temp_kelvin ?? 6500;

  return (
    <article className={`heroCard ${device.state?.is_on ? "on" : ""}`}>
      <div className="heroHeader">
        <div>
          <h2>{device.name}</h2>
          <p className="muted caps">{device.type} · {device.room_name}</p>
        </div>
        <ToggleSwitch
          on={!!device.state?.is_on}
          disabled={unavailable}
          onChange={() => onToggle(device)}
        />
      </div>

      <div className="heroValue">
        <div className="bigNumber">
          <span className="num">{hasBrightness || hasPercentage ? level : (device.state?.is_on ? "On" : "Off")}</span>
          <span className="unit">{hasBrightness ? "%" : hasPercentage ? "%" : ""}</span>
        </div>
        <p className="muted">{hasBrightness ? "Brightness" : hasPercentage ? "Speed" : "State"}</p>
      </div>

      {(hasBrightness || hasPercentage) && (
        <div className="heroSlider">
          <span className="bound">0%</span>
          <input
            type="range"
            min="0"
            max="100"
            value={level}
            disabled={unavailable}
            onChange={(event) =>
              onSet(device, hasBrightness
                ? { brightness: Number(event.target.value) }
                : { percentage: Number(event.target.value) })
            }
          />
          <span className="bound">100%</span>
        </div>
      )}

      {device.capabilities?.includes("color_temperature") && (
        <div className="heroSlider">
          <span className="bound">2000K</span>
          <input
            type="range"
            min="2000"
            max="6500"
            step="100"
            value={kelvin}
            disabled={unavailable}
            onChange={(event) =>
              onSet(device, { color_temp_kelvin: Number(event.target.value) })
            }
          />
          <span className="bound">6500K</span>
        </div>
      )}

      <div className="presetRow">
        {AC_PRESETS.map((preset) => (
          <button
            key={preset.key}
            className="presetBtn"
            type="button"
            aria-label={preset.label}
            title={preset.label}
            disabled
          >
            <Icon name={preset.icon} />
          </button>
        ))}
      </div>
    </article>
  );
}

function AssistantPanel({ status, display, scenes, onRunScene }) {
  return (
    <article className={`assistantPanel ${status}`}>
      <div className="sectionHead">
        <h2>Jarvis</h2>
        <span className="muted caps">{status}</span>
      </div>
      <div className="assistantOrb"><span /></div>
      <p className="assistantText">
        {display || "Listening for Jarvis"}
        <i aria-hidden="true" />
      </p>
      {!!scenes.length && (
        <div className="scenePills" aria-label="Scenes">
          {scenes.map((s) => (
            <button key={s.id} type="button" onClick={() => onRunScene(s)} className="scenePill">
              {s.name}
            </button>
          ))}
        </div>
      )}
      <div className="assistantHints">
        <span>Say "Jarvis"</span>
        <span>Try "turn off bedroom"</span>
      </div>
    </article>
  );
}

function DeviceTile({ device, onToggle, onSet }) {
  const unavailable = device.state?.state === "unavailable" || device.state?.state === "unknown";
  const hasLevel =
    device.capabilities?.includes("brightness") || device.capabilities?.includes("percentage");
  const level = device.state?.brightness ?? device.state?.percentage ?? 0;

  return (
    <article className={`deviceTile ${device.state?.is_on ? "on" : ""}`}>
      <div className="tileHeader">
        <div className="tileIcon"><Icon name={deviceIcon(device.type)} /></div>
        <ToggleSwitch on={!!device.state?.is_on} disabled={unavailable} onChange={onToggle} />
      </div>
      <h3>{device.name}</h3>
      <p className="muted tileSub">
        {unavailable ? "Unavailable" : `${device.state?.state ?? "—"}${hasLevel ? ` · ${level}%` : ""}`}
      </p>
      {hasLevel && !unavailable && (
        <input
          className="tileRange"
          type="range"
          min="0"
          max="100"
          value={level}
          onChange={(event) =>
            onSet(device.capabilities?.includes("brightness")
              ? { brightness: Number(event.target.value) }
              : { percentage: Number(event.target.value) })
          }
        />
      )}
      <div className="tileBar"><span style={{ width: `${level}%` }} /></div>
    </article>
  );
}

function LightRow({ device, onToggle, onSet }) {
  const unavailable = device.state?.state === "unavailable" || device.state?.state === "unknown";
  const level = device.state?.brightness ?? 0;
  const dots = 20;
  const filled = Math.round((level / 100) * dots);
  return (
    <div className={`lightRow ${device.state?.is_on ? "on" : ""}`}>
      <button
        className="lightBulb"
        type="button"
        aria-label={`Toggle ${device.name}`}
        onClick={onToggle}
        disabled={unavailable}
      >
        <Icon name="sun" />
      </button>
      <div className="lightBody">
        <div className="lightMeta">
          <span className="lightName">{device.name}</span>
          <span className="lightPct">{level}%</span>
        </div>
        <div className="lightDots" aria-hidden="true">
          {Array.from({ length: dots }).map((_, i) => (
            <span key={i} className={i < filled ? "on" : ""} />
          ))}
        </div>
        <input
          className="lightRange"
          type="range"
          min="0"
          max="100"
          value={level}
          disabled={unavailable}
          onChange={(event) => onSet({ brightness: Number(event.target.value) })}
          aria-label={`${device.name} brightness`}
        />
      </div>
    </div>
  );
}

function ToggleSwitch({ on, disabled, onChange }) {
  return (
    <button
      type="button"
      className={`toggleSwitch ${on ? "on" : ""}`}
      role="switch"
      aria-checked={!!on}
      onClick={onChange}
      disabled={disabled}
    >
      <span className="thumb" />
    </button>
  );
}

function DevicesView({ allDevices, onToggle, onSet }) {
  return (
    <div className="simpleView">
      <div className="sectionHead">
        <h2>All Devices</h2>
        <span className="muted">{allDevices.length} total</span>
      </div>
      <div className="deviceGrid wide">
        {allDevices.map((device) => (
          <DeviceTile
            key={device.id}
            device={device}
            onToggle={() => onToggle(device)}
            onSet={(payload) => onSet(device, payload)}
          />
        ))}
        {!allDevices.length && <EmptyPanel text="No devices configured." />}
      </div>
    </div>
  );
}

function NewsView({ url, externalUrl }) {
  return (
    <div className="newsView">
      <div className="newsToolbar">
        <span className="newsEyebrow">World Monitor</span>
        <a className="newsOpen" href={externalUrl || url} target="_blank" rel="noreferrer">
          Open in new tab
        </a>
      </div>
      <iframe
        className="newsFrame"
        src={url}
        title="World Monitor"
        referrerPolicy="no-referrer-when-downgrade"
        allow="fullscreen; clipboard-read; clipboard-write"
        loading="lazy"
      />
    </div>
  );
}

function RoutinesView({ scenes, onRunScene }) {
  return (
    <div className="simpleView">
      <div className="sectionHead">
        <h2>Routines</h2>
        <span className="muted">{scenes.length} configured</span>
      </div>
      <div className="routineGrid">
        {scenes.map((scene) => (
          <button key={scene.id} className="routineCard" onClick={() => onRunScene(scene)}>
            <Icon name="bookmark" />
            <span>{scene.name}</span>
          </button>
        ))}
        {!scenes.length && <EmptyPanel text="No routines configured." />}
      </div>
    </div>
  );
}

function ActivityView({ rooms, allDevices, health, healthError, assistantStatus, assistantDisplay }) {
  const haOk = health?.home_assistant?.ok;
  const detail = healthError || health?.home_assistant?.error || "No recent errors.";
  return (
    <div className="simpleView">
      <div className="sectionHead">
        <h2>Activity</h2>
        <span className="muted caps">{haOk ? "systems online" : "needs attention"}</span>
      </div>
      <div className="activityGrid">
        <div className="activityCard">
          <p className="muted caps">Rooms</p>
          <p className="big">{rooms.length}</p>
        </div>
        <div className="activityCard">
          <p className="muted caps">Devices</p>
          <p className="big">{allDevices.length}</p>
        </div>
        <div className="activityCard">
          <p className="muted caps">Home Assistant</p>
          <p className={`big ${haOk ? "" : "warn"}`}>{haOk ? "Online" : "Offline"}</p>
          {!haOk && <p className="muted">{detail}</p>}
        </div>
        <div className="activityCard">
          <p className="muted caps">Jarvis</p>
          <p className="big">{assistantStatus}</p>
          <p className="muted">{assistantDisplay || "Listening for Jarvis"}</p>
        </div>
      </div>
    </div>
  );
}

function EmptyPanel({ text }) {
  return <div className="emptyPanel">{text}</div>;
}

function LoginScreen({ error, onLogin }) {
  return (
    <main className="loginShell">
      <form className="loginPanel" onSubmit={onLogin}>
        <div className="brand">
          <div className="brandMark"><Icon name="logo" /></div>
          <span>Vokrr</span>
        </div>
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

function deviceIcon(type) {
  switch (type) {
    case "light": return "sun";
    case "switch": return "plug";
    case "fan": return "wind";
    case "climate": return "snow";
    case "speaker": return "speaker";
    case "tv": return "monitor";
    default: return "dot";
  }
}

function Icon({ name }) {
  const s = { fill: "none", stroke: "currentColor", strokeWidth: 1.6, strokeLinecap: "round", strokeLinejoin: "round" };
  switch (name) {
    case "logo":
      return (
        <svg viewBox="0 0 32 32" width="24" height="24" aria-hidden="true">
          <defs>
            <linearGradient id="qh-logo" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#cbb3ff" />
              <stop offset="100%" stopColor="#8fd3ff" />
            </linearGradient>
          </defs>
          <path d="M5 7.5 16 3l11 4.5v9c0 7-5.2 10.8-11 12.5-5.8-1.7-11-5.5-11-12.5z" fill="url(#qh-logo)" stroke="none" />
          <path d="M11 15.5h10M11 12h10M11 19h6" stroke="#17121f" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      );
    case "grid":
      return (<svg viewBox="0 0 24 24" width="20" height="20" {...s}><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>);
    case "devices":
      return (<svg viewBox="0 0 24 24" width="20" height="20" {...s}><rect x="3" y="5" width="13" height="11" rx="2"/><rect x="15" y="9" width="6" height="10" rx="1.5"/><path d="M7 20h5"/></svg>);
    case "bookmark":
      return (<svg viewBox="0 0 24 24" width="20" height="20" {...s}><path d="M7 4h10a1 1 0 0 1 1 1v16l-6-4-6 4V5a1 1 0 0 1 1-1z"/></svg>);
    case "clock":
      return (<svg viewBox="0 0 24 24" width="20" height="20" {...s}><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>);
    case "news":
      return (<svg viewBox="0 0 24 24" width="20" height="20" {...s}><path d="M4 5h13a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5z"/><path d="M18 9h2a1 1 0 0 1 1 1v8a2 2 0 0 1-2 2"/><path d="M7 9h7M7 13h7M7 17h4"/></svg>);
    case "help":
      return (<svg viewBox="0 0 24 24" width="20" height="20" {...s}><circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.9.4-1 1-1 1.7M12 17h.01"/></svg>);
    case "settings":
      return (<svg viewBox="0 0 24 24" width="20" height="20" {...s}><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V9c.3.6.9 1 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>);
    case "search":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>);
    case "chevron":
      return (<svg viewBox="0 0 24 24" width="14" height="14" {...s}><path d="m6 9 6 6 6-6"/></svg>);
    case "refresh":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M20 11a8 8 0 1 0-2.2 5.6"/><path d="M20 4v6h-6"/></svg>);
    case "logout":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M9 4H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/></svg>);
    case "bell":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M6 15V10a6 6 0 1 1 12 0v5l1.5 2H4.5z"/><path d="M10 19a2 2 0 0 0 4 0"/></svg>);
    case "snow":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M12 3v18M3 12h18M5.5 5.5l13 13M18.5 5.5l-13 13"/></svg>);
    case "flash":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M13 3 4 14h7l-1 7 9-11h-7z"/></svg>);
    case "wind":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M3 10h12a3 3 0 1 0-3-3M3 14h16a3 3 0 1 1-3 3"/></svg>);
    case "drop":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M12 3s6 7 6 12a6 6 0 1 1-12 0c0-5 6-12 6-12z"/></svg>);
    case "moon":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z"/></svg>);
    case "sun":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M2 12h2M20 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/></svg>);
    case "plug":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><path d="M9 3v5M15 3v5M7 8h10v4a5 5 0 0 1-10 0zM12 17v4"/></svg>);
    case "speaker":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><rect x="6" y="3" width="12" height="18" rx="2"/><circle cx="12" cy="14" r="3"/><circle cx="12" cy="7" r="1"/></svg>);
    case "monitor":
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M9 20h6M12 16v4"/></svg>);
    case "dot":
    default:
      return (<svg viewBox="0 0 24 24" width="18" height="18" {...s}><circle cx="12" cy="12" r="4"/></svg>);
  }
}

createRoot(document.getElementById("root")).render(<App />);
