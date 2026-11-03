// RigGPT Tab Audio → Radio — offscreen document.
//
// Runs getUserMedia on the tabCapture stream id, pushes the audio through an
// AudioWorklet that emits 16-bit mono PCM, and ships it to RigGPT over a
// WebSocket:  ws://<host>/api/stream/tx
//
// Wire protocol (see app.py api_stream_tx):
//   -> text  {"type":"start","token":..,"rate":48000,"channels":1,"title":..}
//   <- text  {"type":"ok"} | {"type":"error","message":..}
//   -> binary Int16LE PCM chunks (~20 ms each)
//   <- text  {"type":"status","seconds":n,"level":0-100,"ptt":bool}
//   -> text  {"type":"stop"}

const SAMPLE_RATE = 48000;
const MAX_BUFFERED = 192000;   // ~2 s of PCM; drop chunks beyond this (LAN hiccup)

let ctx = null, stream = null, src = null, gainNode = null, worklet = null;
let ws = null, wsReady = false;
let state = {
  running: false, title: '', host: '', started: 0,
  sent: 0, dropped: 0, level: 0, peak: 0,
  server: { seconds: 0, level: 0, ptt: false },
  error: '',
};

function reportEnded(reason) {
  state.error = state.error || reason;
  chrome.runtime.sendMessage({ target: 'background', type: 'ended', reason }).catch(() => {});
}

async function start(msg) {
  if (state.running) throw new Error('already running');
  state = { ...state, running: true, title: msg.title, host: msg.host, started: Date.now(),
            sent: 0, dropped: 0, level: 0, peak: 0, error: '',
            server: { seconds: 0, level: 0, ptt: false } };

  // 1. Open the WebSocket first so a refused connection fails fast.
  const url = (msg.host.startsWith('ws://') || msg.host.startsWith('wss://'))
    ? msg.host.replace(/\/+$/, '') + '/api/stream/tx'
    : 'ws://' + msg.host.replace(/^https?:\/\//, '').replace(/\/+$/, '') + '/api/stream/tx';
  await new Promise((resolve, reject) => {
    ws = new WebSocket(url);
    ws.binaryType = 'arraybuffer';
    const timer = setTimeout(() => { reject(new Error('RigGPT connection timed out')); try { ws.close(); } catch (_) {} }, 5000);
    ws.onopen = () => {
      ws.send(JSON.stringify({ type: 'start', token: msg.token || '', rate: SAMPLE_RATE,
                               channels: 1, title: msg.title }));
    };
    ws.onmessage = (ev) => {
      if (typeof ev.data !== 'string') return;
      let m; try { m = JSON.parse(ev.data); } catch (_) { return; }
      if (m.type === 'ok') { clearTimeout(timer); wsReady = true; resolve(); }
      else if (m.type === 'error') { clearTimeout(timer); reject(new Error(m.message || 'server refused')); }
      else if (m.type === 'status') { state.server = { seconds: m.seconds || 0, level: m.level || 0, ptt: !!m.ptt }; }
    };
    ws.onerror = () => { clearTimeout(timer); reject(new Error('Cannot reach RigGPT at ' + url)); };
    ws.onclose = (ev) => {
      wsReady = false;
      if (state.running) {
        const why = ev.reason || ('server closed (' + ev.code + ')');
        teardownAudio();
        state.running = false;
        reportEnded(why);
      }
    };
  });

  // 2. Capture the tab.
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        mandatory: { chromeMediaSource: 'tab', chromeMediaSourceId: msg.streamId },
      },
      video: false,
    });
  } catch (e) {
    try { ws.close(); } catch (_) {}
    throw new Error('tab capture failed: ' + (e.message || e));
  }
  stream.getAudioTracks().forEach(t => t.onended = () => { if (state.running) stop('tab audio ended'); });

  // 3. Audio graph: source → gain → worklet (PCM out); also → destination so
  //    the user keeps hearing the tab (tabCapture mutes it otherwise).
  ctx = new AudioContext({ sampleRate: SAMPLE_RATE });
  await ctx.audioWorklet.addModule('pcm-worklet.js');
  src = ctx.createMediaStreamSource(stream);
  gainNode = ctx.createGain();
  gainNode.gain.value = 1.0;
  worklet = new AudioWorkletNode(ctx, 'pcm-sender', { numberOfInputs: 1, numberOfOutputs: 0 });
  worklet.parameters.get('gain').value = Math.max(0, Math.min(4, (msg.gain || 100) / 100));
  src.connect(gainNode);
  gainNode.connect(worklet);
  if (msg.monitor !== false) src.connect(ctx.destination);
  worklet.port.onmessage = (ev) => {
    const { pcm, rms, peak } = ev.data;
    state.level = rms; state.peak = peak;
    if (!ws || !wsReady || ws.readyState !== WebSocket.OPEN) return;
    if (ws.bufferedAmount > MAX_BUFFERED) { state.dropped++; return; }
    ws.send(pcm);
    state.sent += pcm.byteLength;
  };
  await ctx.resume();
}

function teardownAudio() {
  try { if (worklet) { worklet.port.onmessage = null; worklet.disconnect(); } } catch (_) {}
  try { if (gainNode) gainNode.disconnect(); } catch (_) {}
  try { if (src) src.disconnect(); } catch (_) {}
  try { if (stream) stream.getTracks().forEach(t => t.stop()); } catch (_) {}
  try { if (ctx) ctx.close(); } catch (_) {}
  worklet = gainNode = src = stream = ctx = null;
}

async function stop(reason) {
  const wasRunning = state.running;
  state.running = false;
  teardownAudio();
  if (ws) {
    try { if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'stop' })); } catch (_) {}
    const w = ws; ws = null; wsReady = false;
    setTimeout(() => { try { w.close(1000, 'stopped'); } catch (_) {} }, 300);
  }
  if (wasRunning && reason !== 'user') reportEnded(reason);
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.target !== 'offscreen') return;
  (async () => {
    try {
      if (msg.type === 'start') { await start(msg); sendResponse({ ok: true }); }
      else if (msg.type === 'stop') { await stop(msg.reason || 'user'); sendResponse({ ok: true }); }
      else if (msg.type === 'status') { sendResponse({ ok: true, state }); }
      else if (msg.type === 'gain') {
        if (worklet) worklet.parameters.get('gain').value = Math.max(0, Math.min(4, (msg.gain || 100) / 100));
        sendResponse({ ok: true });
      }
      else if (msg.type === 'monitor') {
        if (src && ctx) { try { msg.on ? src.connect(ctx.destination) : src.disconnect(ctx.destination); } catch (_) {} }
        sendResponse({ ok: true });
      }
      else sendResponse({ ok: false, error: 'unknown' });
    } catch (e) {
      state.running = false;
      teardownAudio();
      sendResponse({ ok: false, error: e.message || String(e) });
    }
  })();
  return true;
});
