#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <esp_crt_bundle.h>
#include <esp_display_panel.hpp>
#include <esp_http_client.h>
#include <esp_log.h>
#include <lvgl.h>
#include <time.h>

#include <Button.h>
#include <ESP_Knob.h>

#include "config_private.h"
#include "knob_ui.h"
#include "lvgl_v8_port.h"

#define GPIO_NUM_KNOB_PIN_A 6
#define GPIO_NUM_KNOB_PIN_B 5
#define GPIO_BUTTON_PIN GPIO_NUM_0

#ifndef VOKRR_TIMEZONE
#define VOKRR_TIMEZONE "IST-5:30"
#endif

using namespace esp_panel::board;
using namespace esp_panel::drivers;

namespace {

static const char *TAG = "VokrrKnob";

constexpr size_t MAX_ROOMS = 6;
constexpr size_t MAX_DEVICES_PER_ROOM = 16;
constexpr uint32_t REFRESH_MS_POLLING = 10000;
constexpr uint32_t WIFI_RETRY_MS = 12000;
constexpr uint32_t BACKEND_RETRY_MS = 5000;
constexpr uint16_t HTTP_TIMEOUT_MS = 8000;
constexpr uint16_t BUTTON_BACK_HOLD_MS = 500;
constexpr const char *NTP_SERVER_PRIMARY = "162.159.200.1";
constexpr const char *NTP_SERVER_SECONDARY = "162.159.200.123";

struct DeviceState {
  String id;
  String name;
  String type;
  bool isOn = false;
  bool unavailable = false;
  bool toggleable = true;
  int level = -1;
  int powerWatts = -1;
};

struct RoomState {
  String id;
  String name;
  String icon;
  DeviceState devices[MAX_DEVICES_PER_ROOM];
  size_t deviceCount = 0;
};

struct RoomProfile {
  const char *name;
  const char *const *devices;
  size_t deviceCount;
};

struct ToggleJob {
  String deviceId;
  bool previousOn = false;
  bool ok = false;
  int statusCode = -1;
};

const char *const LIVING_ROOM_DEVICES[] = {"Bulb", "Fan", "Socket", "Tubelight"};
const char *const KITCHEN_DEVICES[] = {"Left Bulb", "Right Bulb"};
const char *const GAMING_ROOM_DEVICES[] = {"Tubelight", "Socket", "Fan", "Bulb", "Tubelight"};
const char *const BEDROOM_DEVICES[] = {"Tubelight", "Aircon Socket", "Bulb", "Fan", "Socket", "Tubelight"};
const char *const BATHROOM_DEVICES[] = {"Geyser"};
const char *const DINING_ROOM_DEVICES[] = {"Tubelight", "Bulb"};

const RoomProfile ROOM_PROFILES[] = {
    {"Living Room", LIVING_ROOM_DEVICES, sizeof(LIVING_ROOM_DEVICES) / sizeof(LIVING_ROOM_DEVICES[0])},
    {"Kitchen", KITCHEN_DEVICES, sizeof(KITCHEN_DEVICES) / sizeof(KITCHEN_DEVICES[0])},
    {"Gaming Room", GAMING_ROOM_DEVICES, sizeof(GAMING_ROOM_DEVICES) / sizeof(GAMING_ROOM_DEVICES[0])},
    {"Bedroom", BEDROOM_DEVICES, sizeof(BEDROOM_DEVICES) / sizeof(BEDROOM_DEVICES[0])},
    {"Bathroom", BATHROOM_DEVICES, sizeof(BATHROOM_DEVICES) / sizeof(BATHROOM_DEVICES[0])},
    {"Dining Room", DINING_ROOM_DEVICES, sizeof(DINING_ROOM_DEVICES) / sizeof(DINING_ROOM_DEVICES[0])},
};

enum class PendingAction : uint8_t { None, Activate, Back };

RoomState rooms[MAX_ROOMS];
size_t roomCount = 0;
size_t activeRoom = 0;
size_t activeDevice = 0;
bool inDeviceMode = false;
bool busy = false;
bool forceRefresh = false;
bool lastRequestFailed = false;
String busyDeviceId;

String accessToken;
String refreshToken;
uint32_t tokenRefreshAt = 0;
uint32_t lastRefresh = 0;
uint32_t lastWifiAttempt = 0;
uint32_t lastBackendAttempt = 0;
uint32_t lastClockUpdate = 0;
bool timeConfigured = false;
bool connectionDiagnosticsPrinted = false;
bool displayReady = false;
bool secureSessionLost = false;
volatile bool uiRenderPending = false;
volatile bool buttonBackQueued = false;

esp_http_client_handle_t restClient = nullptr;
volatile int pendingRotation = 0;
volatile PendingAction pendingAction = PendingAction::None;
portMUX_TYPE inputMux = portMUX_INITIALIZER_UNLOCKED;
QueueHandle_t toggleRequestQueue = nullptr;
QueueHandle_t toggleResultQueue = nullptr;
SemaphoreHandle_t modelMutex = nullptr;

ESP_Knob *knob = nullptr;
Button *button = nullptr;

class ModelGuard {
 public:
  ModelGuard() {
    if (modelMutex) xSemaphoreTakeRecursive(modelMutex, portMAX_DELAY);
  }

