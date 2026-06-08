#!/bin/bash
# RigGPT v2.13.48 -- Installer
# Tested: Debian 13 (trixie) amd64, Python 3.13, x86_64
set -e

INSTALL_DIR="/opt/riggpt"
SERVICE="riggpt"
SVC_USER="riggpt"
SVC_HOME="/home/riggpt"          # persistent home; NOT removed on uninstall
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="2.13.48"

# -- Parse flags ------------------------------------------------
# -y / --yes  : skip upgrade confirmation prompt (for scripted installs)
YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) YES=1 ;;
    esac
done

echo "=============================================="
echo "  RigGPT v${VERSION} -- Installer"
echo "=============================================="

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Please run as root: sudo bash $0"
    exit 1
fi

# -- Upgrade detection ------------------------------------------
# Detect an existing installation by checking:
#   1. A running or enabled systemd service unit
#   2. An app.py already present in INSTALL_DIR
# If found, show installed vs incoming version and ask to confirm.

INSTALLED_VERSION=""
IS_UPGRADE=0

# Extract the RUNNING version -- NOT from app.py (which git pull already
# overwrote) but from the live service API or the systemd unit description,
# both of which reflect what was running before this upgrade started.
#
# Strategy (in order of preference):
#   1. Ask the running service via HTTP (most reliable)
#   2. Read the Description= line from the active systemd unit (set at last install)
#   3. Read from the git reflog / previous commit's app.py (git-based installs)
#   4. Give up and show 'unknown'

if curl -s --max-time 3 "http://localhost:5000/api/status" 2>/dev/null \
        | grep -o '"version":"[^"]*"' | head -1 | grep -q 'version'; then
    INSTALLED_VERSION=$(
        curl -s --max-time 3 "http://localhost:5000/api/status" 2>/dev/null \
        | grep -o '"version":"[^"]*"' | head -1 \
        | sed 's/"version":"//;s/"//'
    )
elif systemctl is-active --quiet "$SERVICE" 2>/dev/null || true; then
    # Try reading from systemd unit Description (e.g. "RigGPT v2.12.36")
    INSTALLED_VERSION=$(
        systemctl show "$SERVICE" --property=Description 2>/dev/null \
        | grep -o 'v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' | head -1
    )
elif [ -d "$INSTALL_DIR/.git" ]; then
    # Git-based install: read VERSION from the previous commit's app.py
    INSTALLED_VERSION=$(
        git -C "$INSTALL_DIR" show HEAD~1:app.py 2>/dev/null \
        | grep -m1 "^VERSION" | sed "s/.*'\(.*\)'.*/\1/" || echo ""
    )
fi

# Check whether the systemd unit exists (even if stopped)
SVC_EXISTS=0
if systemctl list-unit-files "${SERVICE}.service" 2>/dev/null \
        | grep -q "${SERVICE}.service"; then
    SVC_EXISTS=1
fi

if [ -n "$INSTALLED_VERSION" ] || [ "$SVC_EXISTS" -eq 1 ]; then
    IS_UPGRADE=1
    echo ""
    echo "  !! EXISTING INSTALLATION DETECTED !!"
    echo ""
    if [ -n "$INSTALLED_VERSION" ]; then
        echo "  Installed version : $INSTALLED_VERSION"
    else
        echo "  Installed version : unknown (app.py not found in $INSTALL_DIR)"
    fi
    echo "  Incoming version  : v${VERSION}"
    echo ""

    SVC_STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "inactive")
    echo "  Service status    : $SVC_STATUS"
    echo ""
    echo "  The upgrade will:"
    echo "    - Stop the running service"
    echo "    - Replace app.py, templates, and support files"
    echo "    - Reinstall Python dependencies"
    echo "    - Restart the service"
    echo ""
    echo "  Your config is SAFE -- these files are never touched:"
    echo "    $SVC_HOME/app_settings.json"
    echo "    $SVC_HOME/api_keys.json"
    echo "    $SVC_HOME/canon/"
    echo ""

    if [ "$YES" -eq 0 ]; then
        read -r -p "  Proceed with upgrade? [y/N] " CONFIRM
        case "$CONFIRM" in
            [yY][eE][sS]|[yY]) ;;
            *)
                echo ""
                echo "  Upgrade cancelled. No changes were made."
                exit 0
                ;;
        esac
    else
        echo "  --yes flag set -- proceeding automatically."
    fi
    echo ""
fi

