#include "knob_ui.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

namespace {

constexpr int SCREEN_SIZE = 480;
constexpr int SCREEN_CENTER = SCREEN_SIZE / 2;
constexpr int DOT_RADIUS = 206;
constexpr size_t MAX_DOTS = 16;
constexpr int ICON_CANVAS_SIZE = 72;
constexpr int INNER_RING_RADIUS = 214;
constexpr size_t INNER_RING_DASH_COUNT = 32;
constexpr uint32_t INNER_RING_TICK_MS = 180;
constexpr size_t INNER_RING_TRAIL_LENGTH = 3;
constexpr bool INNER_RING_CONTINUOUS_ANIMATION = false;

constexpr uint32_t COLOR_BACKGROUND = 0x060807;
constexpr uint32_t COLOR_INNER = 0x08100D;
constexpr uint32_t COLOR_GREEN = 0x2EC79A;
constexpr uint32_t COLOR_GOLD = 0xD7B985;
constexpr uint32_t COLOR_TEXT = 0xF2F1EC;
constexpr uint32_t COLOR_MUTED = 0x7C827D;
constexpr uint32_t COLOR_DIM = 0x343A36;
constexpr uint32_t COLOR_ERROR = 0xD77C68;

lv_obj_t *screen = nullptr;
lv_obj_t *clockLabel = nullptr;
lv_obj_t *iconRing = nullptr;
lv_obj_t *iconCanvas = nullptr;
lv_obj_t *nameLabel = nullptr;
lv_obj_t *statusLabel = nullptr;
lv_obj_t *hintLabel = nullptr;
lv_obj_t *indexLabel = nullptr;
lv_obj_t *backButton = nullptr;
lv_obj_t *dots[MAX_DOTS] = {};
lv_obj_t *innerRingLayer = nullptr;
lv_point_t innerRingSegments[INNER_RING_DASH_COUNT][2] = {};
size_t innerRingPhase = 0;

KnobUiCallback onCenter = nullptr;
KnobUiCallback onBack = nullptr;
bool hasRendered = false;
size_t renderedIndex = static_cast<size_t>(-1);
size_t renderedItemCount = static_cast<size_t>(-1);
uint16_t renderedActiveMask = UINT16_MAX;
bool renderedDeviceMode = false;
bool renderedOnline = false;
bool renderedLive = false;
bool renderedOn = false;
bool renderedUnavailable = false;
bool renderedBusy = false;
KnobIcon renderedIcon = KnobIcon::Warning;
uint32_t renderedAccent = UINT32_MAX;

LV_ATTRIBUTE_MEM_ALIGN static uint8_t
    iconCanvasBuffer[LV_CANVAS_BUF_SIZE_TRUE_COLOR_CHROMA_KEYED(ICON_CANVAS_SIZE, ICON_CANVAS_SIZE)];

void centerEvent(lv_event_t *event) {
  if (lv_event_get_code(event) == LV_EVENT_CLICKED && onCenter) onCenter();
}

void backEvent(lv_event_t *event) {
  if (lv_event_get_code(event) == LV_EVENT_CLICKED && onBack) onBack();
}

void drawLine(const lv_point_t *points, uint32_t count, lv_color_t color, int width = 3) {
  lv_draw_line_dsc_t descriptor;
  lv_draw_line_dsc_init(&descriptor);
  descriptor.color = color;
  descriptor.width = width;
  descriptor.opa = LV_OPA_COVER;
  descriptor.round_start = true;
  descriptor.round_end = true;
  lv_canvas_draw_line(iconCanvas, points, count, &descriptor);
}

void drawRect(int x, int y, int width, int height, int radius, lv_color_t color, bool fill = false) {
  lv_draw_rect_dsc_t descriptor;
  lv_draw_rect_dsc_init(&descriptor);
  descriptor.radius = radius;
  descriptor.bg_color = color;
  descriptor.bg_opa = fill ? LV_OPA_COVER : LV_OPA_TRANSP;
  descriptor.border_color = color;
  descriptor.border_width = fill ? 0 : 3;
  descriptor.border_opa = LV_OPA_COVER;
  lv_canvas_draw_rect(iconCanvas, x, y, width, height, &descriptor);
}

void drawArc(int x, int y, int radius, int start, int end, lv_color_t color, int width = 3) {
  lv_draw_arc_dsc_t descriptor;
  lv_draw_arc_dsc_init(&descriptor);
  descriptor.color = color;
  descriptor.width = width;
  descriptor.opa = LV_OPA_COVER;
  descriptor.rounded = true;
  lv_canvas_draw_arc(iconCanvas, x, y, radius, start, end, &descriptor);
}

void drawHome(lv_color_t color) {
  const lv_point_t roof[] = {{12, 34}, {36, 13}, {60, 34}};
  const lv_point_t walls[] = {{18, 31}, {18, 59}, {54, 59}, {54, 31}};
  drawLine(roof, 3, color);
  drawLine(walls, 4, color);
  drawRect(31, 41, 10, 18, 1, color);
}

void drawSofa(lv_color_t color) {
  drawRect(14, 30, 44, 24, 7, color);
  drawRect(9, 39, 10, 20, 5, color);
  drawRect(53, 39, 10, 20, 5, color);
  const lv_point_t seat[] = {{15, 51}, {57, 51}};
  const lv_point_t legs[] = {{18, 59}, {18, 63}, {54, 59}, {54, 63}};
  drawLine(seat, 2, color);
  drawLine(legs, 2, color, 2);
  drawLine(legs + 2, 2, color, 2);
}

void drawKitchen(lv_color_t color) {
  drawArc(36, 34, 22, 0, 180, color);
  const lv_point_t rim[] = {{13, 35}, {59, 35}};
  const lv_point_t base[] = {{27, 57}, {45, 57}};
  const lv_point_t steam1[] = {{26, 29}, {23, 23}, {27, 17}};
  const lv_point_t steam2[] = {{38, 28}, {35, 21}, {39, 14}};
  const lv_point_t steam3[] = {{49, 29}, {46, 23}, {49, 18}};
  drawLine(rim, 2, color);
  drawLine(base, 2, color);
  drawLine(steam1, 3, color, 2);
  drawLine(steam2, 3, color, 2);
  drawLine(steam3, 3, color, 2);
}

void drawGamepad(lv_color_t color) {
  drawRect(9, 24, 54, 34, 13, color);
  const lv_point_t horizontal[] = {{20, 39}, {32, 39}};
  const lv_point_t vertical[] = {{26, 33}, {26, 45}};
  drawLine(horizontal, 2, color);
  drawLine(vertical, 2, color);
  drawArc(47, 36, 2, 0, 360, color, 4);
  drawArc(54, 44, 2, 0, 360, color, 4);
}

void drawBed(lv_color_t color) {
  const lv_point_t frame[] = {{11, 18}, {11, 58}, {61, 58}, {61, 37}, {11, 37}};
  const lv_point_t feet[] = {{15, 58}, {15, 64}, {57, 58}, {57, 64}};
  drawLine(frame, 5, color);
  drawLine(feet, 2, color, 2);
  drawLine(feet + 2, 2, color, 2);
  drawRect(17, 27, 16, 10, 4, color);
}

void drawDrop(lv_color_t color) {
  const lv_point_t drop[] = {{36, 10}, {18, 38}, {18, 48}, {23, 58}, {36, 63}, {49, 58}, {54, 48}, {54, 38}, {36, 10}};
  drawLine(drop, 9, color);
  drawArc(36, 45, 10, 5, 85, color, 2);
}

void drawDining(lv_color_t color) {
  drawArc(36, 36, 18, 0, 360, color);
  drawArc(36, 36, 11, 0, 360, color, 2);
  const lv_point_t fork[] = {{10, 14}, {10, 60}, {7, 14}, {7, 27}, {13, 27}, {13, 14}};
  const lv_point_t knife[] = {{62, 14}, {58, 36}, {62, 36}, {62, 60}};
  drawLine(fork, 2, color, 2);
  drawLine(fork + 2, 4, color, 2);
  drawLine(knife, 4, color, 2);
}

void drawBulb(lv_color_t color) {
  drawArc(36, 29, 17, 105, 435, color);
  const lv_point_t neckLeft[] = {{24, 41}, {29, 49}, {29, 54}};
  const lv_point_t neckRight[] = {{48, 41}, {43, 49}, {43, 54}};
  const lv_point_t base[] = {{29, 54}, {43, 54}, {41, 61}, {31, 61}};
  drawLine(neckLeft, 3, color);
  drawLine(neckRight, 3, color);
  drawLine(base, 4, color);
}

void drawFan(lv_color_t color) {
  drawArc(36, 36, 5, 0, 360, color, 4);
  const lv_point_t blade1[] = {{36, 30}, {31, 12}, {42, 10}, {43, 23}, {36, 30}};
  const lv_point_t blade2[] = {{42, 39}, {61, 40}, {58, 51}, {46, 49}, {42, 39}};
  const lv_point_t blade3[] = {{32, 41}, {22, 58}, {14, 50}, {21, 40}, {32, 41}};
  drawLine(blade1, 5, color);
  drawLine(blade2, 5, color);
  drawLine(blade3, 5, color);
}

void drawSocket(lv_color_t color) {
  drawRect(17, 12, 38, 49, 9, color);
  drawRect(26, 27, 5, 12, 2, color, true);
  drawRect(41, 27, 5, 12, 2, color, true);
  drawArc(36, 48, 3, 0, 360, color, 3);
}

void drawTube(lv_color_t color) {
  drawRect(9, 27, 54, 18, 9, color);
  const lv_point_t left[] = {{17, 30}, {17, 42}};
  const lv_point_t right[] = {{55, 30}, {55, 42}};
  drawLine(left, 2, color, 2);
  drawLine(right, 2, color, 2);
}

void drawClimate(lv_color_t color) {
  const lv_point_t vertical[] = {{36, 9}, {36, 63}};
  const lv_point_t diagonal1[] = {{13, 22}, {59, 50}};
  const lv_point_t diagonal2[] = {{13, 50}, {59, 22}};
  drawLine(vertical, 2, color);
  drawLine(diagonal1, 2, color);
  drawLine(diagonal2, 2, color);
  drawArc(36, 36, 5, 0, 360, color, 3);
}

void drawGeyser(lv_color_t color) {
  drawRect(17, 9, 38, 54, 18, color);
  const lv_point_t drop[] = {{36, 23}, {28, 37}, {30, 45}, {36, 49}, {42, 45}, {44, 37}, {36, 23}};
  drawLine(drop, 7, color, 2);
  const lv_point_t pipe[] = {{36, 63}, {36, 68}};
  drawLine(pipe, 2, color, 2);
}

void drawTv(lv_color_t color) {
  drawRect(10, 15, 52, 38, 5, color);
  const lv_point_t stand[] = {{29, 53}, {27, 61}, {45, 61}, {43, 53}};
  drawLine(stand, 4, color);
}

void drawSpeaker(lv_color_t color) {
  const lv_point_t body[] = {{12, 31}, {25, 31}, {40, 17}, {40, 55}, {25, 41}, {12, 41}, {12, 31}};
  drawLine(body, 7, color);
  drawArc(42, 36, 13, 295, 65, color);
  drawArc(42, 36, 22, 300, 60, color, 2);
}

void drawWarning(lv_color_t color) {
  const lv_point_t triangle[] = {{36, 10}, {63, 60}, {9, 60}, {36, 10}};
  const lv_point_t mark[] = {{36, 27}, {36, 44}};
  drawLine(triangle, 4, color);
  drawLine(mark, 2, color, 4);
  drawArc(36, 52, 2, 0, 360, color, 3);
}

void drawIcon(KnobIcon icon, lv_color_t color) {
  lv_canvas_fill_bg(iconCanvas, LV_COLOR_CHROMA_KEY, LV_OPA_COVER);
  switch (icon) {
    case KnobIcon::Sofa: drawSofa(color); break;
    case KnobIcon::Kitchen: drawKitchen(color); break;
    case KnobIcon::Gamepad: drawGamepad(color); break;
    case KnobIcon::Bed: drawBed(color); break;
    case KnobIcon::Drop: drawDrop(color); break;
    case KnobIcon::Dining: drawDining(color); break;
    case KnobIcon::Bulb: drawBulb(color); break;
    case KnobIcon::Fan: drawFan(color); break;
    case KnobIcon::Socket: drawSocket(color); break;
    case KnobIcon::Tube: drawTube(color); break;
    case KnobIcon::Climate: drawClimate(color); break;
    case KnobIcon::Geyser: drawGeyser(color); break;
    case KnobIcon::Tv: drawTv(color); break;
    case KnobIcon::Speaker: drawSpeaker(color); break;
    case KnobIcon::Warning: drawWarning(color); break;
    case KnobIcon::Home: drawHome(color); break;
  }
}

void setLabelText(lv_obj_t *label, const char *text) {
  if (strcmp(lv_label_get_text(label), text) != 0) lv_label_set_text(label, text);
}

void positionInnerRingDash(size_t index) {
  const int angleTenths = static_cast<int>(index * 3600 / INNER_RING_DASH_COUNT) - 900;
  const float radians = static_cast<float>(angleTenths) * static_cast<float>(M_PI) / 1800.0f;
  const float centerX = SCREEN_CENTER + std::cos(radians) * INNER_RING_RADIUS;
  const float centerY = SCREEN_CENTER + std::sin(radians) * INNER_RING_RADIUS;
  const float tangentX = -std::sin(radians) * 3.0f;
  const float tangentY = std::cos(radians) * 3.0f;
  const int x1 = static_cast<int>(std::lround(centerX - tangentX));
  const int y1 = static_cast<int>(std::lround(centerY - tangentY));
  const int x2 = static_cast<int>(std::lround(centerX + tangentX));
  const int y2 = static_cast<int>(std::lround(centerY + tangentY));
  innerRingSegments[index][0] = {static_cast<lv_coord_t>(x1), static_cast<lv_coord_t>(y1)};
  innerRingSegments[index][1] = {static_cast<lv_coord_t>(x2), static_cast<lv_coord_t>(y2)};
}

lv_opa_t innerRingOpacity(size_t index) {
  const size_t distance = (innerRingPhase + INNER_RING_DASH_COUNT - index) % INNER_RING_DASH_COUNT;
  if (distance == 0) return static_cast<lv_opa_t>(128);
  if (distance == 1) return static_cast<lv_opa_t>(88);
  if (distance == 2) return static_cast<lv_opa_t>(56);
  if (distance == 3) return static_cast<lv_opa_t>(32);
  return static_cast<lv_opa_t>(18);
}

void invalidateInnerRingDash(size_t index) {
  constexpr int padding = 3;
  const lv_point_t &start = innerRingSegments[index][0];
  const lv_point_t &end = innerRingSegments[index][1];
  lv_area_t area = {
      static_cast<lv_coord_t>(std::min(start.x, end.x) - padding),
      static_cast<lv_coord_t>(std::min(start.y, end.y) - padding),
      static_cast<lv_coord_t>(std::max(start.x, end.x) + padding),
      static_cast<lv_coord_t>(std::max(start.y, end.y) + padding),
  };
  lv_obj_invalidate_area(innerRingLayer, &area);
}

void drawInnerRing(lv_event_t *event) {
  if (lv_event_get_code(event) != LV_EVENT_DRAW_MAIN) return;
  lv_draw_ctx_t *drawContext = lv_event_get_draw_ctx(event);
  lv_draw_line_dsc_t descriptor;
  lv_draw_line_dsc_init(&descriptor);
  descriptor.color = lv_color_hex(COLOR_GOLD);
  descriptor.width = 1;
  descriptor.opa = LV_OPA_10;
  descriptor.round_start = true;
  descriptor.round_end = true;
  for (size_t i = 0; i < INNER_RING_DASH_COUNT; ++i) {
    descriptor.opa = innerRingOpacity(i);
    lv_draw_line(drawContext, &descriptor, &innerRingSegments[i][0], &innerRingSegments[i][1]);
  }
}

void rotateInnerRing(lv_timer_t *) {
  const size_t oldTail =
      (innerRingPhase + INNER_RING_DASH_COUNT - (INNER_RING_TRAIL_LENGTH - 1)) % INNER_RING_DASH_COUNT;
  innerRingPhase = (innerRingPhase + 1) % INNER_RING_DASH_COUNT;
  invalidateInnerRingDash(oldTail);
  for (size_t i = 0; i < INNER_RING_TRAIL_LENGTH; ++i) {
    invalidateInnerRingDash((innerRingPhase + INNER_RING_DASH_COUNT - i) % INNER_RING_DASH_COUNT);
  }
}

void updateDots(const KnobUiModel &model) {
  const size_t visibleCount = model.itemCount > MAX_DOTS ? MAX_DOTS : model.itemCount;
  const size_t oldVisibleCount = renderedItemCount > MAX_DOTS ? MAX_DOTS : renderedItemCount;
  const bool geometryChanged = !hasRendered || visibleCount != oldVisibleCount;
  const float step = geometryChanged && visibleCount > 0 ? 360.0f / static_cast<float>(visibleCount) : 0.0f;
  const size_t selectedIndex = visibleCount > 0 ? model.selectedIndex % visibleCount : 0;
  const size_t oldSelectedIndex = oldVisibleCount > 0 ? renderedIndex % oldVisibleCount : MAX_DOTS;
  const uint16_t changedActiveMask = model.activeMask ^ renderedActiveMask;

  for (size_t i = 0; i < MAX_DOTS; ++i) {
    lv_obj_t *dot = dots[i];
    if (i >= visibleCount) {
      if (geometryChanged) lv_obj_add_flag(dot, LV_OBJ_FLAG_HIDDEN);
      continue;
    }

    if (geometryChanged) {
      lv_obj_clear_flag(dot, LV_OBJ_FLAG_HIDDEN);
      const float radians = (-90.0f + static_cast<float>(i) * step) * static_cast<float>(M_PI) / 180.0f;
      constexpr int size = 7;
      const int x = static_cast<int>(std::lround(SCREEN_CENTER + std::cos(radians) * DOT_RADIUS - size / 2));
      const int y = static_cast<int>(std::lround(SCREEN_CENTER + std::sin(radians) * DOT_RADIUS - size / 2));
      lv_obj_set_pos(dot, x, y);
    }

    const bool styleChanged = geometryChanged || i == selectedIndex || i == oldSelectedIndex ||
                              (changedActiveMask & (static_cast<uint16_t>(1U) << i)) != 0;
    if (!styleChanged) continue;

    const bool selected = i == selectedIndex;
    const bool active = (model.activeMask & (static_cast<uint16_t>(1U) << i)) != 0;
    lv_obj_set_style_bg_color(dot, lv_color_hex(selected || active ? COLOR_GREEN : COLOR_GOLD), 0);
    lv_obj_set_style_bg_opa(dot, selected ? LV_OPA_COVER : (active ? LV_OPA_40 : LV_OPA_20), 0);
    lv_obj_set_style_shadow_width(dot, selected ? 10 : 0, 0);
    lv_obj_set_style_shadow_opa(dot, selected ? LV_OPA_50 : LV_OPA_TRANSP, 0);
  }
}

}  // namespace

