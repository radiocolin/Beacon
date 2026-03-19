# Beacon

A macOS menu bar app for controlling Kuando Busylight USB devices.

## Features

- **Menu bar control** — quick access to colors, effects, and sounds without opening a window
- **Controller window** — full control with color picker, brightness, effects (solid/blink/pulse), sound playback, and volume
- **Shortcuts** — App Intents for all functions, usable in Shortcuts and Siri
- **HTTP API** — optional local server on port 29100 for control from scripts, Home Assistant, etc.
- **Persistent state** — remembers your last color and effect across launches and device reconnects
- **Start at login** — uses SMAppService for native login item support

## HTTP API

Enable via the "Enable HTTP Control" checkbox. Default port: `29100`.

```
GET  /status          — current state as JSON
POST /on              — turn on
POST /off             — turn off
POST /color           — {"red":100,"green":0,"blue":0}
POST /effect          — {"effect":"pulse","bpm":120}
POST /sound/play      — {"tone":"Funky","seconds":5}
POST /sound/start     — {"tone":"Funky"}
POST /sound/stop      — stop sound
POST /volume          — {"level":4}
```

Example: `curl -X POST http://localhost:29100/color -d '{"red":0,"green":100,"blue":0}'`

## Requirements

- macOS 13+
- Kuando Busylight (Alpha, Omega, or compatible — vendor ID 0x27BB)
- App Sandbox disabled (required for IOKit HID access)

## Building

Open `Beacon.xcodeproj` in Xcode and build the Beacon target.
