# Vokrr Room View Design System

This file defines the complete visual design system for the Vokrr smart home room dashboard inspired by the 640x480 room mockup. Use this as the single source of truth for colors, typography, spacing, layout, components, and dark/light mode behavior.

---

## 1. Product Context

Vokrr is a futuristic, cinematic smart home dashboard designed for Raspberry Pi touchscreen displays. The target screen is compact, touch-first, and always-on.

Primary target display:

- Base design resolution: `640x480px`
- Aspect ratio: `4:3`
- Touchscreen: Raspberry Pi official 7-inch display / compact dashboard screens
- UI style: premium dark glass, neon blue accents, soft glow, rounded cards, cinematic smart-home control center

The room view must support:

- Multiple devices in one room
- Room hero image / room visual
- Quick controls
- Device cards
- Environment summary
- Camera preview
- Media player
- Sidebar navigation
- Dark and light mode

---

## 2. Design Principles

1. **Cinematic, not generic**
   - The UI should feel like a futuristic home operating system, not a basic dashboard.

2. **Readable from distance**
   - Text must be readable on a 7-inch display from 1-2 meters away.

3. **Touch-first**
   - Tap targets should never feel tiny.
   - Minimum useful tap area: `44x44px`.

4. **Information hierarchy first**
   - Room status and core controls first.
   - Device list second.
   - Extra widgets third.

5. **Soft depth**
   - Use subtle glass cards, borders, shadows, and glow.
   - Do not use harsh flat blocks.

6. **Avoid clutter**
   - 640x480 is small. Reduce text and keep controls compact.

---

## 3. Layout System

### 3.1 Base Frame

```text
Canvas: 640x480px
Safe padding: 8px
Grid: 8px base unit
Corner radius language: soft, rounded, futuristic
```

### 3.2 Main Layout

The 640x480 room view should use this structure:

```text
┌──────────────────────────────────────────────────────────────┐
│ Sidebar │ Header / Status / Weather                         │
│         ├──────────────────────────────┬────────────────────┤
│         │ Room Hero Visual             │ Right Widgets      │
│         │ Floating Quick Controls      │ Environment        │
│         │                              │ Cameras / Media    │
│         ├──────────────────────────────┴────────────────────┤
│         │ Device Grid                                        │
└──────────────────────────────────────────────────────────────┘
```

### 3.3 Recommended Pixel Layout

For a strict 640x480 implementation:

| Region | X | Y | W | H |
|---|---:|---:|---:|---:|
| App Shell | 0 | 0 | 640 | 480 |
| Sidebar nav items | 8 | 0 | 64 | 480 |
| Main Content | 76 | 0 | 564 | 480 |
| Header | 84 | 12 | 548 | 56 |
| Hero Room Visual | 84 | 76 | 356 | 214 |
| Right Widgets | 448 | 76 | 184 | 306 |
| Device Section | 84 | 300 | 356 | 164 |
| Bottom/Extra Widget | 448 | 390 | 184 | 74 |

Sidebar items sit directly on the app background. Do not draw a sidebar underlay/background panel.
The main content must end at the right safe padding (`x=632`) and must not leave unused right-side space.

### 3.4 Spacing Scale

Use only these spacing values unless absolutely necessary:

| Token | Value | Usage |
|---|---:|---|
| `space-1` | 2px | Tiny icon/text offsets |
| `space-2` | 4px | Micro gaps |
| `space-3` | 6px | Dense metadata spacing |
| `space-4` | 8px | Base gap |
| `space-5` | 10px | Compact card padding |
| `space-6` | 12px | Standard internal padding |
| `space-8` | 16px | Section spacing |
| `space-10` | 20px | Large section spacing |
| `space-12` | 24px | Major layout gap |

Do not use large desktop spacing like 32px/48px on the 640x480 view.

---

## 4. Color System

The design must support dark and light mode. Dark mode is the primary experience. Light mode should be premium, soft, and not plain white.

---

## 4.1 Dark Mode Colors

