# RigGPT

AI-driven ham radio transmission platform for the Icom IC-7610 (and other CI-V compatible radios).

RigGPT is a Flask-based web application that turns a ham radio into an AI broadcast station. It generates speech from language models, synthesizes it with a configurable TTS engine, keys PTT via CI-V serial control, and transmits over the air. It supports live Discord community integration, vector memory, automated media playback, a multi-agent AI debate mode called Acid Trip, and a Special Operations tab that lets you do deeply inadvisable things to your radio with CI-V commands.

Built by a ham who wanted to do something deeply stupid with a perfectly good radio.

---

## Features

### Core Radio Control
- CI-V serial control for Icom radios (IC-7610, IC-7300, IC-705, IC-9700, and more)
- PTT keying via CI-V with configurable address and baud rate
- Frequency and mode control from the web UI
- ALSA audio routing to the radio's USB audio codec
- Audio calibration and ALC measurement tools

### AI Transmission
- Multi-turn chat via Ollama (local LLMs), OpenAI, or Google Gemini
- Configurable persona, temperature, and token budget
- AUTO TX mode: every AI response goes straight to air
- INSPIRE, DOSE, and ORACLE modes for generative chaos
- Full AI debug log with verbose trace mode

### Acid Trip Mode
- Two AI agents debate any topic over the air, turn by turn
- Each agent has its own persona, voice, TTS engine, and LLM
- Six mode presets: Sober, Caffeinated, Spicy, Unhinged, Spiritual, Chaos
- Discord Influence: live audience messages steer the debate in real time
- Discord Interact: audience can hijack the conversation mid-trip
- Canon file injection: feed agents source material from local text files
- Per-agent audio FX: reverb, echo, chorus, flanger, pitch, overdrive, bitcrush
- Audience SSE page: live text feed of the debate for Discord viewers
- Scheduled chaos: random wildcard injections during a running trip
- Pre-trip briefing: agents receive a community knowledge brief before turn 0

### Alexa Mode
- Discord-triggered auto-response system
- Monitors the audience channel for a configurable trigger phrase (default: "AI Radio")
- Fires a single sarcastic, rude, funny AI transmission in response
- Configurable model, TTS engine, voice, and token budget

### Community Memory (Qdrant RAG)
- Ingests Discord channel history into a local Qdrant vector database
- Builds per-user behavioral profiles via LLM
- Clusters message history into conversation thread summaries
- Injects relevant community context into agent system prompts at runtime
- Three injection layers: community DNA, audience profiles, past thread summaries
- Pre-trip briefing draws on threads, profiles, and running community references
- Delta ingest via cron: only processes new messages, only rebuilds affected profiles

### Clips Tab
- Radio automation media player
- Scans a local directory for .wav, .mp3, .ogg, .flac, .aiff, .m4a files
- Click any clip to key PTT and play it over air
- Amazon S3 bucket as optional second source (requires boto3)
- Background poller rescans on a configurable interval
- 24-slot cart machine with JINGLES / PROMOS / SPOTS / MISC tiers
- OS drag-and-drop to assign files to cart slots

### Browser Tab Stream (Chrome extension)
- `chrome-extension/` is a Manifest V3 add-on that captures the audio of the
  current Chrome tab (YouTube, etc.) and streams it as 48 kHz PCM over a
  WebSocket to `/api/stream/tx`
- RigGPT keys PTT via CI-V and pipes the audio into the radio's USB codec
- Works with whatever you are logged into in Chrome — it captures the tab, not a URL
- Live status, level meter and STOP in the **LIVE** tab (BROWSER STREAM card)
- Safety: PTT drops on disconnect/idle/max-minutes, VOX-style release during
  silence (paused video), optional shared token, serialised with every other TX path
- Install steps in [`chrome-extension/README.md`](chrome-extension/README.md)

### TTS Engines
eSpeak · Piper · Edge TTS · Google TTS · OpenAI TTS · ElevenLabs · Speechify · FastKoko (Kokoro)

### Special Operations Tab
A dedicated tab for automated and experimental radio features. All settings are persisted to config on disk.

**Numbers Station** — Transmits Cold War-style 5-digit groups over air on a configurable schedule. Flat robotic eSpeak voice. Interval: 1–60 minutes. Engine-configurable.

**Solar Weather Monitor** — Polls NOAA SWPC K-index every 10 minutes. Displays live K-index with color coding (quiet/unsettled/moderate/storm/severe/extreme). Optional AUTO-TX mode: when K-index exceeds the configured threshold (default: 5), automatically transmits a geomagnetic storm alert announcement.

