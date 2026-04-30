#include <Arduino.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <WebSocketsClient.h>
#include <WiFi.h>
#include <esp_display_panel.hpp>
#include <esp_log.h>
#include <lvgl.h>

#include "config_private.h"
#include "lvgl_v8_port.h"

#include <Button.h>
#include <ESP_Knob.h>

#define GPIO_NUM_KNOB_PIN_A 6
#define GPIO_NUM_KNOB_PIN_B 5
#define GPIO_BUTTON_PIN GPIO_NUM_0

using namespace esp_panel::board;
using namespace esp_panel::drivers;

namespace {

static const char *TAG = "VokrrKnob";

constexpr size_t MAX_ROOMS = 12;
constexpr size_t MAX_DEVICES_PER_ROOM = 16;
constexpr uint32_t REFRESH_MS_POLLING = 15000;
constexpr uint32_t REFRESH_MS_REALTIME_FALLBACK = 120000;
constexpr uint32_t ACTION_REFRESH_MS = 200;
constexpr uint16_t HTTP_TIMEOUT_MS = 8000;

struct DeviceState {
  String id;
  String name;
  String type;
  bool isOn = false;
  bool unavailable = false;
  int level = -1;
};

struct RoomState {
  String id;
  String name;
  DeviceState devices[MAX_DEVICES_PER_ROOM];
  size_t deviceCount = 0;
};

RoomState rooms[MAX_ROOMS];
size_t roomCount = 0;
size_t activeRoom = 0;
size_t activeDevice = 0;
bool inDeviceMode = false;
bool busy = false;
String accessToken;
uint32_t lastRefresh = 0;
uint32_t lastActionRefresh = 0;

WebSocketsClient realtimeWs;
volatile bool realtimeWsConnected = false;

lv_obj_t *screen = nullptr;
lv_obj_t *statusLabel = nullptr;
lv_obj_t *titleLabel = nullptr;
lv_obj_t *subtitleLabel = nullptr;
lv_obj_t *centerButton = nullptr;
lv_obj_t *iconLabel = nullptr;
lv_obj_t *nameLabel = nullptr;
lv_obj_t *stateLabel = nullptr;
lv_obj_t *hintLabel = nullptr;
lv_obj_t *backButton = nullptr;

lv_style_t styleScreen;
lv_style_t styleCenter;
lv_style_t styleCenterOn;
lv_style_t styleTiny;

ESP_Knob *knob = nullptr;
Button *button = nullptr;

String httpUrl(const String &path) {
  return String(VOKRR_API_BASE) + path;
}

struct ApiWsEndpoint {
  bool tls = false;
  String host;
  uint16_t port = 80;
};

ApiWsEndpoint parseApiWsEndpoint() {
  ApiWsEndpoint ep;
  String base = String(VOKRR_API_BASE);
  base.trim();
  if (base.startsWith("https://")) {
    ep.tls = true;
    ep.port = 443;
    base = base.substring(8);
  } else if (base.startsWith("http://")) {
    base = base.substring(7);
  }
  int pathSlash = base.indexOf('/');
  if (pathSlash >= 0) {
    base = base.substring(0, pathSlash);
  }
  int colon = base.indexOf(':');
  if (colon >= 0) {
    ep.host = base.substring(0, colon);
    ep.port = static_cast<uint16_t>(base.substring(colon + 1).toInt());
    if (ep.port == 0) ep.port = ep.tls ? 443 : 80;
  } else {
    ep.host = base;
  }
  return ep;
}

void applyDeviceFromJson(DeviceState &device, JsonObject deviceJson) {
  device.id = deviceJson["id"] | "";
  device.name = deviceJson["name"] | "Device";
  device.type = deviceJson["type"] | "";
  JsonObject state = deviceJson["state"];
  const char *rawState = state["state"] | "";
  device.isOn = state["is_on"] | false;
  device.unavailable = strcmp(rawState, "unavailable") == 0 || strcmp(rawState, "unknown") == 0;
  if (!state["brightness"].isNull()) {
    device.level = state["brightness"].as<int>();
  } else if (!state["percentage"].isNull()) {
    device.level = state["percentage"].as<int>();
  } else {
    device.level = -1;
  }
}

bool mergeDevicePayload(JsonObject payload) {
  String id = payload["id"] | "";
  if (!id.length()) return false;
  for (size_t r = 0; r < roomCount; r++) {
    RoomState &room = rooms[r];
    for (size_t d = 0; d < room.deviceCount; d++) {
      if (room.devices[d].id == id) {
        applyDeviceFromJson(room.devices[d], payload);
        return true;
      }
    }
  }
  return false;
}

void parseRooms(JsonArray root);
void drawUi();

void realtimeWsDisconnect();
void realtimeWsConnect();
void realtimeWsEvent(WStype_t type, uint8_t *payload, size_t length);

void realtimeWsEvent(WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      realtimeWsConnected = false;
      ESP_LOGW(TAG, "Realtime WS disconnected");
      break;
    case WStype_CONNECTED:
      realtimeWsConnected = true;
      ESP_LOGI(TAG, "Realtime WS connected");
      break;
    case WStype_TEXT:
      if (payload == nullptr || length == 0) break;
      {
        const size_t docCapacity =
            length > 12000 ? static_cast<size_t>(57344) : static_cast<size_t>(6144);
        DynamicJsonDocument doc(docCapacity);
        DeserializationError err = deserializeJson(doc, payload, length);
        if (err) {
          ESP_LOGW(TAG, "WS JSON parse failed: %s", err.c_str());
          break;
        }
        const char *ev = doc["event"] | "";
        bool redraw = false;
        if (strcmp(ev, "snapshot") == 0) {
          JsonArray roomsArr = doc["payload"]["rooms"].as<JsonArray>();
          if (!roomsArr.isNull()) {
            parseRooms(roomsArr);
            lastRefresh = millis();
            redraw = true;
          }
        } else if (strcmp(ev, "device.updated") == 0) {
          JsonObject p = doc["payload"].as<JsonObject>();
          if (!p.isNull()) {
            mergeDevicePayload(p);
            lastRefresh = millis();
            redraw = true;
          }
        }
        if (redraw) {
          lvgl_port_lock(-1);
          drawUi();
          lvgl_port_unlock();
        }
      }
      break;
    default:
      break;
  }
}