### Background

| Token | Hex | Usage |
|---|---|---|
| `bg-app` | `#212121` | Full app background |
| `bg-shell` | `#050A14` | Sidebar / main shell |
| `bg-surface` | `#0B1220` | Main cards |
| `bg-surface-soft` | `#101827` | Secondary cards |
| `bg-surface-glass` | `rgba(10, 18, 32, 0.72)` | Glass panels |
| `bg-overlay` | `rgba(3, 7, 18, 0.46)` | Dark overlay on hero image |

### Borders

| Token | Value | Usage |
|---|---|---|
| `border-subtle` | `rgba(148, 163, 184, 0.14)` | Default card borders |
| `border-active` | `rgba(45, 125, 255, 0.42)` | Active nav/card border |
| `border-glow` | `rgba(0, 174, 239, 0.35)` | Neon highlight border |

### Text

| Token | Hex | Usage |
|---|---|---|
| `text-primary` | `#F8FAFC` | Main titles |
| `text-secondary` | `#CBD5E1` | Body text |
| `text-muted` | `#94A3B8` | Metadata |
| `text-disabled` | `#64748B` | Disabled text |
| `text-inverse` | `#020617` | Text on bright surfaces |

### Accent Colors

| Token | Hex | Usage |
|---|---|---|
| `accent-blue` | `#2D7DFF` | Main interactive blue |
| `accent-cyan` | `#00AEEF` | Neon glow / highlights |
| `accent-cyan-soft` | `#38BDF8` | Secondary blue text |
| `accent-green` | `#00D26A` | Online / success |
| `accent-yellow` | `#FBBF24` | Lights / warm controls |
| `accent-orange` | `#F59E0B` | Warm glow |
| `accent-red` | `#FF3B30` | Power off / critical |
| `accent-purple` | `#8B5CF6` | AI assistant |

### Gradients

```css
--gradient-app-dark: radial-gradient(circle at 70% 20%, rgba(0,174,239,0.14), transparent 34%), #212121;
--gradient-card-dark: linear-gradient(145deg, rgba(15,23,42,0.92), rgba(2,6,23,0.78));
--gradient-active-dark: linear-gradient(135deg, rgba(45,125,255,0.34), rgba(0,174,239,0.12));
--gradient-hero-overlay-dark: linear-gradient(180deg, rgba(3,7,18,0.10), rgba(3,7,18,0.78));
```

---

## 4.2 Light Mode Colors

Light mode must keep the same futuristic identity, but replace black glass with frosted light panels.

### Background

| Token | Hex | Usage |
|---|---|---|
| `bg-app` | `#e8e8e8` | Full app background |
| `bg-shell` | `#F8FBFF` | Sidebar / shell |
| `bg-surface` | `#FFFFFF` | Main cards |
| `bg-surface-soft` | `#F1F7FF` | Secondary cards |
| `bg-surface-glass` | `rgba(255, 255, 255, 0.74)` | Glass panels |
| `bg-overlay` | `rgba(255, 255, 255, 0.30)` | Hero image soft overlay |

### Borders

| Token | Value | Usage |
|---|---|---|
| `border-subtle` | `rgba(15, 23, 42, 0.10)` | Default card borders |
| `border-active` | `rgba(45, 125, 255, 0.38)` | Active state |
| `border-glow` | `rgba(0, 174, 239, 0.28)` | Glow highlight |

### Text

| Token | Hex | Usage |
|---|---|---|
| `text-primary` | `#07111F` | Main titles |
| `text-secondary` | `#334155` | Body text |
| `text-muted` | `#64748B` | Metadata |
| `text-disabled` | `#94A3B8` | Disabled text |
| `text-inverse` | `#FFFFFF` | Text on dark/blue surfaces |

### Accent Colors

Use the same accent colors as dark mode, but reduce glow opacity by 35-45%.

