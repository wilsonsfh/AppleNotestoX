---
type: concept
tags: [swift, concurrency]
---
# Swift actors
An actor protects its own mutable state so only one task touches it at a time. Related: [[structured-concurrency]], [[main-actor]].

What does an actor guarantee?::Only one task accesses its mutable state at a time.
When should you use async let?::When two independent async calls can run in parallel.
