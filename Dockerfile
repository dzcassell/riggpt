# ─────────────────────────────────────────────────────────────
# RigGPT Docker Image
# AI ham radio transmission platform for Icom CI-V radios
# ─────────────────────────────────────────────────────────────
FROM python:3.12-slim-bookworm

LABEL maintainer="RigGPT" \
      description="AI ham radio platform — TTS, CI-V, Whisper, Acid Trip" \
      version="2.14.0"

# ── System packages ──────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    alsa-utils \
    espeak-ng \
    sox \
    libsox-fmt-all \
    ffmpeg \
    curl \
    usbutils \
    libopus0 \
    libffi-dev \
    libatomic1 \
    && rm -rf /var/lib/apt/lists/*
# libatomic1: pedalboard_native links libatomic.so.1; without it the FX agent
# silently falls back to the sox chain ("CPU may not support AVX2" is a red herring).
RUN true \
    && rm -rf /var/lib/apt/lists/*

# ── Create service user + persistent directories ─────────────
RUN useradd -m -d /home/riggpt -s /bin/bash riggpt \
    && usermod -aG audio,dialout,plugdev riggpt \
    && mkdir -p /opt/riggpt/wav_cache \
    && mkdir -p /home/riggpt/canon/a /home/riggpt/canon/b \
    && mkdir -p /sounds \
    && chown -R riggpt:riggpt /opt/riggpt /home/riggpt /sounds

WORKDIR /opt/riggpt

# ── Python dependencies ──────────────────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir pydub pedalboard scipy \
    && pip install --no-cache-dir 'discord.py[voice]' PyNaCl \
    && echo "Core deps installed"

# Optional: faster-whisper for SENTIENT tab (uncomment to include)
# Adds ~300MB to image. Users can also install at runtime via exec.
# RUN pip install --no-cache-dir faster-whisper

# ── Copy application ─────────────────────────────────────────
COPY app.py api_keys.py gunicorn_conf.py waterfall_image.py ./
COPY templates/ templates/
COPY memory/ memory/
COPY INSTALL.sh UNINSTALL.sh README.md CLAUDE.md ./

RUN chown -R riggpt:riggpt /opt/riggpt

# ── Volumes ──────────────────────────────────────────────────
# Persistent config (survives container rebuilds)
VOLUME ["/home/riggpt"]
# Clips / sound files
VOLUME ["/sounds"]

# ── Environment ──────────────────────────────────────────────
ENV PYTHONUNBUFFERED=1 \
    RIGGPT_DOCKER=1

# ── Expose ───────────────────────────────────────────────────
EXPOSE 5000

# ── Entrypoint ───────────────────────────────────────────────
# Run as root so we can access /dev/ttyUSB* and /dev/snd/*
# (the container is hardware-bound anyway)
CMD ["gunicorn", \
     "--config", "gunicorn_conf.py", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "1", \
     "--worker-class", "gevent", \
     "--timeout", "300", \
     "app:app"]