void knobUiCreate(KnobUiCallback centerCallback, KnobUiCallback backCallback) {
  onCenter = centerCallback;
  onBack = backCallback;

  screen = lv_obj_create(nullptr);
  lv_obj_set_size(screen, SCREEN_SIZE, SCREEN_SIZE);
  lv_obj_set_pos(screen, 0, 0);
  lv_obj_clear_flag(screen, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_style_bg_color(screen, lv_color_hex(COLOR_BACKGROUND), 0);
  lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
  lv_obj_set_style_border_width(screen, 0, 0);
  lv_obj_set_style_pad_all(screen, 0, 0);
  lv_obj_set_style_text_color(screen, lv_color_hex(COLOR_TEXT), 0);

  lv_obj_t *innerGlow = lv_obj_create(screen);
  lv_obj_set_size(innerGlow, 390, 390);
  lv_obj_center(innerGlow);
  lv_obj_clear_flag(innerGlow, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_style_radius(innerGlow, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_color(innerGlow, lv_color_hex(COLOR_INNER), 0);
  lv_obj_set_style_bg_opa(innerGlow, LV_OPA_70, 0);
  lv_obj_set_style_border_width(innerGlow, 0, 0);
  lv_obj_set_style_shadow_color(innerGlow, lv_color_hex(COLOR_GREEN), 0);
  lv_obj_set_style_shadow_width(innerGlow, 54, 0);
  lv_obj_set_style_shadow_opa(innerGlow, LV_OPA_10, 0);

  lv_obj_t *outerRing = lv_obj_create(screen);
  lv_obj_set_size(outerRing, 452, 452);
  lv_obj_center(outerRing);
  lv_obj_clear_flag(outerRing, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_style_radius(outerRing, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_opa(outerRing, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_color(outerRing, lv_color_hex(COLOR_GOLD), 0);
  lv_obj_set_style_border_opa(outerRing, LV_OPA_20, 0);
  lv_obj_set_style_border_width(outerRing, 1, 0);

  innerRingLayer = lv_obj_create(screen);
  lv_obj_remove_style_all(innerRingLayer);
  lv_obj_set_size(innerRingLayer, SCREEN_SIZE, SCREEN_SIZE);
  lv_obj_set_pos(innerRingLayer, 0, 0);
  lv_obj_clear_flag(innerRingLayer, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_event_cb(innerRingLayer, drawInnerRing, LV_EVENT_DRAW_MAIN, nullptr);
  for (size_t i = 0; i < INNER_RING_DASH_COUNT; ++i) positionInnerRingDash(i);
  if (INNER_RING_CONTINUOUS_ANIMATION) lv_timer_create(rotateInnerRing, INNER_RING_TICK_MS, nullptr);

  for (size_t i = 0; i < MAX_DOTS; ++i) {
    dots[i] = lv_obj_create(screen);
    lv_obj_clear_flag(dots[i], LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(dots[i], LV_OBJ_FLAG_HIDDEN);
    lv_obj_set_size(dots[i], 7, 7);
    lv_obj_set_style_radius(dots[i], LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(dots[i], 0, 0);
    lv_obj_set_style_shadow_color(dots[i], lv_color_hex(COLOR_GREEN), 0);
    lv_obj_set_style_pad_all(dots[i], 0, 0);
  }

  clockLabel = lv_label_create(screen);
  lv_obj_set_width(clockLabel, 84);
  lv_label_set_text(clockLabel, "--:--");
  lv_obj_set_style_text_font(clockLabel, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_align(clockLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_color(clockLabel, lv_color_hex(COLOR_MUTED), 0);
  lv_obj_align(clockLabel, LV_ALIGN_TOP_MID, 0, 40);

  iconRing = lv_btn_create(screen);
  lv_obj_remove_style_all(iconRing);
  lv_obj_set_size(iconRing, 138, 138);
  lv_obj_align(iconRing, LV_ALIGN_TOP_MID, 0, 120);
  lv_obj_clear_flag(iconRing, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_style_radius(iconRing, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_color(iconRing, lv_color_hex(COLOR_INNER), 0);
  lv_obj_set_style_bg_opa(iconRing, LV_OPA_COVER, 0);
  lv_obj_set_style_border_width(iconRing, 1, 0);
  lv_obj_set_style_pad_all(iconRing, 0, 0);
  lv_obj_set_style_shadow_spread(iconRing, 1, 0);
  lv_obj_set_ext_click_area(iconRing, 72);
  lv_obj_add_event_cb(iconRing, centerEvent, LV_EVENT_CLICKED, nullptr);

  iconCanvas = lv_canvas_create(iconRing);
  lv_canvas_set_buffer(iconCanvas, iconCanvasBuffer, ICON_CANVAS_SIZE, ICON_CANVAS_SIZE,
                       LV_IMG_CF_TRUE_COLOR_CHROMA_KEYED);
  lv_obj_center(iconCanvas);

  nameLabel = lv_label_create(screen);
  lv_obj_set_size(nameLabel, 310, 34);
  lv_label_set_long_mode(nameLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_style_text_font(nameLabel, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_align(nameLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_color(nameLabel, lv_color_hex(COLOR_TEXT), 0);
  lv_obj_align(nameLabel, LV_ALIGN_TOP_MID, 0, 276);

  statusLabel = lv_label_create(screen);
  lv_obj_set_size(statusLabel, 300, 18);
  lv_label_set_long_mode(statusLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_style_text_font(statusLabel, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_align(statusLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_color(statusLabel, lv_color_hex(COLOR_MUTED), 0);
  lv_obj_align(statusLabel, LV_ALIGN_TOP_MID, 0, 316);

  hintLabel = lv_label_create(screen);
  lv_obj_set_size(hintLabel, 280, 16);
  lv_label_set_long_mode(hintLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_style_text_font(hintLabel, &lv_font_montserrat_10, 0);
  lv_obj_set_style_text_align(hintLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_color(hintLabel, lv_color_hex(COLOR_DIM), 0);
  lv_obj_align(hintLabel, LV_ALIGN_TOP_MID, 0, 342);

  backButton = lv_btn_create(screen);
  lv_obj_remove_style_all(backButton);
  lv_obj_set_size(backButton, 52, 52);
  lv_obj_align(backButton, LV_ALIGN_TOP_MID, 0, 364);
  lv_obj_set_style_radius(backButton, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_color(backButton, lv_color_hex(COLOR_INNER), 0);
  lv_obj_set_style_bg_opa(backButton, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(backButton, lv_color_hex(COLOR_GOLD), 0);
  lv_obj_set_style_border_opa(backButton, LV_OPA_30, 0);
  lv_obj_set_style_border_width(backButton, 1, 0);
  lv_obj_set_style_shadow_width(backButton, 0, 0);
  lv_obj_set_style_pad_all(backButton, 0, 0);
  lv_obj_set_ext_click_area(backButton, 64);
  lv_obj_add_event_cb(backButton, backEvent, LV_EVENT_CLICKED, nullptr);
  lv_obj_t *backIcon = lv_label_create(backButton);
  lv_label_set_text(backIcon, LV_SYMBOL_LEFT);
  lv_obj_set_style_text_color(backIcon, lv_color_hex(COLOR_GOLD), 0);
  lv_obj_set_style_text_font(backIcon, &lv_font_montserrat_16, 0);
  lv_obj_center(backIcon);
  lv_obj_add_flag(backButton, LV_OBJ_FLAG_HIDDEN);

  indexLabel = lv_label_create(screen);
  lv_obj_set_width(indexLabel, 100);
  lv_obj_set_style_text_font(indexLabel, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_align(indexLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_color(indexLabel, lv_color_hex(COLOR_MUTED), 0);
  lv_obj_align(indexLabel, LV_ALIGN_BOTTOM_MID, 0, -40);

  lv_scr_load(screen);
}

void knobUiRender(const KnobUiModel &model) {
  if (!screen) return;

  const bool dotsChanged = !hasRendered || model.selectedIndex != renderedIndex ||
                           model.itemCount != renderedItemCount || model.activeMask != renderedActiveMask;
  if (dotsChanged) updateDots(model);

  setLabelText(nameLabel, model.name);
  setLabelText(statusLabel, model.status);
  setLabelText(hintLabel, model.hint);

  char indexText[20];
  const size_t displayedIndex = model.itemCount ? model.selectedIndex + 1 : 0;
  lv_snprintf(indexText, sizeof(indexText), "%u / %u", static_cast<unsigned>(displayedIndex),
              static_cast<unsigned>(model.itemCount));
  setLabelText(indexLabel, indexText);

  if (!hasRendered || model.deviceMode != renderedDeviceMode) {
    if (model.deviceMode) {
      lv_obj_clear_flag(backButton, LV_OBJ_FLAG_HIDDEN);
    } else {
      lv_obj_add_flag(backButton, LV_OBJ_FLAG_HIDDEN);
    }
  }

  uint32_t accent = model.deviceMode ? COLOR_GREEN : COLOR_GOLD;
  if (model.deviceMode && (!model.on || model.unavailable)) accent = COLOR_MUTED;
  if (model.unavailable) accent = COLOR_ERROR;
  const lv_color_t accentColor = lv_color_hex(accent);

  const bool ringChanged = !hasRendered || accent != renderedAccent || model.on != renderedOn ||
                           model.unavailable != renderedUnavailable || model.busy != renderedBusy;
  if (ringChanged) {
    lv_obj_set_style_border_color(iconRing, accentColor, 0);
    lv_obj_set_style_border_opa(iconRing, model.busy ? LV_OPA_60 : (model.unavailable ? LV_OPA_50 : LV_OPA_COVER), 0);
    lv_obj_set_style_shadow_color(iconRing, accentColor, 0);
    lv_obj_set_style_shadow_width(iconRing, model.busy ? 8 : (model.on && !model.unavailable ? 28 : 14), 0);
    lv_obj_set_style_shadow_opa(iconRing, model.busy ? LV_OPA_10 : (model.on && !model.unavailable ? LV_OPA_30 : LV_OPA_10), 0);
    lv_obj_set_style_bg_color(iconRing, model.on && !model.unavailable ? lv_color_hex(0x0B1814) : lv_color_hex(COLOR_INNER), 0);
  }

  if (!hasRendered || model.icon != renderedIcon || accent != renderedAccent) {
    drawIcon(model.icon, accentColor);
  }

  if (!hasRendered || model.live != renderedLive || model.online != renderedOnline) {
    lv_obj_set_style_text_color(
        clockLabel, lv_color_hex(model.live ? COLOR_GREEN : (model.online ? COLOR_GOLD : COLOR_MUTED)), 0);
  }
  if (!hasRendered || model.unavailable != renderedUnavailable) {
    lv_obj_set_style_text_color(statusLabel, lv_color_hex(model.unavailable ? COLOR_ERROR : COLOR_MUTED), 0);
  }

  renderedIndex = model.selectedIndex;
  renderedItemCount = model.itemCount;
  renderedActiveMask = model.activeMask;
  renderedDeviceMode = model.deviceMode;
  renderedOnline = model.online;
  renderedLive = model.live;
  renderedOn = model.on;
  renderedUnavailable = model.unavailable;
  renderedBusy = model.busy;
  renderedIcon = model.icon;
  renderedAccent = accent;
  hasRendered = true;
}

void knobUiSetClock(const char *timeText) {
  if (clockLabel) setLabelText(clockLabel, timeText);
}