  ~ModelGuard() {
    if (modelMutex) xSemaphoreGiveRecursive(modelMutex);
  }
};

void initializeLocalTopology() {
  ModelGuard guard;
  roomCount = sizeof(ROOM_PROFILES) / sizeof(ROOM_PROFILES[0]);
  for (size_t roomIndex = 0; roomIndex < roomCount; ++roomIndex) {
    const RoomProfile &profile = ROOM_PROFILES[roomIndex];
    RoomState &room = rooms[roomIndex];
    room = RoomState{};
    room.name = profile.name;
    room.icon = "room";
    room.deviceCount = profile.deviceCount;

    for (size_t deviceIndex = 0; deviceIndex < room.deviceCount; ++deviceIndex) {
      DeviceState &device = room.devices[deviceIndex];
      device = DeviceState{};
      device.name = profile.devices[deviceIndex];
      device.type = profile.devices[deviceIndex];
      device.unavailable = true;
      device.toggleable = false;
    }
  }
}

bool setRequestFailed(bool failed) {
  ModelGuard guard;
  if (lastRequestFailed == failed) return false;
  lastRequestFailed = failed;
  return true;
}

bool hasRooms() {
  ModelGuard guard;
  return roomCount > 0;
}

String httpUrl(const String &path) {
  String base = String(VOKRR_API_BASE);
  while (base.endsWith("/")) base.remove(base.length() - 1);
  return base + path;
}

String lower(const String &value) {
  String result = value;
  result.toLowerCase();
  return result;
}

bool includes(const String &value, const char *needle) {
  return value.indexOf(needle) >= 0;
}

String urlEncode(const String &value) {
  static const char HEX_DIGITS[] = "0123456789ABCDEF";
  String encoded;
  encoded.reserve(value.length() * 2);
  for (size_t i = 0; i < value.length(); ++i) {
    const uint8_t c = static_cast<uint8_t>(value[i]);
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
      encoded += static_cast<char>(c);
    } else {
      encoded += '%';
      encoded += HEX_DIGITS[c >> 4];
      encoded += HEX_DIGITS[c & 0x0F];
    }
  }
  return encoded;
}

esp_err_t restEventHandler(esp_http_client_event_t *event) {
  if (event->event_id == HTTP_EVENT_ON_DATA && event->user_data && event->data && event->data_len > 0) {
    static_cast<String *>(event->user_data)->concat(static_cast<const char *>(event->data), event->data_len);
  }
  return ESP_OK;
}

int performRestRequest(const String &path, esp_http_client_method_t method, const String &body,
                       String &response, bool authenticated) {
  const String url = httpUrl(path);
  response = "";
  if (!restClient) {
    esp_http_client_config_t config = {};
    config.url = url.c_str();
    config.timeout_ms = HTTP_TIMEOUT_MS;
    config.buffer_size = 2048;
    config.buffer_size_tx = 2048;
    config.event_handler = restEventHandler;
    config.crt_bundle_attach = esp_crt_bundle_attach;
    config.keep_alive_enable = true;
    config.keep_alive_idle = 15;
    config.keep_alive_interval = 5;
    config.keep_alive_count = 3;
    config.user_agent = "Vokrr-Knob/1.0";
    config.tls_version = ESP_HTTP_CLIENT_TLS_VER_TLS_1_2;
    restClient = esp_http_client_init(&config);
  }
  if (!restClient) return -1;

  esp_http_client_set_url(restClient, url.c_str());
  esp_http_client_set_user_data(restClient, &response);
  esp_http_client_set_method(restClient, method);
  esp_http_client_set_header(restClient, "Accept", "application/json");
  esp_http_client_delete_header(restClient, "Authorization");
  if (authenticated && accessToken.length()) {
    const String authorization = "Bearer " + accessToken;
    esp_http_client_set_header(restClient, "Authorization", authorization.c_str());
  }
  if (method == HTTP_METHOD_POST) {
    esp_http_client_set_header(restClient, "Content-Type", "application/json");
    esp_http_client_set_post_field(restClient, body.c_str(), body.length());
  } else {
    esp_http_client_set_post_field(restClient, nullptr, 0);
  }

  const esp_err_t result = esp_http_client_perform(restClient);
  const int statusCode = result == ESP_OK ? esp_http_client_get_status_code(restClient) : -1;
  esp_http_client_set_user_data(restClient, nullptr);
  if (result != ESP_OK) ESP_LOGE(TAG, "HTTP %s failed: %s", path.c_str(), esp_err_to_name(result));
  if (result != ESP_OK) {
    esp_http_client_cleanup(restClient);
    restClient = nullptr;
    if (displayReady) secureSessionLost = true;
  }
  return statusCode;
}