void realtimeWsDisconnect() {
  realtimeWs.disconnect();
  realtimeWsConnected = false;
}

void realtimeWsConnect() {
  if (!accessToken.length() || WiFi.status() != WL_CONNECTED) return;

  realtimeWsDisconnect();

  realtimeWs.onEvent(realtimeWsEvent);
  realtimeWs.setReconnectInterval(4000);

  ApiWsEndpoint ep = parseApiWsEndpoint();
  String path = String("/ws?token=") + accessToken;

  if (ep.tls) {
#if defined(HAS_SSL) && defined(ESP32)
    realtimeWs.beginSSL(ep.host.c_str(), ep.port, path.c_str(), nullptr, "arduino");
#else
    ESP_LOGE(TAG, "SSL requested but HAS_SSL not available for WebSockets");
#endif
  } else {
    realtimeWs.begin(ep.host.c_str(), ep.port, path.c_str(), "arduino");
  }
}

uint32_t refreshIntervalMs() {
  return realtimeWsConnected ? REFRESH_MS_REALTIME_FALLBACK : REFRESH_MS_POLLING;
}

void setStatus(const char *text) {
  if (!statusLabel) return;
  lv_label_set_text(statusLabel, text);
}

String trimmedText(const String &text, size_t maxLen) {
  if (text.length() <= maxLen) return text;
  return text.substring(0, maxLen - 1) + ".";
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

String deviceIcon(const String &type) {
  if (type == "light") return LV_SYMBOL_EYE_OPEN;
  if (type == "switch") return LV_SYMBOL_POWER;
  if (type == "fan") return LV_SYMBOL_LOOP;
  if (type == "climate") return LV_SYMBOL_SETTINGS;
  if (type == "speaker") return LV_SYMBOL_VOLUME_MAX;
  if (type == "tv") return LV_SYMBOL_VIDEO;
  return LV_SYMBOL_HOME;
}

String deviceStatus(const DeviceState &device) {
  if (device.unavailable) return "Unavailable";
  String status = device.isOn ? "On" : "Off";
  if (device.level >= 0) status += "  " + String(device.level) + "%";
  return status;
}

void drawUi();

bool postJson(const String &path, const String &body, DynamicJsonDocument *out = nullptr) {
  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);
  http.begin(httpUrl(path));
  http.addHeader("Content-Type", "application/json");
  if (accessToken.length()) {
    http.addHeader("Authorization", "Bearer " + accessToken);
  }

  int code = http.POST(body);
  if (code < 200 || code >= 300) {
    Serial.printf("POST %s failed: %d\n", path.c_str(), code);
    http.end();
    return false;
  }

  if (out) {
    DeserializationError err = deserializeJson(*out, http.getStream());
    if (err) {
      Serial.printf("JSON parse failed: %s\n", err.c_str());
      http.end();
      return false;
    }
  }
  http.end();
  return true;
}