**Mystery Transmission** — Schedules a single transmission at a random time within a configurable overnight window (default: 02:00–04:00). Plays a random clip from the Clips library, or if none, transmits one of several pre-written cryptic lines with cave reverb. No log entry. No announcement. It just happens.

**Auto-ID** — Transmits your callsign on a configurable interval. CW (Morse) via the beacon CW engine, or voice via any TTS engine. Supports regulatory ID compliance.

**Voice Roulette** — Takes the current TX box text and transmits it using a completely random combination of TTS engine, FX preset, pitch (±12 semitones), and speed (0.6x–1.8x). The result is shown after transmission. You have no idea what it will sound like.

**Pirate Broadcast** — Transmits absurd fake news headlines on a schedule using random FX presets. Intros include "WE INTERRUPT THIS SILENCE." and "FLASH BULLETIN." Headlines include things like "AREA DOG ELECTED MAYOR. FIRST ACT: ABOLISH MONDAYS."

**Chaos Button** — A big red button that fires a random Special Op. Could be any of the above. Good luck.

### Ghost-in-the-Machine (CI-V Possession Engine)
Directly manipulates the radio hardware via CI-V serial commands in real time. Seven possession modes, all configurable and stoppable. A live possession log tracks every CI-V action. A blinking "POSSESSED" badge appears in the header while active.

All modes restore radio state on stop (where applicable).

| Mode | What it does |
|---|---|
| **VFO POLTERGEIST** | Randomly drifts the VFO frequency ±50–5000 Hz every 0.5–3 seconds. Intensity 1–5. Restores original frequency on exorcism. |
| **PASSBAND POSSESSION** | Rapidly cycles the IF filter 1→2→3→2→1. Audio breathes and pulses as the bandwidth changes. |
| **RF POWER WOBBLE** | Sinusoidal TX power modulation via CI-V cmd 0x14/0x0A. Creates an AM-like tremolo on the carrier at a random rate (0.3–2 Hz). |
| **AGC SEIZURE** | Rapid AGC mode cycling: FAST→MID→SLOW→OFF→repeat. Gain hunting makes the audio unpredictably collapse and surge. |
| **SPLIT PERSONALITY** | Enables SPLIT mode. VFO-B tuned to a random nearby offset (±1–10 kHz). TX and RX on different frequencies, periodically re-shuffled. |
| **DIGITAL GHOST** | Keys PTT and transmits random CW Morse fragments drawn from letters, numbers, and Q-codes. Sounds like a haunted station calling CQ. |
| **THE EXORCIST** | Fires VFO POLTERGEIST + PASSBAND POSSESSION + AGC SEIZURE simultaneously, while transmitting one of nine pre-written screaming lines in horror/alien/demon vocal FX. Continues for the configured duration, transmitting a new line every 15 seconds. |

### Other
- SSTV image transmission (pysstv)
- Waterfall art generator
- Transmission scheduler and beacon
- Full transmission log with playback
- Dub FX panel (audio effects on any transmission)
- Keyboard-first UI: numbered tabs, Ctrl+K command palette, Ctrl+. emergency PTT off
- In-app DOCS button with built-in user manual
- Config export/import (JSON backup with masked or plaintext keys)

---

## Tab Layout

```
CONSOLE(1) TX(2) BEACON(3) WF ART(4) SSTV(5) SCHEDULE(6) LOG(7)
CONFIG(8) SYSTEM(9) API CFG(0) AI  ACID TRIP(!)  CLIPS(📼)  SPEC OPS(☠)
```

| Tab | Contents |
|---|---|
| **CONFIG (8)** | Radio connection (freq/mode/connect), Discord Monitor live view, Discord Control Channel live view, FastKoko TTS status, config import/export |
| **SYSTEM (9)** | Audio device selection/test/calibration, gong settings, diagnostics (probe, PTT test, CI-V scan, debug log), system health |
| **API CFG (0)** | API keys (ElevenLabs, Speechify, OpenAI, S3), API integrations (Ollama, Gemini, Groq, Mistral, Discord bot, FastKoko), engine status |
| **AI** | Ollama/LLM config, AI transmit, debug log, persona, Alexa mode |
| **ACID TRIP (!)** | Two-agent AI debate mode |
| **CLIPS (📼)** | Radio automation media player, cart machine |
| **SPEC OPS (☠)** | Numbers Station, Solar Weather, Mystery TX, Auto-ID, Voice Roulette, Pirate Broadcast, Chaos Button, Ghost-in-the-Machine |

