#pragma once

#include <lvgl.h>

#include <cstddef>
#include <cstdint>

enum class KnobIcon {
  Home,
  Sofa,
  Kitchen,
  Gamepad,
  Bed,
  Drop,
  Dining,
  Bulb,
  Fan,
  Socket,
  Tube,
  Climate,
  Geyser,
  Tv,
  Speaker,
  Warning,
};

struct KnobUiModel {
  bool deviceMode = false;
  bool online = false;
  bool live = false;
  bool busy = false;
  bool on = false;
  bool unavailable = false;
  const char *name = "VOKRR";
  const char *status = "CONNECTING";
  const char *hint = "";
  KnobIcon icon = KnobIcon::Home;
  size_t selectedIndex = 0;
  size_t itemCount = 0;
  uint16_t activeMask = 0;
};

using KnobUiCallback = void (*)();

void knobUiCreate(KnobUiCallback centerCallback, KnobUiCallback backCallback);
void knobUiRender(const KnobUiModel &model);
void knobUiSetClock(const char *timeText);
