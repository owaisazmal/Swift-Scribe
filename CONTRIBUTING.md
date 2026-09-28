# Contributing to Swift Scribe

Thanks for helping make a great free notes app.

## Workflow

1. Open an issue first for anything larger than a small fix, so we can agree on the approach.
2. Fork the repo and create a branch from `main`.
3. Keep pull requests focused on one change.
4. Make sure the app builds without warnings and the tests pass (⌘U).
5. Include screenshots or a short screen recording for UI changes (iPad and iPhone if layout is affected).

## Code style

- Swift + SwiftUI, with UIKit only where PencilKit needs it (`Canvas/`).
- Match the surrounding code: small types, descriptive names, and minimal comments. Code should explain itself; use a short comment only when the *why* isn't obvious.
- New source files are picked up automatically. The project uses folder-synchronized groups, so just add the file to the right folder.
- Put page-geometry logic in `NotebookLayout` / `PageRemapper` and cover it with unit tests.
- Don't add third-party dependencies without discussing it in an issue first. The app deliberately relies only on Apple frameworks.

## Privacy

Swift Scribe collects no data. Please don't add analytics, tracking, ads, or network calls that send user content anywhere.

## Reporting bugs

Include your device, iOS version, steps to reproduce, and what you expected versus what happened. For drawing bugs, say whether you were using Apple Pencil or a finger.
