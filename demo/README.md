# Demo data (for demo purposes only)

Everything in this folder is **made-up sample content**, used to produce the screenshots and
demo GIF in the main README. None of it is real personal data, and the app works without it.

| Path | What it is |
|---|---|
| `create-demo-notes.applescript` | Creates an **AppleNotestoX Demo** folder in Apple Notes with 7 sample notes |
| `vault/` | A sample Personal Wiki vault: 7 concept pages in `wiki/concepts/` (9 flashcards, 5 links), and empty `raw/apple-notes/` and `wiki/sources/` folders the app fills in |

## Try it

```bash
osascript demo/create-demo-notes.applescript    # adds the demo folder to Apple Notes
cp -R demo/vault ~/AppleNotestoX-Demo-Vault     # work on a copy, so the repo stays clean
make study VAULT=~/AppleNotestoX-Demo-Vault     # flashcards and concept map from the sample wiki
make run
```

In the app:

1. **Transfer/Transform:** search `AppleNotestoX Demo`, tick the notes, choose **Personal Wiki**,
   pick `~/AppleNotestoX-Demo-Vault` and export. Notes land in `raw/apple-notes/<category>/`.
2. **Duplicates:** the two cheatsheet notes appear under *Possibly Duplicate Content*.
3. To see *Same Note, Multiple Files* and the version diff, edit **Swift concurrency notes (copy)**
   in Notes, reload the library, and export it again.

## Clean up

Delete the **AppleNotestoX Demo** folder in Apple Notes and the `~/AppleNotestoX-Demo-Vault` folder.
