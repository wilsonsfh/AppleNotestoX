// Recap view: auto-advancing narrated slides (TTS) — the "video-like" multimodal recap.
(function (g) {
  "use strict";

  function slidesForConcept(c) {
    var UI = g.UI, DATA = g.DATA;
    var slides = [{ eyebrow: c.type, title: c.title, body: c.summary || "No summary captured yet." }];
    var nbrs = DATA.neighbors(c.id).map(function (id) { return (DATA.conceptById[id] || {}).title || id; });
    if (nbrs.length) slides.push({ eyebrow: "Connected to", title: c.title, body: "Related concepts: " + nbrs.join(", ") + "." });
    return slides;
  }

  function buildSlides(concepts) {
    var out = [];
    concepts.forEach(function (c) { out = out.concat(slidesForConcept(c)); });
    return out;
  }

  function render(container, opts) {
    var UI = g.UI, DATA = g.DATA, TTS = g.TTS, el = UI.el;
    opts = opts || {};
    var reduced = TTS && TTS.reducedMotion ? TTS.reducedMotion() : false;

    var slides = [], index = 0, playing = false, cleanupFns = [];

    function cleanup() { if (TTS) TTS.cancel(); cleanupFns.forEach(function (f) { f(); }); }

    function startPlayer(slideList, heading) {
      slides = slideList; index = 0; playing = false;
      drawPlayer(heading);
      // Auto-start narration (this render path is reached via a user gesture: button click).
      play();
    }

    function play() {
      if (!slides.length) return;
      playing = true;
      drawPlayer();
      narrate();
    }
    function pause() { playing = false; if (TTS) TTS.cancel(); drawPlayer(); }

    function narrate() {
      var s = slides[index];
      if (!s) return;
      if (TTS && TTS.available()) {
        TTS.speak(s.title + ". " + s.body, {
          onend: function () { if (playing) next(true); },
        });
      }
    }
    function next(auto) {
      if (index < slides.length - 1) { index++; if (playing) { drawPlayer(); narrate(); } else drawPlayer(); }
      else { playing = false; if (TTS) TTS.cancel(); drawPlayer(); }
      if (!auto && playing) { /* manual nav already handled */ }
    }
    function prev() {
      if (index > 0) { index--; drawPlayer(); if (playing) narrate(); }
    }

    function drawPlayer(heading) {
      UI.clear(container);
      var s = slides[index] || { eyebrow: "", title: "Nothing to recap", body: "" };
      var dots = el("div", { class: "recap-dots" }, slides.map(function (_, i) {
        return el("button", {
          class: "recap-dot" + (i === index ? " is-active" : ""),
          "aria-label": "Slide " + (i + 1),
          onclick: function () { index = i; drawPlayer(); if (playing) narrate(); },
        });
      }));

      var slide = el("div", { class: "recap-slide" + (reduced ? " no-anim" : "") }, [
        el("div", { class: "recap-eyebrow" }, s.eyebrow || ""),
        el("h1", { class: "recap-title" }, s.title),
        el("p", { class: "recap-body" }, s.body),
      ]);

      var controls = el("div", { class: "recap-controls" }, [
        el("button", { class: "btn", onclick: prev, disabled: index === 0 ? "" : null }, "‹ Prev"),
        el("button", { class: "btn btn-primary", onclick: function () { playing ? pause() : play(); } }, playing ? "Pause" : "Play"),
        el("button", { class: "btn", onclick: function () { next(false); }, disabled: index >= slides.length - 1 ? "" : null }, "Next ›"),
      ]);

      var note = (!TTS || !TTS.available())
        ? el("p", { class: "faint recap-note" }, "Audio narration unavailable in this browser — slides advance manually.")
        : null;

      container.appendChild(el("div", { class: "recap-stage" }, [
        el("div", { class: "recap-top" }, [
          el("span", { class: "muted" }, (heading || currentHeading) + " · " + (index + 1) + "/" + slides.length),
          el("button", { class: "btn btn-ghost", onclick: function () { if (TTS) TTS.cancel(); drawPicker(); } }, "Topics"),
        ]),
        slide, dots, controls, note,
      ]));
    }

    var currentHeading = "Recap";

    function drawPicker() {
      if (TTS) TTS.cancel();
      playing = false;
      UI.clear(container);
      var concepts = DATA.concepts.slice().sort(function (a, b) { return (DATA.neighbors(b.id).length) - (DATA.neighbors(a.id).length); });

      var list = el("div", { class: "recap-pick-grid" }, concepts.map(function (c) {
        return el("button", {
          class: "recap-pick", onclick: function () { currentHeading = c.title; startPlayer(slidesForConcept(c), c.title); },
        }, [
          el("span", { class: "dot", style: "background:" + UI.typeColor(c.type) }),
          el("span", { class: "recap-pick-title" }, c.title),
          el("span", { class: "recap-pick-meta" }, DATA.neighbors(c.id).length + " links"),
        ]);
      }));

      container.appendChild(el("div", { class: "recap-picker" }, [
        el("div", { class: "recap-picker-head" }, [
          el("h2", {}, "Narrated recap"),
          el("p", { class: "muted" }, "Pick a topic for an auto-narrated walkthrough, or play your whole map. Audio uses your device's voice."),
        ]),
        el("div", { class: "empty-actions" }, [
          el("button", { class: "btn btn-primary", onclick: function () { currentHeading = "Full map"; startPlayer(buildSlides(concepts), "Full map"); } }, "Play all " + concepts.length),
        ]),
        list,
      ]));
    }

    // Entry: focused concept (from graph/flashcards "Listen") or the picker.
    if (opts.concept) { currentHeading = opts.concept.title; startPlayer(slidesForConcept(opts.concept), opts.concept.title); }
    else drawPicker();

    return cleanup;
  }

  g.Recap = { render: render };
})(window);