RoomState *currentRoom() {
  if (roomCount == 0) return nullptr;
  if (activeRoom >= roomCount) activeRoom = roomCount - 1;
  return &rooms[activeRoom];
}

DeviceState *currentDevice() {
  RoomState *room = currentRoom();
  if (!room || room->deviceCount == 0) return nullptr;
  if (activeDevice >= room->deviceCount) activeDevice = room->deviceCount - 1;
  return &room->devices[activeDevice];
}

size_t roomOnCount(const RoomState &room) {
  size_t count = 0;
  for (size_t i = 0; i < room.deviceCount; ++i) {
    if (room.devices[i].isOn && !room.devices[i].unavailable) ++count;
  }
  return count;
}

KnobIcon roomIcon(const RoomState &room) {
  const String key = lower(room.icon + " " + room.name);
  if (includes(key, "living") || includes(key, "lounge") || includes(key, "sofa")) return KnobIcon::Sofa;
  if (includes(key, "kitchen")) return KnobIcon::Kitchen;
  if (includes(key, "gaming") || includes(key, "game")) return KnobIcon::Gamepad;
  if (includes(key, "bed")) return KnobIcon::Bed;
  if (includes(key, "bath") || includes(key, "wash")) return KnobIcon::Drop;
  if (includes(key, "dining")) return KnobIcon::Dining;
  return KnobIcon::Home;
}

KnobIcon deviceIcon(const DeviceState &device) {
  const String key = lower(device.type + " " + device.name);
  if (includes(key, "tube")) return KnobIcon::Tube;
  if (includes(key, "fan")) return KnobIcon::Fan;
  if (includes(key, "socket") || includes(key, "plug") || includes(key, "switch")) return KnobIcon::Socket;
  if (includes(key, "aircon") || includes(key, "air con") || includes(key, "climate") || includes(key, " ac")) return KnobIcon::Climate;
  if (includes(key, "geyser") || includes(key, "heater")) return KnobIcon::Geyser;
  if (includes(key, "tv") || includes(key, "television")) return KnobIcon::Tv;
  if (includes(key, "speaker") || includes(key, "audio")) return KnobIcon::Speaker;
  if (includes(key, "light") || includes(key, "bulb") || includes(key, "lamp")) return KnobIcon::Bulb;
  return KnobIcon::Socket;
}

int readPowerWatts(JsonObject state) {
  JsonObject attributes = state["attributes"].as<JsonObject>();
  if (attributes.isNull()) return -1;
  static const char *POWER_KEYS[] = {"power", "current_power_w", "current_power", "power_consumption"};
  for (const char *key : POWER_KEYS) {
    JsonVariant value = attributes[key];
    if (value.is<float>() || value.is<int>() || value.is<unsigned int>()) {
      const float watts = value.as<float>();
      if (watts >= 0.0f && watts < 100000.0f) return static_cast<int>(lroundf(watts));
    }
  }
  return -1;
}

bool hasToggleCapability(JsonObject deviceJson) {
  JsonArray capabilities = deviceJson["capabilities"].as<JsonArray>();
  if (capabilities.isNull() || capabilities.size() == 0) return true;
  for (JsonVariant capability : capabilities) {
    const char *value = capability.as<const char *>();
    if (value && strcmp(value, "toggle") == 0) return true;
  }
  return false;
}

void applyDeviceFromJson(DeviceState &device, JsonObject deviceJson) {
  device.id = deviceJson["id"] | "";
  device.name = deviceJson["name"] | "Device";
  device.type = deviceJson["type"] | "unknown";
  device.toggleable = hasToggleCapability(deviceJson);
  JsonObject state = deviceJson["state"].as<JsonObject>();
  const char *rawState = state["state"] | "unknown";
  device.isOn = state["is_on"] | false;
  device.unavailable = strcmp(rawState, "unavailable") == 0 || strcmp(rawState, "unknown") == 0;
  if (!state["brightness"].isNull()) {
    device.level = state["brightness"].as<int>();
  } else if (!state["percentage"].isNull()) {
    device.level = state["percentage"].as<int>();
  } else {
    device.level = -1;
  }
  device.powerWatts = readPowerWatts(state);
}