| Token | Hex | Usage |
|---|---|---|
| `accent-blue` | `#1E6BFF` | Main interactive blue |
| `accent-cyan` | `#009EE2` | Neon highlight |
| `accent-cyan-soft` | `#0284C7` | Secondary blue text |
| `accent-green` | `#00A85A` | Online / success |
| `accent-yellow` | `#EAB308` | Lights / warm controls |
| `accent-orange` | `#EA8A00` | Warm glow |
| `accent-red` | `#E53935` | Power off / critical |
| `accent-purple` | `#7C3AED` | AI assistant |

### Gradients

```css
--gradient-app-light: radial-gradient(circle at 70% 18%, rgba(0,174,239,0.18), transparent 36%), #e8e8e8;
--gradient-card-light: linear-gradient(145deg, rgba(255,255,255,0.94), rgba(241,247,255,0.82));
--gradient-active-light: linear-gradient(135deg, rgba(45,125,255,0.18), rgba(0,174,239,0.10));
--gradient-hero-overlay-light: linear-gradient(180deg, rgba(255,255,255,0.02), rgba(255,255,255,0.58));
```

---

## 5. Typography

### 5.1 Font Family

Preferred font:

```css
font-family: Inter, SF Pro Display, SF Pro Text, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
```

For Qt/QML, use:

```qml
font.family: "Inter"
```

Fallback:

```qml
font.family: Qt.platform.os === "osx" ? "SF Pro Display" : "DejaVu Sans"
```

### 5.2 Type Scale for 640x480

| Token | Size | Weight | Line Height | Usage |
|---|---:|---:|---:|---|
| `display-sm` | 26px | 700 | 32px | Room title: Living Room |
| `heading-lg` | 20px | 700 | 26px | Section headings |
| `heading-md` | 16px | 700 | 22px | Card titles |
| `body-lg` | 15px | 500 | 21px | Primary labels |
| `body-md` | 13px | 500 | 18px | Device metadata |
| `body-sm` | 12px | 500 | 16px | Sidebar labels / widget text |
| `caption` | 10px | 500 | 14px | Tiny status labels |
| `number-lg` | 22px | 700 | 28px | Temperature/time metrics |
| `number-md` | 16px | 700 | 22px | Device values |

### 5.3 Typography Rules

- Use semibold/bold for labels, not thin text.
- Use muted text for metadata.
- Avoid paragraphs in this screen.
- Keep labels short:
  - Use `AC` instead of `Air Conditioner`
  - Use `Temp` instead of `Temperature` if space is tight
  - Use `3 Speed` instead of `Speed Level 3`

---

## 6. Radius System

| Token | Value | Usage |
|---|---:|---|
| `radius-xs` | 6px | Small badges |
| `radius-sm` | 10px | Small buttons |
| `radius-md` | 14px | Quick control pills |
| `radius-lg` | 18px | Device cards |
| `radius-xl` | 22px | Main panels |
| `radius-full` | 999px | Avatars, status dots, circular buttons |

---

## 7. Shadows and Glow

### 7.1 Dark Mode Shadows

```css
--shadow-card-dark: 0 12px 32px rgba(0, 0, 0, 0.34);
--shadow-soft-dark: 0 8px 20px rgba(0, 0, 0, 0.24);
--shadow-blue-glow-dark: 0 0 22px rgba(0, 174, 239, 0.28);
--shadow-yellow-glow-dark: 0 0 18px rgba(251, 191, 36, 0.28);
--shadow-green-glow-dark: 0 0 14px rgba(0, 210, 106, 0.25);
```

### 7.2 Light Mode Shadows

```css
--shadow-card-light: 0 10px 30px rgba(15, 23, 42, 0.10);
--shadow-soft-light: 0 8px 18px rgba(15, 23, 42, 0.08);
--shadow-blue-glow-light: 0 0 18px rgba(0, 174, 239, 0.16);
--shadow-yellow-glow-light: 0 0 14px rgba(234, 179, 8, 0.16);
--shadow-green-glow-light: 0 0 12px rgba(0, 168, 90, 0.14);
```

