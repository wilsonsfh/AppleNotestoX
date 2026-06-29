// Tiny DOM helpers shared by the views. No dependencies.
(function (g) {
  "use strict";

  function el(tag, attrs, children) {
    var n = document.createElement(tag);
    if (attrs) {
      for (var k in attrs) {
        if (!Object.prototype.hasOwnProperty.call(attrs, k)) continue;
        var v = attrs[k];
        if (v == null) continue;
        if (k === "class") n.className = v;
        else if (k === "text") n.textContent = v;
        else if (k === "html") n.innerHTML = v;
        else if (k.slice(0, 2) === "on" && typeof v === "function") {
          n.addEventListener(k.slice(2).toLowerCase(), v);
        } else n.setAttribute(k, v);
      }
    }
    if (children != null) {
      (Array.isArray(children) ? children : [children]).forEach(function (c) {
        if (c == null || c === false) return;
        n.appendChild(typeof c === "string" || typeof c === "number" ? document.createTextNode(String(c)) : c);
      });
    }
    return n;
  }

  function clear(node) { while (node && node.firstChild) node.removeChild(node.firstChild); }

  function typeColor(type) {
    return ({
      concept: "var(--accent)",
      entity: "var(--c-entity)",
      project: "var(--c-project)",
      source: "var(--c-source)",
      overview: "var(--c-overview)",
    })[type] || "var(--muted)";
  }

  g.UI = { el: el, clear: clear, typeColor: typeColor };
})(window);