bool updateDeviceFromJson(DeviceState &device, JsonObject deviceJson) {
  const bool previousOn = device.isOn;
  const bool previousUnavailable = device.unavailable;
  const bool previousToggleable = device.toggleable;
  const int previousLevel = device.level;
  const int previousPowerWatts = device.powerWatts;
  applyDeviceFromJson(device, deviceJson);
  return device.isOn != previousOn || device.unavailable != previousUnavailable ||
         device.toggleable != previousToggleable || device.level != previousLevel ||
         device.powerWatts != previousPowerWatts;
}

bool mergeDevicePayload(JsonObject payload) {
  ModelGuard guard;
  const String id = payload["id"] | "";
  if (!id.length()) return false;
  for (size_t r = 0; r < roomCount; ++r) {
    for (size_t d = 0; d < rooms[r].deviceCount; ++d) {
      if (rooms[r].devices[d].id == id) {
        return updateDeviceFromJson(rooms[r].devices[d], payload);
      }
    }
  }
  return false;
}

bool mergeRoomPayload(JsonObject payload) {
  ModelGuard guard;
  const String roomId = payload["id"] | "";
  JsonArray sourceDevices = payload["devices"].as<JsonArray>();
  if (!roomId.length() || sourceDevices.isNull()) return false;

  for (size_t r = 0; r < roomCount; ++r) {
    if (rooms[r].id != roomId) continue;
    bool changed = false;
    for (JsonObject sourceDevice : sourceDevices) {
      const String deviceId = sourceDevice["id"] | "";
      if (!deviceId.length()) continue;
      for (size_t d = 0; d < rooms[r].deviceCount; ++d) {
        if (rooms[r].devices[d].id == deviceId) {
          changed = updateDeviceFromJson(rooms[r].devices[d], sourceDevice) || changed;
          break;
        }
      }
    }
    return changed;
  }
  return false;
}

DeviceState *findDeviceById(const String &id) {
  for (size_t r = 0; r < roomCount; ++r) {
    for (size_t d = 0; d < rooms[r].deviceCount; ++d) {
      if (rooms[r].devices[d].id == id) return &rooms[r].devices[d];
    }
  }
  return nullptr;
}

void parseRooms(JsonArray root) {
  ModelGuard guard;
  for (size_t roomIndex = 0; roomIndex < roomCount; ++roomIndex) {
    const RoomProfile &profile = ROOM_PROFILES[roomIndex];
    RoomState &room = rooms[roomIndex];
    JsonObject roomJson;
    for (JsonObject candidate : root) {
      const String candidateName = candidate["name"] | "";
      if (candidateName.equalsIgnoreCase(profile.name)) {
        roomJson = candidate;
        break;
      }
    }
    room.id = "";
    room.icon = "room";
    for (size_t deviceIndex = 0; deviceIndex < room.deviceCount; ++deviceIndex) {
      room.devices[deviceIndex].id = "";
      room.devices[deviceIndex].unavailable = true;
      room.devices[deviceIndex].toggleable = false;
    }
    if (roomJson.isNull()) continue;

    room.id = roomJson["id"] | "";
    room.icon = roomJson["icon"] | "room";

    JsonArray sourceDevices = roomJson["devices"].as<JsonArray>();
    for (size_t desiredIndex = 0; desiredIndex < profile.deviceCount; ++desiredIndex) {
      const char *desiredName = profile.devices[desiredIndex];
      size_t desiredOccurrence = 0;
      for (size_t previous = 0; previous < desiredIndex; ++previous) {
        if (String(profile.devices[previous]).equalsIgnoreCase(desiredName)) ++desiredOccurrence;
      }

      size_t occurrence = 0;
      for (JsonObject deviceJson : sourceDevices) {
        const String sourceName = deviceJson["name"] | "";
        if (!sourceName.equalsIgnoreCase(desiredName)) continue;
        if (occurrence++ != desiredOccurrence) continue;
        applyDeviceFromJson(room.devices[desiredIndex], deviceJson);
        break;
      }
    }
  }
}