---

## Hardware

Tested on:
- **Radio:** Icom IC-7610
- **Radio machine:** Debian 13, x86_64
- **GPU/AI host:** NVIDIA RTX 5070 Ti, running Ollama and Qdrant in Docker
- **Connection:** USB (CI-V serial + USB audio codec)

Should work with any Icom radio that supports CI-V serial control and USB audio.

---

## Architecture

```
Browser (operator UI)                 Chrome extension (tab audio)
        ↓                                       ↓ WebSocket PCM
Flask app (app.py) — radio machine
        ├── CI-V serial → Icom radio (PTT + frequency + VFO + AGC + power)
        ├── ALSA aplay → USB audio codec → radio TX audio
        ├── TTS engines (local + cloud)
        ├── Discord poller (community monitoring)
        ├── Discord control channel (remote commands)
        ├── Solar weather poller (NOAA SWPC, every 10min)
        ├── Alexa watcher (trigger phrase detection)
        ├── Clips poller (media file scanner)
        └── Memory client (Qdrant RAG)
                ↓
        Qdrant vector DB (Docker, separate host)
        Ollama LLM inference (Docker, GPU host)
```

---

## Requirements

**Radio machine (Debian):**
- Python 3.11+
- Flask, requests, pyserial, APScheduler, pysstv, sounddevice
- eSpeak-ng (for default TTS and Special Ops voice)
- alsa-utils

**For Community Memory (separate host recommended):**
- Docker
- Qdrant container
- Ollama container with GPU (`--gpus all`)
- `nomic-embed-text` model (embedding)
- `qwen3:14b` model (profile and thread summarization)
- boto3 (optional, for S3 clip source)

Full dependency list in `requirements.txt`.

---

## Installation

```bash
git clone https://github.com/afitnacode/riggpt.git
cd riggpt
sudo bash INSTALL.sh
```

The install script creates the `riggpt` service user, installs dependencies, sets up the systemd service, and starts the app on port 5000.

After install, open `http://your-radio-machine-ip:5000` in a browser.

Configure your radio connection in the **CONFIG** tab. Audio device, diagnostics, and system health are in the **SYSTEM** tab. API keys and LLM providers are in **API CFG**.

**Upgrade workflow:**
```bash
cd /opt/riggpt && git pull && bash INSTALL.sh
```
The installer detects the running version from the live service API before stopping it, so upgrade output correctly shows `v2.12.37 → v2.12.38`.

---

## Configuration

All settings persist to disk automatically. Two config files are never touched by the installer:

- `/home/riggpt/app_settings.json` — all application settings (frequencies, intervals, Special Ops config, Discord inject settings, audio device, WF ART settings, beacon defaults, ghost settings, etc.)
- `/home/riggpt/api_keys.json` — API credentials (Discord bot token, ElevenLabs, OpenAI, Gemini, S3, etc.)

Use **CONFIG → EXPORT** to download a JSON backup. **+KEYS** exports with plaintext API keys — store securely.

---

## Special Ops — Safety Note

Ghost-in-the-Machine directly issues CI-V serial commands to the radio hardware. All modes restore radio state on stop. However:

- **RF POWER WOBBLE** modulates TX power; only activate while not transmitting or while testing into a dummy load
- **SPLIT PERSONALITY** enables SPLIT mode; restores on exorcism but verify VFO-A is correct after use
- **THE EXORCIST** fires multiple simultaneous CI-V threads; give the radio 2–3 seconds to settle after stopping

The EXORCISE button sends a stop signal to all active ghost threads. The possession log shows every CI-V command sent.

---

## Community Memory Setup

See the built-in manual (DOCS button in the app) for full setup instructions.

Quick start:
```bash
docker exec ollama ollama pull nomic-embed-text
docker exec ollama ollama pull qwen3:14b

export DISCORD_TOKEN="Bot your-token"
export DISCORD_CHANNEL_ID="your-channel-id"
python3 memory/riggpt-ingest.py --full
```

Enable in RigGPT: **API CFG → API INTEGRATIONS → Community Memory → ENABLED**

---

## Disclaimer

This project transmits audio over licensed amateur radio frequencies. You are responsible for complying with your local amateur radio regulations including station identification requirements. AI-generated content transmitted over the air must comply with Part 97 (or your jurisdiction's equivalent). The Ghost-in-the-Machine feature manipulates radio hardware directly; use it responsibly. The author is not responsible for what your radio says or does.

---

## License

MIT — do whatever you want with it. A mention or a QSL card would be appreciated.

---

*73 de the machine*