bool getJson(const String &path, DynamicJsonDocument &out) {
  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);
  http.begin(httpUrl(path));
  if (accessToken.length()) {
    http.addHeader("Authorization", "Bearer " + accessToken);
  }

  int code = http.GET();
  if (code < 200 || code >= 300) {
    Serial.printf("GET %s failed: %d\n", path.c_str(), code);
    http.end();
    return false;
  }

  DeserializationError err = deserializeJson(out, http.getStream());
  http.end();
  if (err) {
    Serial.printf("JSON parse failed: %s\n", err.c_str());
    return false;
  }
  return true;
}

bool login() {
  DynamicJsonDocument doc(4096);
  ESP_LOGI(TAG, "Logging into Vokrr");
  String body = String("{\"username\":\"") + VOKRR_USERNAME + "\",\"password\":\"" + VOKRR_PASSWORD + "\"}";
  if (!postJson("/api/auth/login", body, &doc)) {
    ESP_LOGE(TAG, "Vokrr login request failed");
    return false;
  }
  accessToken = doc["access_token"].as<String>();
  ESP_LOGI(TAG, "Vokrr login %s", accessToken.length() > 0 ? "succeeded" : "returned no token");
  return accessToken.length() > 0;
}

void parseRooms(JsonArray root) {
  roomCount = 0;
  for (JsonObject roomJson : root) {
    if (roomCount >= MAX_ROOMS) break;
    RoomState &room = rooms[roomCount++];
    room.id = roomJson["id"] | "";
    room.name = roomJson["name"] | "Room";
    room.deviceCount = 0;

    for (JsonObject deviceJson : roomJson["devices"].as<JsonArray>()) {
      if (room.deviceCount >= MAX_DEVICES_PER_ROOM) break;
      DeviceState &device = room.devices[room.deviceCount++];
      applyDeviceFromJson(device, deviceJson);
    }
  }
  if (activeRoom >= roomCount) activeRoom = roomCount ? roomCount - 1 : 0;
  RoomState *room = currentRoom();
  if (!room || activeDevice >= room->deviceCount) activeDevice = 0;
}

bool fetchRooms() {
  DynamicJsonDocument doc(32768);
  ESP_LOGI(TAG, "Fetching Vokrr rooms");
  if (!getJson("/api/rooms", doc)) {
    ESP_LOGE(TAG, "Vokrr room sync failed");
    return false;
  }
  parseRooms(doc.as<JsonArray>());
  ESP_LOGI(TAG, "Vokrr room sync succeeded: %u rooms", static_cast<unsigned>(roomCount));
  lastRefresh = millis();
  return true;
}