void renderUi() {
  KnobUiModel model;
  model.deviceMode = inDeviceMode;
  model.online = WiFi.status() == WL_CONNECTED && accessToken.length() > 0;
  model.live = false;
  model.busy = false;

  RoomState *room = currentRoom();
  if (!room) {
    model.name = lastRequestFailed ? "CONNECTION LOST" : "NO ROOMS";
    model.status = WiFi.status() == WL_CONNECTED ? "SYNCING WITH VOKRR" : "WIFI OFFLINE";
    model.hint = "PRESS TO RETRY";
    model.icon = lastRequestFailed ? KnobIcon::Warning : KnobIcon::Home;
    model.itemCount = 0;
    model.selectedIndex = 0;
    knobUiRender(model);
    return;
  }

  if (!inDeviceMode) {
    static char roomStatus[48];
    lv_snprintf(roomStatus, sizeof(roomStatus), "%u DEVICES  |  %u ON",
                static_cast<unsigned>(room->deviceCount), static_cast<unsigned>(roomOnCount(*room)));
    model.name = room->name.c_str();
    model.status = roomStatus;
    model.hint = room->deviceCount ? "PRESS TO OPEN" : "NO CONTROLLABLE DEVICES";
    model.icon = roomIcon(*room);
    model.itemCount = roomCount;
    model.selectedIndex = activeRoom;
    for (size_t i = 0; i < roomCount && i < 16; ++i) {
      if (roomOnCount(rooms[i]) > 0) model.activeMask |= static_cast<uint16_t>(1U << i);
    }
    knobUiRender(model);
    return;
  }

  DeviceState *device = currentDevice();
  if (!device) {
    model.name = "NO DEVICES";
    model.status = "RETURN TO ROOMS";
    model.hint = "HOLD TO GO BACK";
    model.icon = KnobIcon::Warning;
    model.itemCount = 0;
    model.selectedIndex = 0;
    knobUiRender(model);
    return;
  }

  const bool selectedDeviceBusy = busy && device->id == busyDeviceId;
  model.busy = selectedDeviceBusy;
  static char deviceStatus[48];
  if (device->unavailable) {
    lv_snprintf(deviceStatus, sizeof(deviceStatus), "UNAVAILABLE");
  } else if (selectedDeviceBusy) {
    lv_snprintf(deviceStatus, sizeof(deviceStatus), "UPDATING");
  } else if (device->isOn && device->powerWatts >= 0) {
    lv_snprintf(deviceStatus, sizeof(deviceStatus), "ON  |  %dW", device->powerWatts);
  } else {
    lv_snprintf(deviceStatus, sizeof(deviceStatus), "%s", device->isOn ? "ON" : "OFF");
  }

  model.name = device->name.c_str();
  model.status = deviceStatus;
  model.hint = device->unavailable ? "WAITING FOR DEVICE" : "PRESS TO TOGGLE";
  model.icon = deviceIcon(*device);
  model.itemCount = room->deviceCount;
  model.selectedIndex = activeDevice;
  for (size_t i = 0; i < room->deviceCount && i < 16; ++i) {
    if (room->devices[i].isOn && !room->devices[i].unavailable) {
      model.activeMask |= static_cast<uint16_t>(1U << i);
    }
  }
  model.on = device->isOn;
  model.unavailable = device->unavailable;
  knobUiRender(model);
}

void requestUiRender() {
  if (!displayReady) return;
  portENTER_CRITICAL(&inputMux);
  uiRenderPending = true;
  portEXIT_CRITICAL(&inputMux);
}

bool takeUiRenderRequest() {
  portENTER_CRITICAL(&inputMux);
  const bool pending = uiRenderPending;
  uiRenderPending = false;
  portEXIT_CRITICAL(&inputMux);
  return pending;
}

void renderPendingUiNow() {
  if (!displayReady || !takeUiRenderRequest()) return;
  ModelGuard guard;
  renderUi();
}

int postJsonRaw(const String &path, const String &body, JsonDocument *out, bool authenticated) {
  String payload;
  const int code = performRestRequest(path, HTTP_METHOD_POST, body, payload, authenticated);
  if (code >= 200 && code < 300 && out) {
    const DeserializationError error = deserializeJson(*out, payload);
    if (error) {
      ESP_LOGE(TAG, "Invalid JSON from POST %s (%u bytes): %s", path.c_str(),
               static_cast<unsigned>(payload.length()), error.c_str());
      return -2;
    }
  }
  if (code < 200 || code >= 300) ESP_LOGW(TAG, "POST %s returned %d", path.c_str(), code);
  return code;
}

int getJsonRaw(const String &path, JsonDocument &out) {
  String payload;
  const int code = performRestRequest(path, HTTP_METHOD_GET, "", payload, true);
  if (code >= 200 && code < 300) {
    const DeserializationError error = deserializeJson(out, payload);
    if (error) {
      ESP_LOGE(TAG, "Invalid JSON from GET %s (%u bytes): %s", path.c_str(),
               static_cast<unsigned>(payload.length()), error.c_str());
      return -2;
    }
  } else {
    ESP_LOGW(TAG, "GET %s returned %d", path.c_str(), code);
  }
  return code;
}

