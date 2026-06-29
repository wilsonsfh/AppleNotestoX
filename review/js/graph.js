// Concept map: dependency-free force-directed graph on <canvas> with a detail panel.
(function (g) {
  "use strict";

  function render(container, opts) {
    var UI = g.UI, DATA = g.DATA, el = UI.el;
    opts = opts || {};

    var nodes = DATA.concepts.map(function (c) {
      return { id: c.id, c: c, x: 0, y: 0, vx: 0, vy: 0, deg: 0, r: 6 };
    });
    var byId = {};
    nodes.forEach(function (n) { byId[n.id] = n; });
    var edges = DATA.edges.filter(function (e) { return byId[e.source] && byId[e.target]; });
    edges.forEach(function (e) { byId[e.source].deg++; byId[e.target].deg++; });
    nodes.forEach(function (n) { n.r = 6 + Math.min(10, n.deg * 1.4); });

    var canvas = el("canvas", { class: "graph-canvas" });
    var panel = el("aside", { class: "graph-panel" });
    var search = el("input", { class: "graph-search", type: "search", placeholder: "Search concepts…", "aria-label": "Search concepts" });
    var wrap = el("div", { class: "graph-wrap" }, [
      el("div", { class: "graph-stage" }, [search, canvas]),
      panel,
    ]);
    container.appendChild(wrap);

    var ctx = canvas.getContext("2d");
    var W = 0, H = 0, dpr = Math.max(1, window.devicePixelRatio || 1);
    var selected = null, hover = null, dragging = null, query = "";
    var raf = null, alpha = 1;
    var reduced = g.TTS && g.TTS.reducedMotion ? g.TTS.reducedMotion() : false;

    function size() {
      var stage = canvas.parentElement;
      W = stage.clientWidth; H = stage.clientHeight;
      canvas.width = Math.floor(W * dpr); canvas.height = Math.floor(H * dpr);
      canvas.style.width = W + "px"; canvas.style.height = H + "px";
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function seed() {
      nodes.forEach(function (n) {
        if (!n.x) {
          var a = Math.random() * Math.PI * 2, rad = Math.min(W, H) * 0.3 * Math.sqrt(Math.random());
          n.x = W / 2 + Math.cos(a) * rad; n.y = H / 2 + Math.sin(a) * rad;
        }
      });
    }

    function tick() {
      var charge = 1400, springLen = 80, springK = 0.02, centerK = 0.006, damping = 0.86;
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          var a = nodes[i], b = nodes[j];
          var dx = b.x - a.x, dy = b.y - a.y, d2 = dx * dx + dy * dy || 0.01, d = Math.sqrt(d2);
          var f = (charge / d2) * alpha, fx = (dx / d) * f, fy = (dy / d) * f;
          a.vx -= fx; a.vy -= fy; b.vx += fx; b.vy += fy;
        }
      }
      edges.forEach(function (e) {
        var a = byId[e.source], b = byId[e.target];
        var dx = b.x - a.x, dy = b.y - a.y, d = Math.sqrt(dx * dx + dy * dy) || 0.01;
        var f = (d - springLen) * springK * alpha, fx = (dx / d) * f, fy = (dy / d) * f;
        a.vx += fx; a.vy += fy; b.vx -= fx; b.vy -= fy;
      });
      nodes.forEach(function (n) {
        if (n === dragging) return;
        n.vx += (W / 2 - n.x) * centerK * alpha;
        n.vy += (H / 2 - n.y) * centerK * alpha;
        n.vx *= damping; n.vy *= damping;
        n.x += n.vx; n.y += n.vy;
        n.x = Math.max(n.r + 4, Math.min(W - n.r - 4, n.x));
        n.y = Math.max(n.r + 4, Math.min(H - n.r - 4, n.y));
      });
      alpha *= 0.985;
      return alpha > 0.02;
    }

    function matches(n) { return query && n.c.title.toLowerCase().indexOf(query) === -1 && n.id.indexOf(query) === -1; }

    function draw() {
      ctx.clearRect(0, 0, W, H);
      // edges
      ctx.lineWidth = 1;
      edges.forEach(function (e) {
        var a = byId[e.source], b = byId[e.target];
        var active = selected && (e.source === selected.id || e.target === selected.id);
        ctx.strokeStyle = active ? "rgba(123,138,255,0.55)" : "rgba(255,255,255,0.07)";
        ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
      });
      // nodes
      nodes.forEach(function (n) {
        var dim = matches(n);
        var isSel = selected === n, isHov = hover === n;
        ctx.globalAlpha = dim ? 0.18 : 1;
        ctx.beginPath(); ctx.arc(n.x, n.y, n.r + (isSel ? 2 : 0), 0, Math.PI * 2);
        ctx.fillStyle = colorFor(n.c.type);
        ctx.fill();
        if (isSel || isHov) { ctx.lineWidth = 2; ctx.strokeStyle = "#fff"; ctx.stroke(); }
        if (isSel || isHov || n.deg >= 4 || query) {
          ctx.globalAlpha = dim ? 0.25 : 1;
          ctx.fillStyle = "rgba(231,231,234,0.92)";
          ctx.font = "12px ui-sans-serif, -apple-system, sans-serif";
          ctx.textAlign = "center";
          ctx.fillText(n.c.title.length > 26 ? n.c.title.slice(0, 25) + "…" : n.c.title, n.x, n.y - n.r - 6);
        }
      });
      ctx.globalAlpha = 1;
    }

    function colorFor(type) {
      return ({ concept: "#5b6cff", entity: "#3fb37f", project: "#e0a13a", source: "#9a6bff", overview: "#e0556b" })[type] || "#8a8a93";
    }

    function loop() { var live = tick(); draw(); if (live) raf = requestAnimationFrame(loop); else raf = null; }

    function restart() { alpha = 1; if (!raf && !reduced) raf = requestAnimationFrame(loop); else if (reduced) { for (var i = 0; i < 320; i++) tick(); draw(); } }

    function nodeAt(px, py) {
      for (var i = nodes.length - 1; i >= 0; i--) {
        var n = nodes[i], dx = px - n.x, dy = py - n.y;
        if (dx * dx + dy * dy <= (n.r + 5) * (n.r + 5)) return n;
      }
      return null;
    }
    function pos(e) { var r = canvas.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; }

    function onMove(e) {
      var p = pos(e);
      if (dragging) { dragging.x = p.x; dragging.y = p.y; dragging.vx = 0; dragging.vy = 0; restart(); if (reduced) draw(); return; }
      var n = nodeAt(p.x, p.y);
      canvas.style.cursor = n ? "pointer" : "default";
      if (n !== hover) { hover = n; if (reduced || !raf) draw(); }
    }
    function onDown(e) { var n = nodeAt(pos(e).x, pos(e).y); if (n) { dragging = n; select(n); } }
    function onUp() { dragging = null; }

    function select(n) { selected = n; renderPanel(); if (reduced || !raf) draw(); }

    function renderPanel() {
      UI.clear(panel);
      if (!selected) {
        panel.appendChild(el("div", { class: "panel-empty muted" }, [
          el("p", {}, "Click a node to inspect a concept — its summary, tags, and links."),
          el("p", { class: "faint" }, nodes.length + " concepts · " + edges.length + " links"),
        ]));
        return;
      }
      var c = selected.c;
      panel.appendChild(el("div", { class: "panel-head" }, [
        el("span", { class: "chip chip-type", style: "color:" + colorFor(c.type) }, c.type),
        el("h2", {}, c.title),
      ]));
      if (c.summary) panel.appendChild(el("p", { class: "panel-summary" }, c.summary));
      if (c.tags && c.tags.length) {
        panel.appendChild(el("div", { class: "panel-tags" }, c.tags.map(function (t) { return el("span", { class: "tag" }, t); })));
      }
      var nbrs = DATA.neighbors(c.id);
      if (nbrs.length) {
        panel.appendChild(el("div", { class: "panel-section-label" }, "Linked concepts"));
        panel.appendChild(el("div", { class: "panel-links" }, nbrs.map(function (id) {
          var nc = DATA.conceptById[id];
          return el("button", { class: "link-pill", onclick: function () { select(byId[id]); } }, nc ? nc.title : id);
        })));
      }
      var cards = DATA.cardsForConcept(c.id);
      panel.appendChild(el("div", { class: "panel-actions" }, [
        cards.length && opts.onReview ? el("button", { class: "btn btn-primary", onclick: function () { opts.onReview(cards, c.title); } }, "Review (" + cards.length + ")") : null,
        (g.TTS && g.TTS.available()) ? el("button", { class: "btn", onclick: function () { if (opts.onListen) opts.onListen(c); } }, "Listen") : null,
      ]));
    }

    var ro = (typeof ResizeObserver !== "undefined") ? new ResizeObserver(function () { size(); seed(); restart(); }) : null;

    canvas.addEventListener("mousemove", onMove);
    canvas.addEventListener("mousedown", onDown);
    window.addEventListener("mouseup", onUp);
    search.addEventListener("input", function () { query = search.value.trim().toLowerCase(); if (reduced || !raf) draw(); });

    // initial layout (after the element is in the DOM so sizes are known)
    setTimeout(function () {
      size(); seed();
      if (ro) ro.observe(canvas.parentElement);
      if (opts.focusId && byId[opts.focusId]) select(byId[opts.focusId]); else renderPanel();
      restart();
    }, 0);

    return function cleanup() {
      if (raf) cancelAnimationFrame(raf);
      canvas.removeEventListener("mousemove", onMove);
      canvas.removeEventListener("mousedown", onDown);
      window.removeEventListener("mouseup", onUp);
      if (ro) ro.disconnect();
    };
  }

  g.Graph = { render: render };
})(window);