bool toggleCurrentDevice() {
  String deviceId;
  bool prevOn = false;

  lvgl_port_lock(-1);
  DeviceState *device = currentDevice();
  if (!device || busy) {
    lvgl_port_unlock();
    return false;
  }
  busy = true;
  prevOn = device->isOn;
  deviceId = device->id;
  device->isOn = !device->isOn;
  setStatus("Updating");
  drawUi();
  lvgl_port_unlock();

  bool ok = postJson("/api/devices/" + deviceId + "/toggle", "");

  lvgl_port_lock(-1);
  busy = false;
  device = currentDevice();
  if (!ok) {
    if (device && device->id == deviceId) {
      device->isOn = prevOn;
    }
    setStatus("Action failed");
  } else if (WiFi.status() == WL_CONNECTED) {
    setStatus(realtimeWsConnected ? "Vokrr live" : "Vokrr online");
  }
  lastActionRefresh = millis();
  drawUi();
  lvgl_port_unlock();

  return ok;
}

void moveSelection(int direction) {
  if (busy) return;
  if (!inDeviceMode) {
    if (roomCount == 0) return;
    activeRoom = (activeRoom + roomCount + direction) % roomCount;
    activeDevice = 0;
  } else {
    RoomState *room = currentRoom();
    if (!room || room->deviceCount == 0) return;
    activeDevice = (activeDevice + room->deviceCount + direction) % room->deviceCount;
  }
  drawUi();
}

void activateSelection() {
  if (!inDeviceMode) {
    if (roomCount == 0) return;
    inDeviceMode = true;
    activeDevice = 0;
    drawUi();
    return;
  }
  toggleCurrentDevice();
}

void goBack() {
  if (!inDeviceMode) return;
  inDeviceMode = false;
  drawUi();
}

void screenClickEvent(lv_event_t *event) {
  if (lv_event_get_code(event) == LV_EVENT_CLICKED) activateSelection();
}

void backClickEvent(lv_event_t *event) {
  if (lv_event_get_code(event) == LV_EVENT_CLICKED) goBack();
}

void drawUi() {
  if (!screen) return;

  lv_obj_clear_state(centerButton, LV_STATE_CHECKED);
  lv_obj_remove_style(centerButton, &styleCenterOn, 0);
  lv_obj_add_style(centerButton, &styleCenter, 0);
  lv_obj_add_flag(backButton, LV_OBJ_FLAG_HIDDEN);

  if (WiFi.status() != WL_CONNECTED) {
    setStatus("WiFi offline");
  } else if (realtimeWsConnected) {
    setStatus("Vokrr live");
  } else {
    setStatus("Vokrr online");
  }

  if (roomCount == 0) {
    lv_label_set_text(titleLabel, "Vokrr");
    lv_label_set_text(subtitleLabel, "No rooms");
    lv_label_set_text(iconLabel, LV_SYMBOL_WARNING);
    lv_label_set_text(nameLabel, "No rooms found");
    lv_label_set_text(stateLabel, "Check backend");
    lv_label_set_text(hintLabel, "Press to retry");
    return;
  }

  RoomState *room = currentRoom();
  if (!inDeviceMode) {
    lv_label_set_text(titleLabel, "Rooms");
    lv_label_set_text(subtitleLabel, String(String(activeRoom + 1) + "/" + String(roomCount)).c_str());
    lv_label_set_text(iconLabel, LV_SYMBOL_HOME);
    lv_label_set_text(nameLabel, trimmedText(room->name, 20).c_str());
    lv_label_set_text(stateLabel, String(String(room->deviceCount) + " devices").c_str());

    lv_label_set_text(hintLabel, "Rotate rooms  |  Press select");
    return;
  }

  lv_obj_clear_flag(backButton, LV_OBJ_FLAG_HIDDEN);
  lv_label_set_text(titleLabel, room->name.c_str());
  lv_label_set_text(subtitleLabel, room->deviceCount ? String(String(activeDevice + 1) + "/" + String(room->deviceCount)).c_str() : "0/0");

  DeviceState *device = currentDevice();
  if (!device) {
    lv_label_set_text(iconLabel, LV_SYMBOL_WARNING);
    lv_label_set_text(nameLabel, "No devices");
    lv_label_set_text(stateLabel, "Rotate back");
    lv_label_set_text(hintLabel, "Long press for rooms");
    return;
  }

  if (device->isOn && !device->unavailable) {
    lv_obj_remove_style(centerButton, &styleCenter, 0);
    lv_obj_add_style(centerButton, &styleCenterOn, 0);
  }
  lv_label_set_text(iconLabel, deviceIcon(device->type).c_str());
  lv_label_set_text(nameLabel, trimmedText(device->name, 18).c_str());
  lv_label_set_text(stateLabel, deviceStatus(*device).c_str());

  lv_label_set_text(hintLabel, "Rotate device  |  Press toggle");
}