# -- System package prerequisites ───────────────────────────────
echo "[1/7] Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
    python3 python3-pip alsa-utils ffmpeg sox espeak-ng curl libopus0 libffi-dev \
    psmisc lsof \
    2>/dev/null || echo "  WARNING: some apt packages failed (continuing)"

# -- Service user + persistent home ─────────────────────────────
echo "[2/7] Creating service user..."
if ! id "$SVC_USER" &>/dev/null; then
    # useradd -m creates home dir; -d sets path; NOT -r so home is a real user home
    useradd -m -d "$SVC_HOME" -s /bin/false "$SVC_USER"
    echo "  Created user: $SVC_USER (home: $SVC_HOME)"
else
    echo "  User $SVC_USER already exists"
    if [ ! -d "$SVC_HOME" ]; then
        mkdir -p "$SVC_HOME"
        chown "$SVC_USER:$SVC_USER" "$SVC_HOME"
        chmod 750 "$SVC_HOME"
        echo "  Created missing home: $SVC_HOME"
    fi
fi

for grp in dialout audio plugdev; do
    if getent group "$grp" &>/dev/null; then
        usermod -aG "$grp" "$SVC_USER" 2>/dev/null && echo "  Added $SVC_USER to: $grp" || true
    fi
done

# -- Stop existing service ──────────────────────────────────────
echo "[3/7] Stopping existing service (if any)..."
for f in "$INSTALL_DIR/gunicorn.ctl" "$INSTALL_DIR/gunicorn.pid" "$INSTALL_DIR/gunicorn.sock"; do
    [ -f "$f" ] && rm -f "$f" && echo "  Cleaned: $f"
done
systemctl stop "$SERVICE" 2>/dev/null || true
sleep 1

# ── Aggressively free port 5000 ──
# Multiple strategies to ensure nothing holds the port.
# All commands wrapped in `timeout` to prevent hangs.

_list_port_pids() {
    # Collect ALL PIDs holding port 5000 from multiple sources
    # Each command gets a 3-second timeout to prevent hangs
    {
        timeout 3 ss -tlnp 'sport = :5000' 2>/dev/null | grep -oP 'pid=\K[0-9]+' || true
        timeout 3 lsof -ti :5000 2>/dev/null || true
        timeout 3 fuser 5000/tcp 2>/dev/null | tr -s ' ' '\n' | grep -oP '[0-9]+' || true
    } | sort -un | grep -v '^$' || true
}

# Round 1: SIGTERM all holders
PORT_PIDS=$(_list_port_pids)
if [ -n "$PORT_PIDS" ]; then
    echo "  Port 5000 held by PID(s): $(echo $PORT_PIDS | tr '\n' ' ')"
    for pid in $PORT_PIDS; do
        cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
        echo "  SIGTERM → PID $pid ($cmd)"
        kill "$pid" 2>/dev/null || true
    done
    # Wait up to 5s for graceful shutdown
    for _w in $(seq 1 10); do
        sleep 0.5
        PORT_PIDS=$(_list_port_pids)
        [ -z "$PORT_PIDS" ] && break
    done
fi

# Round 2: SIGKILL any survivors
PORT_PIDS=$(_list_port_pids)
if [ -n "$PORT_PIDS" ]; then
    echo "  Still held after SIGTERM — escalating to SIGKILL"
    for pid in $PORT_PIDS; do
        echo "  SIGKILL → PID $pid"
        kill -9 "$pid" 2>/dev/null || true
    done
    sleep 1
fi

# Round 3: fuser -k (kernel-level kill, catches everything)
if command -v fuser &>/dev/null; then
    timeout 3 fuser -k 5000/tcp 2>/dev/null || true
    sleep 0.5
fi

# Round 4: pkill patterns for common holders
pkill -9 -f "gunicorn.*app:app" 2>/dev/null || true
pkill -9 -f "gunicorn.*5000" 2>/dev/null || true
pkill -9 -f "python.*app.py" 2>/dev/null || true
sleep 0.5

# Final verification
PORT_PIDS=$(_list_port_pids)
if [ -n "$PORT_PIDS" ]; then
    echo ""
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║  ERROR: Port 5000 STILL held after all kill   ║"
    echo "  ║  attempts. Remaining PID(s):                  ║"
    for pid in $PORT_PIDS; do
        cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
        printf "  ║  PID %-6s %s\n" "$pid" "${cmd:0:36}"
    done
    echo "  ║                                               ║"
    echo "  ║  Try: sudo kill -9 $PORT_PIDS                ║"
    echo "  ║  Then re-run: bash INSTALL.sh                 ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo ""
    exit 1
