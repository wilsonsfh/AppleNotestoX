-- DEMO DATA ONLY. Creates an "AppleNotestoX Demo" folder in Apple Notes with
-- made-up notes used for the README screenshots. Safe to delete afterwards.
-- Run: osascript demo/create-demo-notes.applescript
tell application "Notes"
  set acct to default account
  if not (exists folder "AppleNotestoX Demo" of acct) then
    make new folder at acct with properties {name:"AppleNotestoX Demo"}
  end if
  set f to folder "AppleNotestoX Demo" of acct
  make new note at f with properties {body:"<h1>Swift concurrency cheatsheet</h1><ul><li>An actor serialises access to its own state, so only one task touches it at a time.</li><li>Use async let when two independent requests can run in parallel.</li><li>Mark UI-facing state with @MainActor so updates land on the main thread.</li><li>Prefer structured concurrency with task groups over detached tasks.</li></ul>"}
  -- Near-identical copy: shows up under "Possibly Duplicate Content".
  make new note at f with properties {body:"<h1>Swift concurrency cheatsheet (2)</h1><ul><li>An actor serialises access to its own state, so only one task touches it at a time.</li><li>Use async let when two independent requests can run in parallel.</li><li>Mark UI-facing state with @MainActor so updates land on the main thread.</li><li>Prefer structured concurrency with task groups over detached tasks.</li></ul>"}
  -- Export this once, edit it in Notes, then export again: it shows up under
  -- "Same Note, Multiple Files" with a diff between the two versions.
  make new note at f with properties {body:"<h1>Swift concurrency notes (copy)</h1><ul><li>An actor serialises access to its own state, so only one task touches it at a time.</li><li>Use async let when two independent requests can run in parallel.</li><li>Mark UI-facing state with @MainActor so updates land on the main thread.</li><li>Prefer structured concurrency over detached tasks.</li></ul>"}
  make new note at f with properties {body:"<h1>Reading list: knowledge systems</h1><ul><li>Andrej Karpathy, LLM wiki idea: raw sources in, synthesised pages out</li><li>Zettelkasten: one idea per note, link everything</li><li>Spaced repetition and the SM-2 algorithm</li></ul>"}
  make new note at f with properties {body:"<h1>Study plan: networking module</h1><p>Week 1: TCP congestion control, slow start and AIMD.</p><p>Week 2: routing, link-state vs distance-vector.</p><p>Week 3: revise with flashcards, focus on the weakest topics.</p>"}
  make new note at f with properties {body:"<h1>Weekend trip packing list</h1><ul><li>Passport and charger</li><li>Light jacket</li><li>Camera and spare battery</li><li>Budget: transport, food, entry tickets</li></ul>"}
  make new note at f with properties {body:"<h1>Interview prep: system design</h1><p>Practise explaining trade-offs out loud: consistency vs availability, caching layers, rate limiting.</p><p>Prepare one story about debugging a hard production issue.</p>"}
  return count of notes of f
end tell