void applySession(JsonDocument &document) {
  accessToken = document["access_token"].as<String>();
  refreshToken = document["refresh_token"].as<String>();
  const uint32_t expiresIn = document["expires_in"] | 900;
  const uint32_t refreshIn = expiresIn > 90 ? expiresIn - 60 : 30;
  tokenRefreshAt = millis() + refreshIn * 1000UL;
}

bool login() {
  JsonDocument request;
  request["username"] = VOKRR_USERNAME;
  request["password"] = VOKRR_PASSWORD;
  String body;
  serializeJson(request, body);

  JsonDocument response;
  ESP_LOGI(TAG, "Authenticating with Vokrr");
  const int code = postJsonRaw("/api/auth/login", body, &response, false);
  if (code < 200 || code >= 300 || response["access_token"].isNull() ||
      response["refresh_token"].isNull()) {
    Serial.printf("[Vokrr] Authentication failed (%d)\n", code);
    accessToken = "";
    refreshToken = "";
    return false;
  }
  applySession(response);
  Serial.println("[Vokrr] Authenticated");
  return true;
}

bool refreshSession() {
  if (!refreshToken.length()) return false;
  JsonDocument request;
  request["refresh_token"] = refreshToken;
  String body;
  serializeJson(request, body);

  JsonDocument response;
  const int code = postJsonRaw("/api/auth/refresh", body, &response, false);
  if (code < 200 || code >= 300 || response["access_token"].isNull()) return false;
  applySession(response);
  return true;
}

bool renewSession() {
  return refreshSession() || login();
}

bool getJson(const String &path, JsonDocument &out) {
  int code = getJsonRaw(path, out);
  if (code == 401 && renewSession()) code = getJsonRaw(path, out);
  return code >= 200 && code < 300;
}

bool fetchRooms() {
  lastRefresh = millis();
  JsonDocument document;
  if (!getJson("/api/rooms", document)) {
    if (setRequestFailed(true) && !hasRooms()) requestUiRender();
    return false;
  }
  JsonArray payload = document.as<JsonArray>();
  if (payload.isNull()) {
    if (setRequestFailed(true) && !hasRooms()) requestUiRender();
    return false;
  }
  parseRooms(payload);
  setRequestFailed(false);
  ESP_LOGI(TAG, "Synced %u rooms", static_cast<unsigned>(roomCount));
  Serial.printf("[Vokrr] Synced %u rooms\n", static_cast<unsigned>(roomCount));
  requestUiRender();
  return true;
}

bool fetchSelectedRoom() {
  String roomId;
  {
    ModelGuard guard;
    RoomState *room = currentRoom();
    if (room) roomId = room->id;
  }
  if (!roomId.length()) return fetchRooms();

  lastRefresh = millis();
  JsonDocument document;
  if (!getJson("/api/rooms/" + urlEncode(roomId), document)) {
    setRequestFailed(true);
    return false;
  }
  JsonObject payload = document.as<JsonObject>();
  if (payload.isNull()) {
    setRequestFailed(true);
    return false;
  }

  const bool changed = mergeRoomPayload(payload);
  setRequestFailed(false);
  if (changed) requestUiRender();
  return true;
}

void processToggleRequest() {
  if (!toggleRequestQueue) return;
  ToggleJob *job = nullptr;
  if (xQueueReceive(toggleRequestQueue, &job, 0) != pdTRUE || !job) return;

  const String path = "/api/devices/" + urlEncode(job->deviceId) + "/toggle";
  JsonDocument response;
  job->statusCode = postJsonRaw(path, "", &response, true);
  job->ok = job->statusCode >= 200 && job->statusCode < 300;
  if (job->ok) {
    JsonObject payload = response.as<JsonObject>();
    if (!payload.isNull()) mergeDevicePayload(payload);
  }
  xQueueSend(toggleResultQueue, &job, portMAX_DELAY);
}

void processToggleResult() {
  if (!toggleResultQueue) return;
  ToggleJob *job = nullptr;
  if (xQueueReceive(toggleResultQueue, &job, 0) != pdTRUE || !job) return;

  ModelGuard guard;
  DeviceState *device = findDeviceById(job->deviceId);
  if (!job->ok && device) device->isOn = job->previousOn;
  if (job->statusCode == 401) tokenRefreshAt = 0;
  busy = false;
  busyDeviceId = "";
  requestUiRender();
  delete job;
}

