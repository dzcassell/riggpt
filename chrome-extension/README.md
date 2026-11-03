# RigGPT Tab Audio → Radio (Chrome extension)

Streams the audio of the Chrome tab you are looking at (YouTube, SoundCloud,
anything that plays sound) to a RigGPT server on your LAN. RigGPT keys the
IC-7610 over CI-V and plays the audio into its USB codec, so whatever the tab
plays goes out over the air. Because it captures the tab itself, your normal
Chrome login (YouTube Premium, age-restricted videos, playlists) just works.

```
Chrome tab ──tabCapture──▶ offscreen doc (AudioWorklet, 48 kHz mono PCM)
          ──WebSocket ws://radio:5000/api/stream/tx──▶ RigGPT
          ──aplay (USB codec) + CI-V PTT──▶ IC-7610
```

## Install (unpacked)

1. On the RigGPT host, pull v2.14.0+ and redeploy (`docker compose up -d --build`
   on the Docker host, or `bash INSTALL.sh` for a systemd install). Both pull
   in the `flask-sock` dependency.
2. In Chrome open `chrome://extensions`, turn on **Developer mode**, click
   **Load unpacked** and pick this `chrome-extension/` folder.
3. Pin the extension. Click it, set **RigGPT host** to your server
   (default `192.168.40.15:5001`). If you set a token in RigGPT
   (LIVE tab → BROWSER STREAM → Token), enter the same token here.

## Use

1. Open the YouTube tab you want to transmit and start playback.
2. Click the extension → **▶ TRANSMIT THIS TAB**. The badge shows `TX`,
   RigGPT keys PTT, and the LIVE tab shows `🔴 ON AIR` with a level meter.
3. **■ STOP** in the popup, **■ STOP** in RigGPT's LIVE tab, **PTT OFF**,
   **TERM TX** or `Ctrl+.` all end the stream and drop PTT.

The popup's **Gain** slider scales the audio before it is sent; keep the
RigGPT ALC meter (SYSTEM tab) out of the red. **Keep playing audio locally**
lets you hear the tab while it transmits (tab capture mutes it otherwise).

## Safety behaviour (server side, LIVE tab settings)

| Setting   | Default | Effect |
|-----------|---------|--------|
| Max TX    | 30 min  | Hard limit per stream; PTT drops and the stream ends. |
| Idle      | 5 s     | No audio frames from the browser for this long → stream ends. |
| VOX drop  | 4 s     | Near-silence (below the % level) for this long → PTT released; re-keys when audio returns. `0` disables. |
| Token     | blank   | Shared secret; anyone on the LAN who can reach port 5000 can otherwise transmit. |

PTT also drops if the WebSocket closes, the tab is closed, `aplay` exits,
or RigGPT's dead-man heartbeat fires. Only one transmission can hold the
radio at a time: the stream is refused while TTS, a clip or a beacon is
playing, and vice-versa.

## Regulatory note

You are the control operator. Music and rebroadcast of third-party audio
are restricted on amateur frequencies (Part 97 in the US); keep Auto-ID
running during long streams and only transmit what you are permitted to.