void createUi() {
  lv_style_init(&styleScreen);
  lv_style_set_bg_color(&styleScreen, lv_color_hex(0x08090B));
  lv_style_set_text_color(&styleScreen, lv_color_hex(0xFFFFFF));
  lv_style_set_border_width(&styleScreen, 0);

  lv_style_init(&styleCenter);
  lv_style_set_radius(&styleCenter, 110);
  lv_style_set_bg_color(&styleCenter, lv_color_hex(0x181B22));
  lv_style_set_bg_opa(&styleCenter, LV_OPA_COVER);
  lv_style_set_border_width(&styleCenter, 2);
  lv_style_set_border_color(&styleCenter, lv_color_hex(0x343946));
  lv_style_set_shadow_width(&styleCenter, 34);
  lv_style_set_shadow_opa(&styleCenter, LV_OPA_40);
  lv_style_set_pad_all(&styleCenter, 12);

  lv_style_init(&styleCenterOn);
  lv_style_set_radius(&styleCenterOn, 110);
  lv_style_set_bg_color(&styleCenterOn, lv_color_hex(0xF59E0B));
  lv_style_set_bg_opa(&styleCenterOn, LV_OPA_COVER);
  lv_style_set_text_color(&styleCenterOn, lv_color_hex(0x111111));
  lv_style_set_border_width(&styleCenterOn, 0);
  lv_style_set_shadow_width(&styleCenterOn, 42);
  lv_style_set_shadow_color(&styleCenterOn, lv_color_hex(0xF59E0B));
  lv_style_set_shadow_opa(&styleCenterOn, LV_OPA_30);
  lv_style_set_pad_all(&styleCenterOn, 12);

  lv_style_init(&styleTiny);
  lv_style_set_text_color(&styleTiny, lv_color_hex(0x9CA3AF));
  lv_style_set_text_font(&styleTiny, &lv_font_montserrat_12);

  screen = lv_obj_create(nullptr);
  lv_obj_add_style(screen, &styleScreen, 0);
  lv_scr_load(screen);

  statusLabel = lv_label_create(screen);
  lv_obj_add_style(statusLabel, &styleTiny, 0);
  lv_label_set_text(statusLabel, "Starting");
  lv_obj_align(statusLabel, LV_ALIGN_TOP_MID, 0, 22);

  titleLabel = lv_label_create(screen);
  lv_obj_set_style_text_font(titleLabel, &lv_font_montserrat_20, 0);
  lv_obj_align(titleLabel, LV_ALIGN_TOP_MID, 0, 54);

  subtitleLabel = lv_label_create(screen);
  lv_obj_add_style(subtitleLabel, &styleTiny, 0);
  lv_obj_align(subtitleLabel, LV_ALIGN_TOP_MID, 0, 82);

  centerButton = lv_btn_create(screen);
  lv_obj_set_size(centerButton, 250, 250);
  lv_obj_add_style(centerButton, &styleCenter, 0);
  lv_obj_align(centerButton, LV_ALIGN_CENTER, 0, 10);
  lv_obj_add_event_cb(centerButton, screenClickEvent, LV_EVENT_CLICKED, nullptr);

  backButton = lv_btn_create(screen);
  lv_obj_set_size(backButton, 46, 46);
  lv_obj_set_style_radius(backButton, 23, 0);
  lv_obj_set_style_bg_color(backButton, lv_color_hex(0x20242C), 0);
  lv_obj_set_style_border_width(backButton, 1, 0);
  lv_obj_set_style_border_color(backButton, lv_color_hex(0x353B47), 0);
  lv_obj_align_to(backButton, centerButton, LV_ALIGN_OUT_LEFT_MID, -14, 0);
  lv_obj_add_event_cb(backButton, backClickEvent, LV_EVENT_CLICKED, nullptr);
  lv_obj_t *backIcon = lv_label_create(backButton);
  lv_label_set_text(backIcon, LV_SYMBOL_LEFT);
  lv_obj_center(backIcon);
  lv_obj_add_flag(backButton, LV_OBJ_FLAG_HIDDEN);

  iconLabel = lv_label_create(centerButton);
  lv_obj_set_style_text_font(iconLabel, &lv_font_montserrat_48, 0);
  lv_label_set_text(iconLabel, LV_SYMBOL_HOME);
  lv_obj_align(iconLabel, LV_ALIGN_TOP_MID, 0, 34);

  nameLabel = lv_label_create(centerButton);
  lv_obj_set_width(nameLabel, 210);
  lv_obj_set_style_text_align(nameLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_font(nameLabel, &lv_font_montserrat_28, 0);
  lv_label_set_long_mode(nameLabel, LV_LABEL_LONG_WRAP);
  lv_obj_align(nameLabel, LV_ALIGN_CENTER, 0, 26);

  stateLabel = lv_label_create(centerButton);
  lv_obj_set_width(stateLabel, 210);
  lv_obj_set_style_text_align(stateLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_font(stateLabel, &lv_font_montserrat_16, 0);
  lv_obj_align(stateLabel, LV_ALIGN_BOTTOM_MID, 0, -34);

  hintLabel = lv_label_create(screen);
  lv_obj_add_style(hintLabel, &styleTiny, 0);
  lv_obj_align(hintLabel, LV_ALIGN_BOTTOM_MID, 0, -34);

  drawUi();
}

void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(VOKRR_WIFI_SSID, VOKRR_WIFI_PASSWORD);
  setStatus("Connecting WiFi");
  ESP_LOGI(TAG, "Connecting to WiFi");
  Serial.printf("Connecting to WiFi SSID %s\n", VOKRR_WIFI_SSID);
  for (int i = 0; i < 60 && WiFi.status() != WL_CONNECTED; i++) {
    delay(250);
  }
  if (WiFi.status() == WL_CONNECTED) {
    ESP_LOGI(TAG, "WiFi connected: %s", WiFi.localIP().toString().c_str());
    Serial.printf("WiFi connected: %s\n", WiFi.localIP().toString().c_str());
    setStatus("WiFi connected");
    realtimeWsConnect();
  } else {
    ESP_LOGE(TAG, "WiFi connection failed");
    Serial.println("WiFi connection failed");
    setStatus("WiFi failed");
  }
}

void onKnobLeftEventCallback(int count, void *usr_data) {
  (void)count;
  (void)usr_data;
  lvgl_port_lock(-1);
  moveSelection(-1);
  lvgl_port_unlock();
}

void onKnobRightEventCallback(int count, void *usr_data) {
  (void)count;
  (void)usr_data;
  lvgl_port_lock(-1);
  moveSelection(1);
  lvgl_port_unlock();
}

void singleClickCallback(void *button_handle, void *usr_data) {
  (void)button_handle;
  (void)usr_data;
  lvgl_port_lock(-1);
  if (!inDeviceMode) {
    activateSelection();
    lvgl_port_unlock();
    return;
  }
  lvgl_port_unlock();
  toggleCurrentDevice();
}

void longPressCallback(void *button_handle, void *usr_data) {
  (void)button_handle;
  (void)usr_data;
  lvgl_port_lock(-1);
  goBack();
  lvgl_port_unlock();
}

}  // namespace

