// RigGPT Tab Audio → Radio — service worker.
//
// Owns the lifecycle: popup asks us to start/stop, we obtain a tabCapture
// stream id for the active tab, hand it to the offscreen document (the only
// MV3 context that can run getUserMedia + AudioWorklet), and relay status.

const OFFSCREEN_URL = 'offscreen.html';

async function hasOffscreen() {
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ['OFFSCREEN_DOCUMENT'],
    documentUrls: [chrome.runtime.getURL(OFFSCREEN_URL)],
  });
  return contexts.length > 0;
}

async function ensureOffscreen() {
  if (await hasOffscreen()) return;
  await chrome.offscreen.createDocument({
    url: OFFSCREEN_URL,
    reasons: ['USER_MEDIA'],
    justification: 'Capture tab audio and stream PCM to the RigGPT server over WebSocket',
  });
}

async function closeOffscreen() {
  if (await hasOffscreen()) {
    try { await chrome.offscreen.closeDocument(); } catch (_) {}
  }
}

async function getSettings() {
  const d = await chrome.storage.local.get({
    host: '192.168.40.10:5000',
    token: '',
    gain: 100,
    monitor: true,
  });
  return d;
}

async function startCapture(tab) {
  const settings = await getSettings();
  // getMediaStreamId must run in the service worker (extension context); the
  // id is then consumed by getUserMedia in the offscreen document.
  const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
  await ensureOffscreen();
  const title = (tab.title || 'Chrome tab').slice(0, 120);
  const resp = await chrome.runtime.sendMessage({
    target: 'offscreen',
    type: 'start',
    streamId,
    title,
    host: settings.host,
    token: settings.token,
    gain: settings.gain,
    monitor: settings.monitor,
  });
  if (!resp || !resp.ok) {
    await closeOffscreen();
    throw new Error((resp && resp.error) || 'offscreen start failed');
  }
  await chrome.storage.session.set({
    active: true, tabId: tab.id, title, since: Date.now(),
  });
  chrome.action.setBadgeText({ text: 'TX' });
  chrome.action.setBadgeBackgroundColor({ color: '#ff3366' });
}

async function stopCapture(reason) {
  if (await hasOffscreen()) {
    try {
      await chrome.runtime.sendMessage({ target: 'offscreen', type: 'stop', reason });
    } catch (_) {}
  }
  await closeOffscreen();
  await chrome.storage.session.set({ active: false, tabId: null, title: '', since: 0 });
  chrome.action.setBadgeText({ text: '' });
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.target !== 'background') return;
  (async () => {
    try {
      if (msg.type === 'start') {
        const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
        if (!tab) throw new Error('No active tab');
        if (!/^https?:/.test(tab.url || '')) throw new Error('Only http(s) tabs can be captured');
        await startCapture(tab);
        sendResponse({ ok: true });
      } else if (msg.type === 'stop') {
        await stopCapture('user');
        sendResponse({ ok: true });
      } else if (msg.type === 'ended') {
        // Offscreen document reports the stream finished (server closed, tab
        // closed, error). Tear down so the badge/state don't go stale.
        await stopCapture(msg.reason || 'ended');
        sendResponse({ ok: true });
      } else {
        sendResponse({ ok: false, error: 'unknown message' });
      }
    } catch (e) {
      sendResponse({ ok: false, error: e.message || String(e) });
    }
  })();
  return true; // async sendResponse
});

// If the captured tab goes away, stop transmitting.
chrome.tabs.onRemoved.addListener(async (tabId) => {
  const s = await chrome.storage.session.get({ active: false, tabId: null });
  if (s.active && s.tabId === tabId) await stopCapture('tab closed');
});