bool toggleCurrentDevice() {
  ModelGuard guard;
  DeviceState *device = currentDevice();
  if (!device || !device->id.length() || busy || device->unavailable || !device->toggleable) return false;

  busy = true;
  const String deviceId = device->id;
  const bool previousOn = device->isOn;
  busyDeviceId = deviceId;
  device->isOn = !device->isOn;
  requestUiRender();

  ToggleJob *job = new ToggleJob();
  if (!job) {
    device->isOn = previousOn;
    busy = false;
    busyDeviceId = "";
    requestUiRender();
    return false;
  }
  job->deviceId = deviceId;
  job->previousOn = previousOn;
  if (!toggleRequestQueue || xQueueSend(toggleRequestQueue, &job, 0) != pdTRUE) {
    delete job;
    device->isOn = previousOn;
    busy = false;
    busyDeviceId = "";
    requestUiRender();
    return false;
  }
  return true;
}

size_t wrappedIndex(size_t current, size_t count, int delta) {
  int64_t next = static_cast<int64_t>(current) + delta;
  next %= static_cast<int64_t>(count);
  if (next < 0) next += count;
  return static_cast<size_t>(next);
}

void moveSelection(int delta) {
  ModelGuard guard;
  if (delta == 0) return;
  if (!inDeviceMode) {
    if (!roomCount) return;
    activeRoom = wrappedIndex(activeRoom, roomCount, delta);
    activeDevice = 0;
  } else {
    RoomState *room = currentRoom();
    if (!room || !room->deviceCount) return;
    activeDevice = wrappedIndex(activeDevice, room->deviceCount, delta);
  }
  requestUiRender();
}

void activateSelection() {
  ModelGuard guard;
  if (!roomCount) {
    forceRefresh = true;
    return;
  }
  if (!inDeviceMode) {
    RoomState *room = currentRoom();
    if (!room || !room->deviceCount) return;
    inDeviceMode = true;
    activeDevice = 0;
    requestUiRender();
    return;
  }
  toggleCurrentDevice();
}

void goBack() {
  ModelGuard guard;
  if (!inDeviceMode) return;
  inDeviceMode = false;
  requestUiRender();
}

void onUiCenter() {
  activateSelection();
  renderPendingUiNow();
}

void onUiBack() {
  goBack();
  renderPendingUiNow();
}

void queueActivate() {
  portENTER_CRITICAL(&inputMux);
  pendingAction = PendingAction::Activate;
  portEXIT_CRITICAL(&inputMux);
}

void queueBack() {
  portENTER_CRITICAL(&inputMux);
  pendingAction = PendingAction::Back;
  portEXIT_CRITICAL(&inputMux);
}

void onKnobLeft(int count, void *) {
  (void)count;
  portENTER_CRITICAL(&inputMux);
  if (pendingRotation > -32) --pendingRotation;
  portEXIT_CRITICAL(&inputMux);
}

void onKnobRight(int count, void *) {
  (void)count;
  portENTER_CRITICAL(&inputMux);
  if (pendingRotation < 32) ++pendingRotation;
  portEXIT_CRITICAL(&inputMux);
}

void onButtonRelease(void *, void *) {
  portENTER_CRITICAL(&inputMux);
  const bool backQueued = buttonBackQueued;
  buttonBackQueued = false;
  portEXIT_CRITICAL(&inputMux);

  const int pressMs = button ? button->getTickTime() : 0;
  if (backQueued) return;
  if (pressMs >= BUTTON_BACK_HOLD_MS) {
    queueBack();
    return;
  }
  queueActivate();
}

void onButtonLongPress(void *, void *) {
  portENTER_CRITICAL(&inputMux);
  buttonBackQueued = true;
  portEXIT_CRITICAL(&inputMux);
  queueBack();
}

void processInput() {
  portENTER_CRITICAL(&inputMux);
  int rotation = pendingRotation;
  pendingRotation = 0;
  const PendingAction action = pendingAction;
  pendingAction = PendingAction::None;
  portEXIT_CRITICAL(&inputMux);

  if (rotation != 0) moveSelection(rotation);

  if (action == PendingAction::Activate) activateSelection();
  if (action == PendingAction::Back) goBack();
}

void beginWifiConnection() {
  lastWifiAttempt = millis();
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(VOKRR_WIFI_SSID, VOKRR_WIFI_PASSWORD);
  ESP_LOGI(TAG, "Connecting to WiFi");
  requestUiRender();
}

void updateClock() {
  const uint32_t now = millis();
  if (lastClockUpdate != 0 && now - lastClockUpdate < 60000) return;
  lastClockUpdate = now;

  char clockText[8] = "--:--";
  struct tm localTime;
  if (getLocalTime(&localTime, 10)) strftime(clockText, sizeof(clockText), "%H:%M", &localTime);
  knobUiSetClock(clockText);
}

