# dayshift

minimal, natural-language task management for macOS.

dayshift is a native SwiftUI app with a full-screen todo list, a calendar view, class-aware school task suggestions, priorities, due dates, and repeating tasks. Everything is controlled from the command bar at the bottom of the window.

## requirements

- macOS 14 or later
- Xcode 26.3 or later (or Swift 6.2+)
- Apple silicon is the currently supported build target

## build and run

```sh
swift test --jobs 1
./scripts/build-app.sh
open build/Dayshift.app
```

The build script creates a signed local app bundle in `build/` and generates the `d.` app icon. Generated build products are ignored by git.

## commands

Type plain English into the command bar, for example:

```text
quiz next wednesday
finish quiz
move quiz to friday
make quiz high priority
add quiz next week
add a repeating quiz every 2 weeks
repeat quiz every monday
remove quiz
add class math237
i have classes math237, cs136, stat230
```

Press `tab` when a school task has a suggested class. Completing a repeating task creates its next occurrence automatically.

Use `command-z` to undo the last task or class change and `command-shift-z` to redo it. Completed tasks fade away after two seconds; undo still restores the task.

## data

Tasks and classes are stored locally in Application Support under `DAYSHIFT`. No account or network connection is required.

## project layout

- `Sources/DAYSHIFT` — SwiftUI app and natural-language command engine
- `Tests/DAYSHIFTTests` — parser and command interpreter tests
- `scripts/build-app.sh` — reproducible macOS app bundle build
- `Resources/Info.plist` — app bundle metadata

Pull requests should keep the app dependency-free and preserve the `swift test --jobs 1` check. GitHub Actions runs that test and builds the app on every push and pull request to `main`.
# dayshift
