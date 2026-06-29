// Spaced repetition (SM-2) + localStorage persistence.
// Classic script: attaches `SRS` to the global (window in browser, globalThis in node tests).
(function (global) {
  "use strict";

  var DAY_MS = 86400000;
  var STORE_KEY = "wikiReview.srs.v1";

  // Again / Hard / Good / Easy  ->  SM-2 quality
  var GRADE_Q = { again: 1, hard: 3, good: 4, easy: 5 };

  // Faithful SM-2 update. Returns a fresh card-state object.
  function review(state, q, now) {
    now = now == null ? Date.now() : now;
    var ef = state && state.ef != null ? state.ef : 2.5;
    var n = state && state.n != null ? state.n : 0;
    var interval = state && state.interval != null ? state.interval : 0;

    ef = Math.max(1.3, ef + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)));

    if (q < 3) {
      n = 0;
      interval = 1; // lapse: re-show tomorrow (within-session requeue handled by the view)
    } else {
      n += 1;
      if (n === 1) interval = 1;
      else if (n === 2) interval = 6;
      else interval = Math.ceil(interval * ef);
    }
    return { ef: ef, n: n, interval: interval, due: now + interval * DAY_MS, lastReviewed: now };
  }

  // Interval (in whole days) that a given grade would schedule, from current state.
  function previewDays(state, grade) {
    var q = GRADE_Q[grade];
    return review(state || {}, q, 0).interval;
  }

  // Human label for a grade button.
  function previewLabel(state, grade) {
    if (grade === "again") return "<1m";
    var d = previewDays(state, grade);
    return d === 1 ? "1d" : d + "d";
  }

  function isDue(state, now) {
    now = now == null ? Date.now() : now;
    if (!state || state.due == null) return true; // never reviewed -> due
    return state.due <= now;
  }

  // --- persistence (browser only; no-ops degrade gracefully) ----------------
  function readAll() {
    try {
      return JSON.parse(global.localStorage.getItem(STORE_KEY) || "{}") || {};
    } catch (e) {
      return {};
    }
  }
  function writeAll(map) {
    try {
      global.localStorage.setItem(STORE_KEY, JSON.stringify(map));
    } catch (e) {
      /* storage unavailable (private mode / file:// quirks) — session-only */
    }
  }
  function load(id) {
    return readAll()[id] || null;
  }
  function save(id, state) {
    var all = readAll();
    all[id] = state;
    writeAll(all);
  }

  // Split cards into due vs scheduled given persisted state.
  function partition(cards, now) {
    now = now == null ? Date.now() : now;
    var all = readAll();
    var due = [];
    var scheduled = 0;
    for (var i = 0; i < cards.length; i++) {
      if (isDue(all[cards[i].id], now)) due.push(cards[i]);
      else scheduled++;
    }
    return { due: due, scheduled: scheduled };
  }

  // Best-effort daily streak tracking (separate key).
  function bumpStreak(now) {
    now = now == null ? Date.now() : now;
    var KEY = "wikiReview.streak.v1";
    var rec;
    try { rec = JSON.parse(global.localStorage.getItem(KEY) || "null"); } catch (e) { rec = null; }
    var today = new Date(now); today.setHours(0, 0, 0, 0);
    var todayMs = today.getTime();
    if (!rec) rec = { count: 1, last: todayMs };
    else if (rec.last === todayMs) { /* already counted today */ }
    else if (todayMs - rec.last === DAY_MS) { rec.count += 1; rec.last = todayMs; }
    else { rec.count = 1; rec.last = todayMs; }
    try { global.localStorage.setItem(KEY, JSON.stringify(rec)); } catch (e) {}
    return rec.count;
  }
  function currentStreak(now) {
    now = now == null ? Date.now() : now;
    var KEY = "wikiReview.streak.v1";
    var rec;
    try { rec = JSON.parse(global.localStorage.getItem(KEY) || "null"); } catch (e) { rec = null; }
    if (!rec) return 0;
    var today = new Date(now); today.setHours(0, 0, 0, 0);
    var diff = today.getTime() - rec.last;
    if (diff === 0 || diff === DAY_MS) return rec.count;
    return 0; // streak broken
  }

  global.SRS = {
    GRADE_Q: GRADE_Q,
    review: review,
    previewDays: previewDays,
    previewLabel: previewLabel,
    isDue: isDue,
    load: load,
    save: save,
    partition: partition,
    bumpStreak: bumpStreak,
    currentStreak: currentStreak,
    _DAY_MS: DAY_MS,
  };
})(typeof window !== "undefined" ? window : globalThis);