### 7.3 Glow Rules

- Use glow only on active/important elements.
- Never apply strong glow to every card.
- Active room navigation should have a blue glow.
- Lights should use warm yellow glow.
- AC/Fan/Camera should use cyan/blue glow.
- Online status should use green glow.

---

## 8. Icon System

### 8.1 Icon Style

- Use line icons with rounded caps.
- Stroke width: `1.75px` to `2px`.
- Icons should feel technical and premium, not playful.

Recommended icon size:

| Area | Size |
|---|---:|
| Sidebar icons | 18px |
| Header icon buttons | 20px |
| Quick control icons | 18px |
| Device card icons | 22px |
| Widget icons | 18px |
| Power buttons | 18px |

### 8.2 Icon Colors

| Device Type | Icon Color |
|---|---|
| Lights | `accent-yellow` |
| AC | `accent-cyan` |
| Fan | `accent-blue` |
| TV | `accent-blue` |
| Soundbar | `accent-cyan` |
| Curtains | `accent-blue` |
| Camera | `accent-cyan` |
| Air purifier | `text-muted` or `accent-green` when active |
| Power off | `accent-red` |
| Online | `accent-green` |

---

## 9. Components

## 9.1 App Shell

The app shell contains sidebar and main room content.

### Dark Mode

- Background: `gradient-app-dark`
- Sidebar nav items: directly on `bg-app`; no sidebar underlay/background panel.
- Main background: transparent over app background

### Light Mode

- Background: `gradient-app-light`
- Sidebar nav items: directly on `bg-app`; no sidebar underlay/background panel.
- Main background: transparent over app background

---

## 9.2 Sidebar

### Size

```text
Width: 64px nav item rail, no background panel
Height: 480px
Padding: 12px 4px
```

### Logo Area

```text
Height: 54px
Logo mark: hidden on room dashboard
Text: hidden on room dashboard
```

The room dashboard home screen must not show the Vokrr logo or Vokrr wordmark.

### Nav Item

```text
Width: 56px
Height: 52px
Radius: 16px
Gap: 6px
Icon: 18px
Text: 12px
```

### Active Nav

Dark:

```css
background: linear-gradient(135deg, rgba(45,125,255,0.32), rgba(0,174,239,0.10));
border: 1px solid rgba(45,125,255,0.42);
box-shadow: 0 0 18px rgba(45,125,255,0.18);
```

Light:

```css
background: linear-gradient(135deg, rgba(45,125,255,0.16), rgba(0,174,239,0.08));
border: 1px solid rgba(45,125,255,0.32);
box-shadow: 0 0 14px rgba(45,125,255,0.10);
```

---

## 9.3 Header

### Structure

```text
Back Button | Room Title + Metadata | Status Pill | Weather + Time Card
```

### Sizes

```text
Header height: 56px
Back button: 38x38px
Title: 26px / 700
Metadata: 13px / 500
Status pill: height 34px, radius 14px
Weather/time card: height 48px, radius 16px
```

### Room Metadata

Example:

```text
8 Devices • 2 Cameras
```

Use blue accent for numbers.

---

## 9.4 Hero Room Visual

### Size

```text
X: 108px
Y: 76px
W: 344px
H: 214px
Radius: 22px
```

### Background

- Use a realistic room image or generated render.
- Apply dark/light overlay depending on theme.
- Add neon blue edge light overlay.

### Overlay Rules

Dark:

```css
background-overlay: linear-gradient(180deg, rgba(3,7,18,0.05), rgba(3,7,18,0.72));
```

Light:

```css
background-overlay: linear-gradient(180deg, rgba(255,255,255,0.02), rgba(255,255,255,0.46));
```

### Floating Quick Controls

Place on top of hero visual.

```text
Top: 10px
Left: 10px
Gap: 8px
Card height: 42px
Card width: 94-104px
Radius: 14px
```

Quick control examples:

- Lights 70%
- AC 24°C
- Fan 3 Speed

