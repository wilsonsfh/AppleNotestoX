// Text-to-speech via the Web Speech API. Degrades gracefully when unavailable.
// Works from file://. Safari requires speech to start from a user gesture.
(function (global) {
  "use strict";

  var synth = global.speechSynthesis;
  var voicesCache = [];

  function available() {
    return !!synth && typeof global.SpeechSynthesisUtterance !== "undefined";
  }

  // getVoices() can be empty until 'voiceschanged' fires (Chrome). Resolve robustly.
  function loadVoices() {
    return new Promise(function (resolve) {
      if (!available()) return resolve([]);
      var v = synth.getVoices();
      if (v && v.length) { voicesCache = v; return resolve(v); }
      var done = false;
      function finish() {
        if (done) return;
        done = true;
        voicesCache = synth.getVoices() || [];
        resolve(voicesCache);
      }
      try { synth.addEventListener("voiceschanged", finish, { once: true }); } catch (e) {}
      setTimeout(finish, 1000); // fallback if the event never fires
    });
  }

  function pickVoice() {
    var v = voicesCache.length ? voicesCache : (available() ? synth.getVoices() : []);
    return (
      v.find(function (x) { return /^en[-_]/i.test(x.lang) && x.localService; }) ||
      v.find(function (x) { return /^en/i.test(x.lang); }) ||
      v[0] || null
    );
  }

  // speak(text, { rate, pitch, onend, onerror }) -> utterance | undefined
  function speak(text, opts) {
    opts = opts || {};
    if (!available() || !text) { if (opts.onend) opts.onend(); return; }
    synth.cancel();
    var u = new global.SpeechSynthesisUtterance(String(text));
    u.rate = opts.rate || 1;
    u.pitch = opts.pitch || 1;
    var voice = pickVoice();
    if (voice) u.voice = voice;
    if (opts.onend) u.addEventListener("end", opts.onend);
    if (opts.onerror) u.addEventListener("error", opts.onerror);
    synth.speak(u);
    return u;
  }

  function pause() { if (available()) try { synth.pause(); } catch (e) {} }
  function resume() { if (available()) try { synth.resume(); } catch (e) {} }
  function cancel() { if (available()) try { synth.cancel(); } catch (e) {} }

  function reducedMotion() {
    return !!(global.matchMedia && global.matchMedia("(prefers-reduced-motion: reduce)").matches);
  }

  global.TTS = {
    available: available,
    loadVoices: loadVoices,
    speak: speak,
    pause: pause,
    resume: resume,
    cancel: cancel,
    reducedMotion: reducedMotion,
  };
})(typeof window !== "undefined" ? window : globalThis);