void setup() {
  Serial.begin(115200);
  ESP_LOGI(TAG, "Starting Vokrr Smart Knob");
  Serial.println("Starting Vokrr Smart Knob");

  Board *board = new Board();
  board->init();
#if LVGL_PORT_AVOID_TEARING_MODE
  auto lcd = board->getLCD();
  lcd->configFrameBufferNumber(LVGL_PORT_DISP_BUFFER_NUM);
#if ESP_PANEL_DRIVERS_BUS_ENABLE_RGB && CONFIG_IDF_TARGET_ESP32S3
  auto lcd_bus = lcd->getBus();
  if (lcd_bus->getBasicAttributes().type == ESP_PANEL_BUS_TYPE_RGB) {
    static_cast<BusRGB *>(lcd_bus)->configRGB_BounceBufferSize(lcd->getFrameWidth() * 10);
  }
#endif
#endif
  assert(board->begin());

  lvgl_port_init(board->getLCD(), board->getTouch());

  knob = new ESP_Knob(GPIO_NUM_KNOB_PIN_A, GPIO_NUM_KNOB_PIN_B);
  knob->begin();
  knob->attachLeftEventCallback(onKnobLeftEventCallback);
  knob->attachRightEventCallback(onKnobRightEventCallback);

  button = new Button(GPIO_BUTTON_PIN, false);
  button->attachSingleClickEventCb(singleClickCallback, nullptr);
  button->attachLongPressStartEventCb(longPressCallback, nullptr);

  lvgl_port_lock(-1);
  createUi();
  lvgl_port_unlock();

  connectWifi();
  if (WiFi.status() == WL_CONNECTED && login() && fetchRooms()) {
    ESP_LOGI(TAG, "Vokrr Smart Knob is online");
    realtimeWsConnect();
    lvgl_port_lock(-1);
    drawUi();
    lvgl_port_unlock();
  } else {
    ESP_LOGE(TAG, "Vokrr Smart Knob backend startup failed");
    lvgl_port_lock(-1);
    setStatus("Backend offline");
    drawUi();
    lvgl_port_unlock();
  }
}