---

## 9.5 Quick Control Card

### Size

```text
Width: 96px
Height: 42px
Padding: 8px 10px
Radius: 14px
Gap: 8px
```

### Content

```text
Icon left
Label top
Value bottom
```

### Typography

- Label: `12px`, semibold, primary text
- Value: `13px`, semibold, accent color

---

## 9.6 Room Off Button

Use this as a prominent but compact control.

```text
Width: 86px
Height: 42px
Radius: 14px
Position: upper-right area of hero visual
```

Dark:

```css
background: rgba(10,18,32,0.76);
border: 1px solid rgba(148,163,184,0.16);
```

Power icon:

```css
color: #FF3B30;
```

---

## 9.7 Device Section

### Container

```text
X: 108px
Y: 300px
W: 344px
H: 164px
Radius: 22px
Padding: 12px
```

### Header

```text
Height: 24px
Icon: 18px
Title: Devices, 16px, 700
```

### Device Grid

For 640x480:

```text
Columns: 2 or 3 depending density
Recommended: 2 columns for touch comfort
Compact alternative: 4 columns if card controls are read-only
Gap: 8px
Card height: 54-62px
```

Preferred 640x480 layout:

```text
2 columns x 4 visible cards
```

If the current room has more than 4 devices, keep 4 cards visible and page/swipe horizontally. Do not shrink cards below touch-friendly size to fit more.

If screen needs to match the image more closely, use:

```text
4 columns x 2 rows with compact cards
```

But for actual Raspberry Pi touch usage, 2 columns is safer.

---

## 9.8 Device Card

### Compact Card Size

```text
Width: 76px to 80px in 4-column mode
Height: 58px
Radius: 16px
Padding: 8px
```

### Comfortable Card Size

```text
Width: 156px
Height: 58px
Radius: 16px
Padding: 10px
```

### Content

- Icon block
- Device name
- Device brand/location metadata
- Status/value
- Power button

### States

#### Active

Dark:

```css
background: linear-gradient(145deg, rgba(15,23,42,0.94), rgba(5,12,24,0.82));
border: 1px solid rgba(45,125,255,0.22);
box-shadow: 0 8px 20px rgba(0,0,0,0.22);
```

Light:

```css
background: linear-gradient(145deg, rgba(255,255,255,0.96), rgba(241,247,255,0.88));
border: 1px solid rgba(45,125,255,0.18);
box-shadow: 0 8px 20px rgba(15,23,42,0.08);
```

#### Inactive

- Reduce opacity of icon glow.
- Status text should use muted color.
- Power button still visible.

---

## 9.9 Environment Widget

### Size

```text
Width: 164px
Height: 132px
Radius: 20px
Padding: 12px
```

### Content

- Header: icon + `Environment`
- 3 metrics: temperature, humidity, AQI
- Small line graph
- Updated timestamp

### Metrics

```text
24.6°C
58%
AQI 42
```

### Graph

- Height: 24px
- Stroke: `accent-blue`
- Soft fill under curve

---

## 9.10 Camera Widget

### Size

```text
Width: 164px
Height: 166px
Radius: 20px
Padding: 10px
```

### Camera Thumbnail

```text
Width: 144px
Height: 54px
Radius: 12px
```

Show:

- Camera name
- Green live dot
- `Live` text
- Small camera icon

---

## 9.11 Media Widget

### Size

```text
Width: 164px
Height: 74px minimum
Radius: 20px
Padding: 10px
```

For full media controls, allow height `110px`.

Content:

- Now Playing label
- Album art: 36x36px
- Song title
- Artist
- Previous / Play / Next controls
- Equalizer line

---

## 10. Interactive States

### Hover / Focus / Pressed

Even on touchscreen, pressed states are required.

| State | Behavior |
|---|---|
| Default | Glass card, subtle border |
| Hover | Slightly brighter border and glow |
| Pressed | Scale `0.98`, reduce opacity slightly |
| Active | Blue/cyan border and background gradient |
| Disabled | 45% opacity, no glow |