fi
echo "  Port 5000 is free ✓"

# -- Install directory ──────────────────────────────────────────
echo "[4/7] Installing files to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/templates"
mkdir -p "$INSTALL_DIR/wav_cache"

# Only copy files if SCRIPT_DIR differs from INSTALL_DIR.
# If the user cloned directly into INSTALL_DIR and ran the script from there,
# the files are already in place -- skip the cp to avoid 'same file' errors.
if [ "$(realpath "$SCRIPT_DIR")" != "$(realpath "$INSTALL_DIR")" ]; then
    cp "$SCRIPT_DIR/app.py"               "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/templates/index.html" "$INSTALL_DIR/templates/"
    [ -f "$SCRIPT_DIR/waterfall_image.py" ] && cp "$SCRIPT_DIR/waterfall_image.py" "$INSTALL_DIR/"
    [ -f "$SCRIPT_DIR/api_keys.py" ]        && cp "$SCRIPT_DIR/api_keys.py"        "$INSTALL_DIR/"
    [ -f "$SCRIPT_DIR/requirements.txt" ]   && cp "$SCRIPT_DIR/requirements.txt"   "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/UNINSTALL.sh" "$INSTALL_DIR/"
else
    echo "  Files already in $INSTALL_DIR (cloned in-place) -- skipping copy"
fi
chmod +x "$INSTALL_DIR/UNINSTALL.sh"

# Persistent home: set ownership only, NEVER wipe (survives reinstall)
chown "$SVC_USER:$SVC_USER" "$SVC_HOME"
chmod 750 "$SVC_HOME"

chown -R "$SVC_USER:dialout" "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# -- Python dependencies ────────────────────────────────────────
echo "[5/7] Installing Python dependencies..."
pip3 install \
    flask flask-cors pyserial requests apscheduler pysstv pillow numpy \
    psutil edge-tts gtts pyttsx3 gunicorn gevent pydub pedalboard scipy \
    'discord.py[voice]' PyNaCl \
    --break-system-packages -q --root-user-action=ignore 2>&1 | grep -v "^$" || true

echo "  Note: Coqui TTS (optional ~2GB): pip3 install TTS --break-system-packages"
echo "  Note: Piper TTS (optional): see https://github.com/rhasspy/piper/releases"

AUDIO_DEV=$(python3 -c "
import subprocess
r = subprocess.run(['aplay','-l'], capture_output=True, text=True, timeout=5)
PREFER=['burr-brown','burr brown','08bb','pcm2901','usb audio codec']
SKIP=['pch','hda intel','hdmi','analog','digital','nvidia','amd']
best_card,best_score=None,-1
for line in r.stdout.splitlines():
    if not line.startswith('card '): continue
    low=line.lower()
    if any(k in low for k in SKIP): continue
    try: card_num=int(line.split(':')[0].replace('card','').strip())
    except: continue
    score=10 if any(k in low for k in PREFER) else 5
    if score>best_score: best_score,best_card=score,card_num
print(f'plughw:{best_card},0' if best_card is not None else 'default')
" 2>/dev/null || echo "default")
echo "  Detected audio device: $AUDIO_DEV"

python3 -c "import gevent; import gevent.monkey" 2>/dev/null && \
    echo "  gevent: OK" || \
    echo "  WARNING: gevent import failed -- try: apt-get install -y python3-gevent libev-dev"

# -- Systemd unit ───────────────────────────────────────────────
echo "[6/7] Installing systemd service..."

GUNICORN_BIN=$(command -v gunicorn 2>/dev/null || echo "")
if [ -z "$GUNICORN_BIN" ]; then
    for candidate in /usr/local/bin/gunicorn /usr/bin/gunicorn "$HOME/.local/bin/gunicorn"; do
        [ -x "$candidate" ] && GUNICORN_BIN="$candidate" && break
    done
fi
if [ -z "$GUNICORN_BIN" ]; then
    echo "  WARNING: gunicorn not found -- falling back to python3 app.py"
    EXEC_START="/usr/bin/python3 ${INSTALL_DIR}/app.py"
else
    echo "  Found gunicorn: $GUNICORN_BIN"
    EXEC_START="${GUNICORN_BIN} --config gunicorn_conf.py --worker-class gevent --workers 1 --bind 0.0.0.0:5000 --timeout 300 --keep-alive 5 --log-level info --access-logfile - --error-logfile - app:app"
fi

cat > /etc/systemd/system/${SERVICE}.service << EOF
[Unit]
Description=RigGPT v${VERSION}
After=network.target sound.target
Wants=network.target

[Service]
Type=simple
User=${SVC_USER}
Group=dialout
SupplementaryGroups=audio plugdev
WorkingDirectory=${INSTALL_DIR}
Environment="RIGGPT_AUDIO_DEVICE=${AUDIO_DEV}"
Environment="HOME=${SVC_HOME}"
Environment="PULSE_SERVER="
Environment="ALSA_CONFIG_PATH=/usr/share/alsa/alsa.conf"
ExecStart=${EXEC_START}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=riggpt
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE"

# -- Start and verify ───────────────────────────────────────────
echo "[7/7] Starting service..."
for f in "$INSTALL_DIR/gunicorn.ctl" "$INSTALL_DIR/gunicorn.pid"; do
    [ -f "$f" ] && rm -f "$f" && echo "  Cleaned: $f"
done
chown -R "$SVC_USER:dialout" "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

echo "  Testing Python import as $SVC_USER..."
su -s /bin/bash -c "cd $INSTALL_DIR && python3 -c 'import app' 2>&1 | head -20" "$SVC_USER" \
    && echo "  Import OK" || echo "  WARNING: import test had issues (may still work)"

systemctl start "$SERVICE"

for i in $(seq 1 10); do
    sleep 1
    STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "unknown")
    [ "$STATUS" = "active" ] && break
