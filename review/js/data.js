// Normalizes window.STUDY_DATA (generated) or the committed sample into an indexed model.
(function (global) {
  "use strict";

  var raw = global.STUDY_DATA || {
    generatedAt: null, vault: "sample", concepts: [], cards: [], edges: [],
  };
  raw.concepts = raw.concepts || [];
  raw.cards = raw.cards || [];
  raw.edges = raw.edges || [];

  var conceptById = {};
  raw.concepts.forEach(function (c) { conceptById[c.id] = c; });

  var adj = {};
  raw.concepts.forEach(function (c) { adj[c.id] = {}; });
  raw.edges.forEach(function (e) {
    if (adj[e.source]) adj[e.source][e.target] = true;
    if (adj[e.target]) adj[e.target][e.source] = true;
  });

  function neighbors(id) { return adj[id] ? Object.keys(adj[id]) : []; }
  function cardsForConcept(id) { return raw.cards.filter(function (k) { return k.source === id; }); }

  function decks() {
    var counts = {};
    raw.cards.forEach(function (k) { counts[k.deck] = (counts[k.deck] || 0) + 1; });
    return counts;
  }

  global.DATA = {
    raw: raw,
    concepts: raw.concepts,
    cards: raw.cards,
    edges: raw.edges,
    conceptById: conceptById,
    neighbors: neighbors,
    cardsForConcept: cardsForConcept,
    decks: decks,
    generatedAt: raw.generatedAt,
    vault: raw.vault,
    isSample: raw.vault === "sample" || !global.STUDY_DATA,
  };
})(typeof window !== "undefined" ? window : globalThis);
