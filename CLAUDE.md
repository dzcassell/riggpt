# CLAUDE.md — RigGPT Project Guide

## What this project is
RigGPT is a Flask-based AI ham radio transmission platform for the Icom IC-7610 (and other CI-V compatible radios). It generates TTS speech, keys PTT via CI-V serial, and transmits over the air. Single-file Flask app with a large single-page frontend.

## Repository layout
```
app.py                  Flask backend (~360KB) — all routes, CI-V, TTS, scheduling
templates/index.html    Single-page frontend (~530KB, ~11000 lines) — all UI, JS
INSTALL.sh              Debian installer / upgrade script
gunicorn_conf.py        Gunicorn config — filters noisy access logs
requirements.txt        Python dependencies
README.md               Full feature documentation
api_keys.py             API key manager (not committed — lives on server)
memory/                 Discord ingestion + Qdrant RAG pipeline
waterfall_image.py      Waterfall art encoder
chrome-extension/       MV3 Chrome extension: tab audio → ws /api/stream/tx → aplay + PTT
CLAUDE.md               This file — read on startup
```

## Server details (since v2.14.0: Docker on the GPU box)
- **Host:** root@192.168.40.15 (`rtx5070ti`, Debian 13). The IC-7610 USB cable is on this box.
- **Runs as:** Docker container `riggpt` from `/opt/riggpt` (`docker compose up -d --build`),
  bridge network, **port 5001** on the host (5000 is taken by hermitsdr). UI: http://192.168.40.15:5001