void uiTimer(lv_timer_t *) {
  processToggleResult();
  processInput();
  updateClock();
  if (takeUiRenderRequest()) {
    ModelGuard guard;
    renderUi();
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  ESP_LOGI(TAG, "Starting Vokrr Smart Knob");

  modelMutex = xSemaphoreCreateRecursiveMutex();
  assert(modelMutex != nullptr);
  initializeLocalTopology();
  beginWifiConnection();
  const uint32_t wifiStartedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - wifiStartedAt < 20000) delay(50);
  if (WiFi.status() == WL_CONNECTED) {
    configTzTime(VOKRR_TIMEZONE, NTP_SERVER_PRIMARY, NTP_SERVER_SECONDARY);
    timeConfigured = true;
    connectionDiagnosticsPrinted = true;
    ESP_LOGI(TAG, "WiFi RSSI %d dBm | heap %u free, %u max block | PSRAM %u free", WiFi.RSSI(),
             ESP.getFreeHeap(), ESP.getMaxAllocHeap(), ESP.getFreePsram());
    if (login()) fetchRooms();
  }

  Board *board = new Board();
  board->init();
#if LVGL_PORT_AVOID_TEARING_MODE
  auto lcd = board->getLCD();
  lcd->configFrameBufferNumber(LVGL_PORT_DISP_BUFFER_NUM);
#if ESP_PANEL_DRIVERS_BUS_ENABLE_RGB && CONFIG_IDF_TARGET_ESP32S3
  auto lcdBus = lcd->getBus();
  if (lcdBus->getBasicAttributes().type == ESP_PANEL_BUS_TYPE_RGB) {
    auto rgbBus = static_cast<BusRGB *>(lcdBus);
    rgbBus->configRGB_FreqHz(10 * 1000 * 1000);
    rgbBus->configRGB_BounceBufferSize(lcd->getFrameWidth() * 20);
  }
#endif
#endif
  assert(board->begin());
  lvgl_port_init(board->getLCD(), board->getTouch());

  knob = new ESP_Knob(GPIO_NUM_KNOB_PIN_A, GPIO_NUM_KNOB_PIN_B);
  knob->begin();
  knob->attachLeftEventCallback(onKnobLeft);
  knob->attachRightEventCallback(onKnobRight);

  button = new Button(GPIO_BUTTON_PIN, false);
  button->setParam(BUTTON_LONG_PRESS_TIME_MS, reinterpret_cast<void *>(static_cast<intptr_t>(BUTTON_BACK_HOLD_MS)));
  button->attachPressUpEventCb(onButtonRelease, nullptr);
  button->attachLongPressStartEventCb(onButtonLongPress, nullptr);
  toggleRequestQueue = xQueueCreate(1, sizeof(ToggleJob *));
  assert(toggleRequestQueue != nullptr);
  toggleResultQueue = xQueueCreate(1, sizeof(ToggleJob *));
  assert(toggleResultQueue != nullptr);

  lvgl_port_lock(-1);
  knobUiCreate(onUiCenter, onUiBack);
  displayReady = true;
  renderUi();
  lv_timer_create(uiTimer, 5, nullptr);
  lvgl_port_unlock();
}

void loop() {
  const uint32_t now = millis();

  if (secureSessionLost) {
    ESP_LOGE(TAG, "Secure session lost; restarting network stack");
    delay(100);
    ESP.restart();
  }

  if (WiFi.status() != WL_CONNECTED) {
    if (now - lastWifiAttempt >= WIFI_RETRY_MS) beginWifiConnection();
    delay(10);
    return;
  }

  if (!timeConfigured) {
    // Numeric anycast addresses avoid an ESP-IDF 5.3 DNS race between SNTP and HTTPS.
    configTzTime(VOKRR_TIMEZONE, NTP_SERVER_PRIMARY, NTP_SERVER_SECONDARY);
    timeConfigured = true;
  }

  if (!connectionDiagnosticsPrinted) {
    connectionDiagnosticsPrinted = true;
    ESP_LOGI(TAG, "WiFi RSSI %d dBm | heap %u free, %u max block | PSRAM %u free", WiFi.RSSI(),
             ESP.getFreeHeap(), ESP.getMaxAllocHeap(), ESP.getFreePsram());
  }

  processToggleRequest();

  if (accessToken.length() && static_cast<int32_t>(now - tokenRefreshAt) >= 0) {
    renewSession();
  }

  const bool backendRetryDue = !accessToken.length() && now - lastBackendAttempt >= BACKEND_RETRY_MS;
  if (backendRetryDue) {
    lastBackendAttempt = now;
    if (login()) {
      fetchRooms();
    } else {
      if (setRequestFailed(true)) requestUiRender();
    }
  }

  const bool refreshDue = now - lastRefresh > REFRESH_MS_POLLING;
  if (accessToken.length() && (forceRefresh || refreshDue)) {
    forceRefresh = false;
    fetchSelectedRoom();
  }

  delay(10);
}
