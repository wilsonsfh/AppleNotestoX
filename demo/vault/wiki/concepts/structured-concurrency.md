---
type: concept
tags: [swift, concurrency]
---
# Structured concurrency
Child tasks live inside a parent scope, so cancellation and errors flow upward. See [[swift-actors]].

Why prefer task groups over detached tasks?::Child tasks are cancelled and awaited with their parent scope.