done

echo -n "  Waiting for HTTP port 5000"
BOUND=0
for i in $(seq 1 30); do
    sleep 2; echo -n "."
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
           "http://localhost:5000/api/status" 2>/dev/null || echo "0")
    [ "$CODE" = "200" ] && BOUND=1 && break
    # Every 10s, show what's happening
    if [ $((i % 5)) -eq 0 ]; then
        SVC_STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "unknown")
        PORT_PID=$(ss -tlnp 'sport = :5000' 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1)
        if [ "$SVC_STATUS" != "active" ]; then
            echo ""
            echo "  Service status: $SVC_STATUS (not running)"
            echo "  Check logs: journalctl -u $SERVICE -n 30 --no-pager"
            break
        elif [ -n "$PORT_PID" ]; then
            echo " [bound by PID $PORT_PID, waiting for /api/status]"
            echo -n "  "
        fi
    fi
done
echo ""

if [ "$BOUND" = "0" ]; then
    echo "  WARNING: port 5000 did not respond within 60s"
    journalctl -u "$SERVICE" -n 40 --no-pager 2>/dev/null || true
fi

STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "unknown")
echo ""
echo "=============================================="
if [ "$IS_UPGRADE" -eq 1 ]; then
    if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "v${VERSION}" ]; then
        echo "  Upgrade complete: ${INSTALLED_VERSION} -> v${VERSION}"
    else
        echo "  Reinstall / same version: v${VERSION}"
    fi
else
    echo "  Fresh install complete: v${VERSION}"
fi
echo "  Service status:      $STATUS"
echo "  Persistent config:   $SVC_HOME/"
echo "    (app_settings.json, api_keys.json, canon/ never touched by installer)"
echo "=============================================="

if [ "$STATUS" = "active" ]; then
    IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "  Access:    http://${IP}:5000"
    echo "  Logs:      journalctl -u $SERVICE -f"
    echo "  Restart:   systemctl restart $SERVICE"
    echo "  Uninstall: sudo bash $INSTALL_DIR/UNINSTALL.sh"
    echo ""
    echo "  Route check:"
    for ep in /api/status /api/system/health /api/ai/config; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
               "http://localhost:5000${ep}" 2>/dev/null || echo "ERR")
        echo "    GET  $ep -> HTTP $CODE  $([ "$CODE" = "200" ] && echo OK || echo FAIL)"
    done
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
           -H "Content-Type: application/json" \
           -d '{"text":"radio check"}' --max-time 15 \
           "http://localhost:5000/api/transmit/preview" 2>/dev/null || echo "ERR")
    echo "    POST /api/transmit/preview -> HTTP $CODE  $([ "$CODE" = "200" ] && echo OK || echo '(eSpeak may not be installed)')"
else
    echo "  WARNING: service did not start"
    journalctl -u "$SERVICE" -n 20 --no-pager 2>/dev/null || true
fi
echo "=============================================="
