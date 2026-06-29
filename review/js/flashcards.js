// Flashcard review view: SM-2 scheduled queue, flip, grade, keyboard, session summary.
(function (g) {
  "use strict";

  var GRADES = [
    { key: "again", label: "Again", hint: "1" },
    { key: "hard", label: "Hard", hint: "2" },
    { key: "good", label: "Good", hint: "3" },
    { key: "easy", label: "Easy", hint: "4" },
  ];

  // render(container, { cards, title, onExit }) -> cleanup()
  function render(container, opts) {
    var UI = g.UI, SRS = g.SRS, DATA = g.DATA, el = UI.el;
    opts = opts || {};
    var pool = opts.cards && opts.cards.length ? opts.cards : DATA.cards;

    var part = SRS.partition(pool, Date.now());
    var reviewingAll = false;
    var queue = part.due.slice();
    var flipped = false;
    var reviewedCount = 0;

    function keyHandler(e) {
      if (e.key === " " || e.key === "Spacebar") { e.preventDefault(); if (!flipped) flip(); }
      else if (flipped && e.key >= "1" && e.key <= "4") grade(GRADES[+e.key - 1].key);
    }
    document.addEventListener("keydown", keyHandler);

    function cleanup() { document.removeEventListener("keydown", keyHandler); }

    function flip() { flipped = true; draw(); }

    function grade(gradeKey) {
      var card = queue[0];
      if (!card) return;
      var q = SRS.GRADE_Q[gradeKey];
      var next = SRS.review(SRS.load(card.id) || {}, q, Date.now());
      SRS.save(card.id, next);
      reviewedCount++;
      queue.shift();
      if (q < 3) queue.push(card); // lapse -> requeue within session
      flipped = false;
      draw();
    }

    function startReviewAll() {
      reviewingAll = true;
      queue = pool.slice();
      flipped = false;
      reviewedCount = 0;
      draw();
    }

    function draw() {
      UI.clear(container);

      if (queue.length === 0) {
        container.appendChild(sessionEnd());
        return;
      }

      var card = queue[0];
      var concept = DATA.conceptById[card.source];
      var total = reviewedCount + queue.length;
      var done = reviewedCount;

      var progress = el("div", { class: "fc-progress" }, [
        el("div", { class: "fc-bar" }, [
          el("i", { style: "width:" + (total ? Math.round((done / total) * 100) : 0) + "%" }),
        ]),
        el("span", { class: "fc-count" }, done + " / " + total),
      ]);

      var card$ = el("div", { class: "fc-card" + (flipped ? " is-flipped" : "") }, [
        el("div", { class: "fc-deck" }, (card.deck || "card") + (concept ? " · " + concept.title : "")),
        el("div", { class: "fc-front" }, card.front),
        flipped ? el("div", { class: "fc-divider" }) : null,
        flipped ? el("div", { class: "fc-back" }, card.back) : null,
        (flipped && concept && concept.links && concept.links.length)
          ? el("div", { class: "fc-links" }, "Linked: " + concept.links.slice(0, 4).join(" · "))
          : null,
      ]);

      var actions;
      if (!flipped) {
        actions = el("div", { class: "fc-actions" }, [
          el("button", { class: "btn btn-primary", onclick: flip }, "Show answer"),
          el("span", { class: "fc-hint" }, "Space"),
        ]);
      } else {
        actions = el("div", { class: "fc-grades" },
          GRADES.map(function (gr) {
            var prev = SRS.load(card.id) || {};
            return el("button", {
              class: "fc-grade fc-grade-" + gr.key,
              onclick: function () { grade(gr.key); },
            }, [
              el("span", { class: "fc-grade-label" }, gr.label),
              el("small", {}, SRS.previewLabel(prev, gr.key)),
            ]);
          })
        );
      }

      container.appendChild(el("div", { class: "fc-wrap" }, [progress, card$, actions]));
    }

    function sessionEnd() {
      var actions = [el("button", { class: "btn btn-primary", onclick: function () { if (opts.onExit) opts.onExit(); } }, "Done")];
      if (!reviewingAll && pool.length > 0) {
        actions.unshift(el("button", { class: "btn", onclick: startReviewAll }, "Review all " + pool.length + " anyway"));
      }
      return el("div", { class: "empty" }, [
        el("div", { class: "empty-mark" }, reviewedCount > 0 ? "✓" : "•"),
        el("h2", {}, reviewedCount > 0 ? "Session complete" : "Nothing due right now"),
        el("p", { class: "muted" }, reviewedCount > 0
          ? "Reviewed " + reviewedCount + " card" + (reviewedCount === 1 ? "" : "s") + ". Spaced-repetition has scheduled the next reviews."
          : "You're caught up. Come back later, or review everything to study ahead."),
        el("div", { class: "empty-actions" }, actions),
      ]);
    }

    if (queue.length > 0) SRS.bumpStreak(Date.now());
    draw();
    return cleanup;
  }

  g.Flashcards = { render: render };
})(window);