### Animation Timings

| Motion | Duration | Easing |
|---|---:|---|
| Card press | 100ms | ease-out |
| Toggle state | 180ms | ease-in-out |
| Page transition | 220ms | cubic-bezier(0.2, 0.8, 0.2, 1) |
| Glow pulse | 1800ms | ease-in-out infinite |
| Widget update | 240ms | ease-out |

Avoid heavy animations on Raspberry Pi. Use opacity/transform only where possible.

---

## 11. Theme Behavior

### 11.1 Dark Mode

Dark mode should feel like the generated mockup:

- Deep black/navy background
- Cyan-blue neon strips
- Warm light accents
- Glass cards
- Stronger image contrast
- Glow visible but controlled

### 11.2 Light Mode

Light mode should not become plain white.

It should feel like:

- Premium frosted glass
- Soft blue-tinted background
- Dark text
- Lower glow intensity
- Same layout and component hierarchy
- Same blue/yellow/green/red semantic colors

### 11.3 Theme Toggle Implementation

Use semantic tokens only. Do not hardcode colors in components.

Bad:

```css
background: #212121;
color: white;
```

Good:

```css
background: var(--color-bg-app);
color: var(--color-text-primary);
```

---

## 12. Device Types and Sample Data

Use this sample data for the room view.

```json
{
  "room": "Living Room",
  "devicesCount": 8,
  "camerasCount": 2,
  "status": "All systems normal",
  "weather": {
    "temperature": "26°C",
    "condition": "Light Rain"
  },
  "time": "07:42 PM",
  "date": "Mon, 26 May",
  "quickControls": [
    { "type": "light", "label": "Lights", "value": "70%" },
    { "type": "ac", "label": "AC", "value": "24°C" },
    { "type": "fan", "label": "Fan", "value": "3 Speed" }
  ],
  "devices": [
    { "name": "TV", "meta": "Samsung QLED", "status": "On", "type": "tv", "active": true },
    { "name": "Soundbar", "meta": "Sony HT-S40R", "status": "45%", "type": "speaker", "active": true },
    { "name": "AC", "meta": "Daikin Inverter", "status": "24°C", "type": "ac", "active": true },
    { "name": "Ceiling Light", "meta": "Main", "status": "70%", "type": "light", "active": true },
    { "name": "Strip Lights", "meta": "LED", "status": "60%", "type": "light", "active": true },
    { "name": "Fan", "meta": "Crompton", "status": "3 Speed", "type": "fan", "active": true },
    { "name": "Curtains", "meta": "Left Window", "status": "Closed", "type": "curtain", "active": false },
    { "name": "Air Purifier", "meta": "Xiaomi 4 Pro", "status": "On", "type": "purifier", "active": true }
  ],
  "environment": {
    "temperature": "24.6°C",
    "humidity": "58%",
    "aqi": "AQI 42",
    "aqiLabel": "Good",
    "updated": "Updated 1 min ago"
  },
  "cameras": [
    { "name": "Living Room", "status": "Live" },
    { "name": "Balcony", "status": "Live" }
  ],
  "media": {
    "song": "Blinding Lights",
    "artist": "The Weeknd",
    "playing": true
  }
}
```

---

## 13. Implementation Notes for Qt/QML

If implementing in Qt/QML:

- Build fresh components.
- Do not reuse current existing components.
- Use `Rectangle`, `Image`, `Text`, `MouseArea`, `ShaderEffectSource` carefully.
- Avoid heavy blur effects on Raspberry Pi.
- Prefer simulated glass using translucent fills and borders instead of live blur.
- Use `Behavior on opacity`, `Behavior on scale`, and lightweight transitions.
- Avoid loading huge images. Optimize hero image to exact display size.
- Use SVG icons if possible.
- Cache icons and images.

Recommended fresh component names:

