// App shell: hash router, Today dashboard, theme toggle, view mounting (with cleanup).
(function (g) {
  "use strict";
  var UI = g.UI, DATA = g.DATA, SRS = g.SRS, el = UI.el;
  var ROUTES = ["today", "review", "map", "recap"];

  var main, navEl, dueChip;
  var currentCleanup = null;
  var pending = null;

  function currentRoute() {
    var h = (location.hash || "").replace(/^#\/?/, "");
    return ROUTES.indexOf(h) >= 0 ? h : "today";
  }

  function go(route, params) {
    pending = params || null;
    if (location.hash === "#/" + route) mount();
    else location.hash = "#/" + route;
  }

  function setActiveNav(route) {
    Array.prototype.forEach.call(navEl.children, function (a) {
      a.classList.toggle("is-active", a.getAttribute("data-route") === route);
      if (a.getAttribute("data-route") === route) a.setAttribute("aria-current", "page");
      else a.removeAttribute("aria-current");
    });
  }

  function refreshChip() {
    var d = SRS.partition(DATA.cards, Date.now()).due.length;
    dueChip.textContent = d + " due · " + SRS.currentStreak() + "-day streak";
  }

  function mount() {
    var route = currentRoute();
    setActiveNav(route);
    if (currentCleanup) { try { currentCleanup(); } catch (e) {} currentCleanup = null; }
    UI.clear(main);
    var p = pending; pending = null;

    if (route === "today") renderToday();
    else if (route === "review") {
      currentCleanup = g.Flashcards.render(main, {
        cards: p && p.cards, title: p && p.title, onExit: function () { go("today"); },
      });
    } else if (route === "map") {
      currentCleanup = g.Graph.render(main, {
        focusId: p && p.focusId,
        onReview: function (cards, title) { go("review", { cards: cards, title: title }); },
        onListen: function (c) { go("recap", { concept: c }); },
      });
    } else if (route === "recap") {
      currentCleanup = g.Recap.render(main, { concept: p && p.concept });
    }
    refreshChip();
  }

  function renderToday() {
    var part = SRS.partition(DATA.cards, Date.now());
    var due = part.due.length;
    var streak = SRS.currentStreak();
    var topConcepts = DATA.concepts.slice().sort(function (a, b) {
      return DATA.neighbors(b.id).length - DATA.neighbors(a.id).length;
    }).slice(0, 6);

    var hero = el("section", { class: "hero" }, [
      el("div", { class: "hero-main" }, [
        el("div", { class: "hero-eyebrow" }, due > 0 ? "Ready to review" : "All caught up"),
        el("div", { class: "hero-figure" }, [
          el("span", { class: "hero-num" }, String(due)),
          el("span", { class: "hero-unit" }, due === 1 ? "card due" : "cards due"),
        ]),
        el("div", { class: "hero-actions" }, [
          el("button", { class: "btn btn-primary btn-lg", onclick: function () { go("review"); } },
            due > 0 ? "Start review" : "Review ahead"),
          el("button", { class: "btn btn-ghost btn-lg", onclick: function () { go("map"); } }, "Explore map"),
        ]),
      ]),
      el("div", { class: "hero-stats" }, [
        stat(String(streak), streak === 1 ? "day streak" : "day streak"),
        stat(String(DATA.concepts.length), "concepts"),
        stat(String(part.scheduled), "scheduled"),
      ]),
    ]);

    var jump = el("section", { class: "panel-card" }, [
      el("div", { class: "section-head" }, [el("h2", {}, "Jump back in"), el("span", { class: "muted" }, "most-connected concepts")]),
      el("div", { class: "chip-row" }, topConcepts.map(function (c) {
        return el("button", { class: "concept-chip", onclick: function () { go("map", { focusId: c.id }); } }, [
          el("span", { class: "dot", style: "background:" + UI.typeColor(c.type) }),
          c.title,
        ]);
      })),
    ]);

    var tiles = el("section", { class: "tile-row" }, [
      tile("Concept map", DATA.edges.length + " links between " + DATA.concepts.length + " concepts", function () { go("map"); }),
      tile("Narrated recap", "Auto-narrated walkthrough of your topics", function () { go("recap"); }),
    ]);

    var children = [hero, jump, tiles];
    if (DATA.isSample) {
      children.unshift(el("div", { class: "banner" }, [
        el("strong", {}, "Demo data. "),
        "Generate from your vault: ",
        el("code", {}, "node review/generate.mjs --vault ~/Projects/Personal_LLM_Wiki"),
      ]));
    }
    main.appendChild(el("div", { class: "today" }, children));
  }

  function stat(num, label) {
    return el("div", { class: "stat" }, [el("div", { class: "stat-num" }, num), el("div", { class: "stat-label" }, label)]);
  }
  function tile(title, desc, onclick) {
    return el("button", { class: "tile", onclick: onclick }, [
      el("h3", {}, title), el("p", { class: "muted" }, desc), el("span", { class: "tile-go" }, "→"),
    ]);
  }

  // --- theme ---
  var THEME_KEY = "wikiReview.theme";
  function applyTheme(t) {
    if (t === "light") document.documentElement.setAttribute("data-theme", "light");
    else document.documentElement.removeAttribute("data-theme");
  }
  function currentTheme() { try { return localStorage.getItem(THEME_KEY) || "dark"; } catch (e) { return "dark"; } }
  function toggleTheme() {
    var t = currentTheme() === "light" ? "dark" : "light";
    try { localStorage.setItem(THEME_KEY, t); } catch (e) {}
    applyTheme(t);
  }

  function boot() {
    applyTheme(currentTheme());
    var root = document.getElementById("app");

    navEl = el("nav", { class: "nav" }, [
      navLink("today", "Today"), navLink("review", "Review"),
      navLink("map", "Map"), navLink("recap", "Recap"),
    ]);
    dueChip = el("span", { class: "due-chip" }, "—");

    var header = el("header", { class: "topbar" }, [
      el("div", { class: "brand" }, [el("span", { class: "brand-dot" }), "Wiki Review"]),
      navEl,
      el("div", { class: "topbar-right" }, [
        dueChip,
        el("button", { class: "icon-btn", title: "Toggle theme", "aria-label": "Toggle theme", onclick: toggleTheme }, "◑"),
      ]),
    ]);

    main = el("main", { class: "main", id: "view" });
    root.appendChild(header);
    root.appendChild(main);

    window.addEventListener("hashchange", mount);
    mount();
  }

  function navLink(route, label) {
    return el("a", { class: "nav-link", href: "#/" + route, "data-route": route }, label);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  g.App = { go: go };
})(window);
