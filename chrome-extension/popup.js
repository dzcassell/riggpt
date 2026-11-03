const $ = (id) => document.getElementById(id);
let pollTimer = null;

async function loadSettings() {
  const s = await chrome.storage.local.get({ host: '192.168.40.15:5001', token: '', gain: 100, monitor: true });
  $('host').value = s.host;
  $('token').value = s.token;
  $('gain').value = s.gain;
  $('gain-v').textContent = s.gain + '%';
  $('monitor').checked = !!s.monitor;
}

function saveSettings() {
  return chrome.storage.local.set({
    host: $('host').value.trim(),
    token: $('token').value,
    gain: parseInt($('gain').value, 10) || 100,
    monitor: $('monitor').checked,
  });
}

function fmt(sec) {
  sec = Math.max(0, Math.floor(sec));
  return String(Math.floor(sec / 60)).padStart(2, '0') + ':' + String(sec % 60).padStart(2, '0');
}

function setRunning(on, title) {
  $('start').disabled = on;
  $('stop').disabled = !on;
  $('host').disabled = on;
  $('token').disabled = on;
  $('tab-title').textContent = on && title ? '▶ ' + title : '';
  if (!on) { $('meter').style.width = '0'; }
}

async function refresh() {
  const sess = await chrome.storage.session.get({ active: false, title: '', since: 0 });
  setRunning(sess.active, sess.title);
  if (!sess.active) {
    if (!$('status').dataset.err) $('status').textContent = 'idle';
    return;
  }
  let st = null;
  try {
    const r = await chrome.runtime.sendMessage({ target: 'offscreen', type: 'status' });
    if (r && r.ok) st = r.state;
  } catch (_) {}
  if (!st) { $('status').textContent = 'starting…'; return; }
  const pct = Math.min(100, Math.round(st.peak * 100));
  $('meter').style.width = pct + '%';
  const elapsed = (Date.now() - (sess.since || Date.now())) / 1000;
  $('status').innerHTML =
    `<b>${st.server.ptt ? 'ON AIR' : 'connected'}</b>  ${fmt(elapsed)}  ·  radio level ${st.server.level | 0}%` +
    `\nsent ${(st.sent / 1024 | 0)} KB` + (st.dropped ? `  ·  dropped ${st.dropped} chunks` : '');
}

$('start').addEventListener('click', async () => {
  delete $('status').dataset.err;
  await saveSettings();
  $('status').textContent = 'connecting…';
  $('start').disabled = true;
  const r = await chrome.runtime.sendMessage({ target: 'background', type: 'start' });
  if (!r || !r.ok) {
    $('status').innerHTML = `<span class="err">${(r && r.error) || 'failed'}</span>`;
    $('status').dataset.err = '1';
    $('start').disabled = false;
    return;
  }
  refresh();
});

$('stop').addEventListener('click', async () => {
  $('stop').disabled = true;
  await chrome.runtime.sendMessage({ target: 'background', type: 'stop' });
  $('status').textContent = 'stopped';
  refresh();
});

$('gain').addEventListener('input', async () => {
  $('gain-v').textContent = $('gain').value + '%';
  await saveSettings();
  chrome.runtime.sendMessage({ target: 'offscreen', type: 'gain', gain: parseInt($('gain').value, 10) }).catch(() => {});
});

$('monitor').addEventListener('change', async () => {
  await saveSettings();
  chrome.runtime.sendMessage({ target: 'offscreen', type: 'monitor', on: $('monitor').checked }).catch(() => {});
});

for (const id of ['host', 'token']) $(id).addEventListener('change', saveSettings);

loadSettings().then(() => {
  refresh();
  pollTimer = setInterval(refresh, 500);
});