void loop() {
  const uint32_t now = millis();

  if (WiFi.status() != WL_CONNECTED) {
    realtimeWsDisconnect();
    connectWifi();
  } else {
    realtimeWs.loop();
    if (accessToken.length() && !realtimeWs.isConnected()) {
      static uint32_t lastWsRetry = 0;
      if (now - lastWsRetry > 4000) {
        lastWsRetry = now;
        realtimeWsConnect();
      }
    }
  }

  bool refreshDue =
      static_cast<int32_t>(now - lastRefresh) > static_cast<int32_t>(refreshIntervalMs());
      static_cast<int32_t>(now - lastRefresh) > static_cast<int32_t>(refreshIntervalMs());
  bool actionRefreshDue = lastActionRefresh && now - lastActionRefresh > ACTION_REFRESH_MS;
  if (WiFi.status() == WL_CONNECTED && (refreshDue || actionRefreshDue)) {
    if (!accessToken.length() && !login()) {
      ESP_LOGE(TAG, "Login failed during refresh");
      lvgl_port_lock(-1);
      setStatus("Login failed");
      lvgl_port_unlock();
      delay(1000);
      return;
    }
    if (fetchRooms()) {
      lastActionRefresh = 0;
      lvgl_port_lock(-1);
      drawUi();
      lvgl_port_unlock();
    } else {
      accessToken = "";
      realtimeWsDisconnect();
      ESP_LOGE(TAG, "Sync failed during refresh; token cleared");
      lvgl_port_lock(-1);
      setStatus("Sync failed");
      lvgl_port_unlock();
    }
  }

  delay(10);
}