```text
AppShell.qml
SidebarNav.qml
SidebarNavItem.qml
RoomHeader.qml
StatusPill.qml
WeatherTimeCard.qml
RoomHero.qml
QuickControlCard.qml
RoomPowerButton.qml
DeviceSection.qml
DeviceCard.qml
EnvironmentWidget.qml
CameraWidget.qml
MediaWidget.qml
Theme.qml
ThemeManager.qml
VokrrIcon.qml
```

---

## 14. Implementation Notes for React / Web

If implementing in React:

- Build fresh components.
- Do not reuse existing components.
- Do not edit existing components unless explicitly required for routing.
- Use CSS variables for all tokens.
- Use `data-theme="dark"` and `data-theme="light"` on the root.
- Use SVG icons or lucide-react.
- Avoid heavy canvas/WebGL for this specific view.
- Use compressed WebP/AVIF room images.

Recommended fresh component names:

```text
VokrrRoomView.tsx
VokrrShell.tsx
SidebarNav.tsx
RoomHeader.tsx
RoomHero.tsx
QuickControlCard.tsx
DeviceGrid.tsx
DeviceCard.tsx
EnvironmentWidget.tsx
CameraWidget.tsx
MediaWidget.tsx
ThemeToggle.tsx
```

---

## 15. Accessibility and Touch Rules

- Minimum tap area: `44x44px`.
- Text contrast must pass readable contrast in both modes.
- Active state must not rely only on color; use border/glow/fill too.
- Power buttons must be visually obvious.
- Device status must remain readable in light and dark mode.
- Use clear labels for icons.

---

## 16. Performance Rules

Target device may be Raspberry Pi, so:

- Avoid real-time blur.
- Avoid excessive shadows on many elements.
- Avoid animating layout size.
- Use opacity and transform animations only.
- Keep images small and optimized.
- Avoid nested expensive gradients where possible.
- Limit visible animated effects to 2-3 areas at once.

---

## 17. Visual QA Checklist

Before approving the implementation, verify this checklist at least 4 times:

### Pass 1: Layout

- [ ] Canvas is exactly 640x480.
- [ ] Sidebar width is close to 92px.
- [ ] Header is compact and readable.
- [ ] Hero image dominates the screen without hiding controls.
- [ ] Right widgets do not overflow.
- [ ] Device grid fits within the bottom section.

### Pass 2: Colors and Theme

- [ ] Dark mode matches the cinematic navy/black reference.
- [ ] Light mode keeps the same premium style.
- [ ] Accent blue/cyan is consistent.
- [ ] Lights use warm yellow.
- [ ] Online states use green.
- [ ] Power off uses red.

### Pass 3: Spacing and Typography

- [ ] Text is readable at 640x480.
- [ ] Cards have consistent padding.
- [ ] Icons align vertically with labels.
- [ ] Device cards do not feel cramped.
- [ ] Section headers align to the same grid.

### Pass 4: Interaction and Touch

- [ ] Tap targets are at least 44x44 where possible.
- [ ] Buttons have pressed states.
- [ ] Active nav item is obvious.
- [ ] Theme toggle works.
- [ ] Dark/light mode changes use tokens, not hardcoded colors.

---

## 18. Do Not Do

- Do not reuse existing old components.
- Do not edit current components to force this design.
- Do not hardcode dark colors inside components.
- Do not build desktop-first and shrink it down.
- Do not use tiny 8px text except for non-critical captions.
- Do not use pure white light mode background.
- Do not overuse blur on Raspberry Pi.
- Do not make every card glow.
- Do not hide important device states behind hover-only UI.

---

## 19. Acceptance Criteria

The implementation is complete only when:

- A fresh room dashboard is built from scratch.
- It visually follows the 640x480 Vokrr room mockup.
- It supports both dark and light mode.
- All tokens come from this `design.md` system.
- Existing components are not reused or edited for this screen.
- Device cards are reusable and data-driven.
- The room can display multiple devices.
- The layout remains usable at exactly 640x480.
- The UI feels premium, futuristic, and touch-friendly.