- **Host specifics:** `docker-compose.override.yml` (committed) — CP2102 port A (CI-V) mapped by by-id name
  → `/dev/ttyIC7610` (the app's first auto-connect candidate), port B → `/dev/ttyUSB1`, `/dev/snd`,
  `RIGGPT_AUDIO_DEVICE=plughw:CODEC` (ALSA card 3 "CODEC" = Burr-Brown PCM2901). Ollama is native on the host (`http://192.168.40.15:11434`), Qdrant in Docker (`:6333`).
- **Config files (bind-mounted, never in the image):**
  - `/opt/riggpt/data/config/app_settings.json` — all settings (container sees `/home/riggpt/`)
  - `/opt/riggpt/data/config/api_keys.json` — API credentials
  - `/opt/riggpt/data/sounds/` clips, `/opt/riggpt/data/wav_cache/` TX log audio
- **Old host:** root@radio (192.168.40.10) ran the systemd install (`INSTALL.sh`) up to v2.13.49; no longer the deploy target.

## Current version: v2.14.0

## Version sync rule — ALWAYS update all 6 on every version bump
1. `app.py` docstring header (`RigGPT vX.X.X`)
2. `app.py` `VERSION = 'vX.X.X'` constant
3. `requirements.txt` comment line 1
4. `INSTALL.sh` comment line 1 + `VERSION="X.X.X"` variable
5. `templates/index.html` `<span class="sb-label">vX.X.X</span>` in `#statusbar`
6. `Dockerfile` `LABEL ... version="X.X.X"`

## Deploy workflow
```bash
# On root@192.168.40.15, from /opt/riggpt:
git pull && docker compose up -d --build

# Check after deploy:
docker compose ps
docker compose logs -f --tail 50 riggpt
curl -s localhost:5001/api/status | head -c 200
```
(`INSTALL.sh` is the legacy systemd path; it is not used on the Docker host.)

## Working style
- Surgical edits only — never rewrite whole files
- Search before reading: `grep -n "pattern" app.py` before opening anything
- For large files use head/tail/grep — do NOT attempt full reads
- `index.html` is ~11000 lines — always grep for the exact anchor before editing
- Preserve existing code style throughout

## Large file warnings
- `index.html` (~530KB, ~11000 lines): grep only, never full read
- `app.py` (~360KB): grep only, never full read
- Both change frequently — always grep for exact text before any edit

## Tab structure (v2.14.0)
```
CONSOLE(1) WF ART(2) SSTV(3) SCHEDULE(4) LOG(5)
CONFIG(6) SYSTEM(7) API CFG(8) AI(9)  ACID TRIP(!)  CLIPS(0)  SPEC OPS(#)  SENTIENT(@)  DISCORD(&)  LIVE
```
- Pane IDs: `pane-dash`, `pane-wfall`, `pane-sstv`,
  `pane-sched`, `pane-hist`, `pane-cfg`, `pane-system`, `pane-apicfg`,
  `pane-ai`, `pane-trip`, `pane-clips`, `pane-specops`, `pane-sentient`, `pane-discord`, `pane-live`
- TABS constant in JS: `['dash','wfall','sstv','sched','hist','cfg','system','apicfg','ai','trip','clips','specops','sentient','discord','live']`
  (number keys use indices 0-8 only; the full list is for `#hash` restore on reload)
- LIVE tab = roger-beep engine + **BROWSER STREAM** card (status/meter/STOP + token, max-min, idle, VOX settings)

## Browser tab stream (v2.14.0)
- WebSocket `ws://host:5000/api/stream/tx` via `flask-sock` (gevent worker OK). Handler `_stream_run()`,
  state `_stream_state` under `_stream_lock`, abort via `_stream_kill()` (called by `/api/stream/stop`,
  `/api/tx/terminate` and `_heartbeat_kill_all`). Routes: `GET /api/stream/status`, `POST /api/stream/stop`.
- Protocol: text `{"type":"start",token,rate,channels,title}` → `{"type":"ok"}`; binary Int16LE PCM;
  server `{"type":"status",seconds,level,ptt}` 1/s; text `{"type":"stop"}`.
- Holds `_tx_exec_lock` + `_play_file_lock` for the whole stream; pauses `_poller_paused` only around PTT CI-V calls.
- Settings keys: `stream_token stream_max_min stream_idle_sec stream_vox_sec stream_vox_level` (in `SETTINGS_KEYS`).

## TX safety invariants (v2.14.0 bug sweep)
- Every path that keys PTT must hold `_tx_exec_lock` (execute, `_beacon_tx_file`, `_clips_play`, EVP, stream).
  Beacons and scheduled clips go through `_beacon_tx_file()`.
- `SETTINGS_KEYS` (module-level) is THE whitelist for both `POST /api/settings` and config import.
- CPU-bound encodes (pysstv, waterfall, whisper) go through `_cpu_offload()` so the single gevent worker keeps serving.
- Interval jobs use `IntervalTrigger(minutes=n)`, never `*/n` cron (breaks for n >= 60).
- CI-V levels (0x14) and meters (0x15) are BCD: use `set_level/read_level/read_meter`, never raw hi/lo bytes.
- TX controls are embedded in `pane-dash` (Console tab), not a separate pane
- BEACON was merged into SCHEDULE (50/50 split) in v2.13.43
- `pane-dub` (Trenchtown FX) was removed in v2.12.34; FX/pads live in Clips tab

## Key app.py patterns
- Settings: `POST /api/settings` with allowed-key whitelist → `app_settings.json`
- All new setting keys must be added to the `allowed` set in `api_settings_post()`
- State globals named with leading `_` (e.g. `_ghost_active`, `_pirate_job`)
- Routes follow `@app.route` + `def api_<name>():` naming
- New features need entries in `cfgFlushPresets()` JS AND `_restoreAllSettings()` JS

## Special Ops / Ghost-in-the-Machine
Routes:
- `POST /api/ghost/start {ghost, intensity, duration}` — start a ghost
- `POST /api/ghost/stop` — stop active ghost
- `GET /api/ghost/status` — {active, name, log}
- Ghost names: `poltergeist`, `passband`, `power_wobble`, `agc_seizure`, `split_personality`, `digital_ghost`, `exorcist`

Other Special Ops routes: `numbers_station`, `solar`, `mystery`, `autoid`, `pirate`, `voice_roulette`

## IcomSerialAgent — available CI-V methods
```python
agent.set_frequency(freq_hz)          # cmd 0x05
agent.set_mode(mode_name, filter_num) # cmd 0x06, filter 1/2/3
agent.set_level(sub, value)           # cmd 0x14 (AF=0x01, TX power=0x0A)
agent.set_function(sub, state)        # cmd 0x16
agent.set_split(state)                # cmd 0x0F
agent.set_vfo(vfo)                    # cmd 0x07 (A=0x00, B=0x01)
agent.vfo_swap()                      # cmd 0x07 0xB0
agent.vfo_a_to_b()                    # cmd 0x07 0xA0
agent.set_att(level)                  # cmd 0x11 (0/6/12/18 dB)
agent.set_preamp(level)               # cmd 0x16 0x02
agent.set_agc(mode)                   # cmd 0x16 0x12 (1=fast, 2=mid, 3=slow, 0=off)
agent.set_antenna(ant_num)            # cmd 0x12
agent.read_frequency()
agent.read_mode()
agent.read_rf_power()
agent.read_af_gain()
agent.read_alc()
agent.send_command(*bytes)            # raw CI-V
```

## Config persistence checklist
When adding any new user-facing input field, ALWAYS:
1. Add key to `allowed` set in `api_settings_post()` in `app.py`
2. Add to `cfgFlushPresets()` in `index.html` (the JS that saves on export/change)
3. Add to `_restoreAllSettings(s)` in `index.html` (the JS that restores on page load)

## Things to avoid
- Never read entire index.html or app.py without a grep first
- Never refactor unrelated code during a targeted fix
- Never commit with diverged version strings across the 5 locations
- Never touch `/home/riggpt/app_settings.json` or `api_keys.json` directly
