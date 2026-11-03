// AudioWorklet: downmix to mono, apply gain, convert to 16-bit PCM and post
// ~20 ms chunks (960 frames @ 48 kHz) to the main thread. Also reports a
// peak/RMS level every chunk so the popup can draw a meter.

const CHUNK_FRAMES = 960;

class PcmSender extends AudioWorkletProcessor {
  static get parameterDescriptors() {
    return [{ name: 'gain', defaultValue: 1.0, minValue: 0, maxValue: 4 }];
  }

  constructor() {
    super();
    this._buf = new Int16Array(CHUNK_FRAMES);
    this._pos = 0;
    this._sumsq = 0;
    this._peak = 0;
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const gainArr = parameters.gain;
    const nch = input.length;
    const n = input[0].length;
    for (let i = 0; i < n; i++) {
      let s = 0;
      for (let c = 0; c < nch; c++) s += input[c][i];
      s /= nch;
      const g = gainArr.length > 1 ? gainArr[i] : gainArr[0];
      s *= g;
      if (s > 1) s = 1; else if (s < -1) s = -1;
      const v = (s * 32767) | 0;
      this._buf[this._pos++] = v;
      this._sumsq += s * s;
      const a = s < 0 ? -s : s;
      if (a > this._peak) this._peak = a;
      if (this._pos >= CHUNK_FRAMES) {
        const out = this._buf.buffer.slice(0);
        this.port.postMessage({
          pcm: out,
          rms: Math.sqrt(this._sumsq / CHUNK_FRAMES),
          peak: this._peak,
        }, [out]);
        this._pos = 0; this._sumsq = 0; this._peak = 0;
      }
    }
    return true;
  }
}

registerProcessor('pcm-sender', PcmSender);
