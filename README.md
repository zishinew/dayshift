# dayshift

minimal, natural-language task management for macOS and the web.

dayshift is a native SwiftUI app with a full-screen todo list, a calendar view, class-aware school task suggestions, priorities, due dates, and repeating tasks. Tasks are controlled from the command bar at the bottom of the window. Account and appearance controls live under the profile icon in the title bar.

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
move quiz to next weds
make quiz high priority
add quiz next week
add a repeating quiz every 2 weeks
repeat quiz every monday
remove quiz
add class math237
i have classes math237, cs136, stat230
```

Weekdays accept common short forms such as `mon`, `tue`, `tues`, `wed`, `weds`, `thu`, `thur`, `thurs`, `fri`, and `sat`. Common weekday misspellings are corrected automatically.

Press `tab` when a school task has a suggested class. Completing a repeating task creates its next occurrence automatically.

Use `command-z` to undo the last task or class change and `command-shift-z` to redo it. Completed tasks fade away after two seconds; undo still restores the task.

## notifications

Upcoming alerts are on by default and can be turned off in settings. The app asks for macOS notification permission when it has an upcoming item to remind you about. Timed tasks and events alert one hour beforehand (or at the scheduled time if added within that hour). Items without a time alert at 9 a.m. the day before, or at 9 a.m. on the due date if added later. Completing or removing an item cancels its pending alert; repeating items schedule their upcoming occurrences.

## data

Tasks and classes are stored locally in Application Support under `DAYSHIFT`. No account or network connection is required for local use. When signed in, Dayshift keeps an account-specific local cache and an offline change queue, then syncs through the configured Supabase project. Edits, deletions, and undo/redo are included. On first sign-in, existing guest tasks and classes are copied into the account cache without removing the guest originals. Changes made on another device are fetched when the app opens, becomes active, or checks for updates. If two devices edit the same item, the last change accepted by the server wins.

Email/password sign-up normally requires confirming the email before signing in. The profile icon opens account and settings. Sessions are kept in the macOS Keychain. The bundled Supabase URL and publishable key are public client configuration, never a service-role secret. The database schema and per-user row-level-security policies are tracked in `supabase/migrations/`.

The migrations are already applied to the Dayshift Supabase project bundled in this build. To point a fork at another project, apply the migrations there in filename order and replace `DayshiftSupabaseURL` and `DayshiftSupabasePublishableKey` in `Resources/Info.plist` with that project's API URL and publishable key. Never put a secret or service-role key in the app bundle.

## project layout

- `Sources/DAYSHIFT` — SwiftUI app and natural-language command engine
- `Tests/DAYSHIFTTests` — parser and command interpreter tests
- `scripts/build-app.sh` — reproducible macOS app bundle build
- `Resources/Info.plist` — app bundle metadata

Pull requests should keep the app dependency-free and preserve the `swift test --jobs 1` check. GitHub Actions runs that test and builds the app on every push and pull request to `main`.

Run `./scripts/ci-check.sh` before pushing. It performs a clean Swift 5 compatibility test, builds the signed app bundle, and verifies its signature. This checkout uses the same check automatically as a pre-push hook.

## web app

The Next.js 16 / React 19 / Tailwind CSS v4 app lives in [`web/`](web/). It uses the same Supabase Auth account and `dayshift_changes` sync log as the Mac app, including Swift-compatible date encoding. No separate database or account is needed. Browser guest data stays local until sign-in, then is copied into the account once; the guest copy remains.

```sh
cd web
cp .env.example .env.local
npm ci
npm run dev
```

Open `http://localhost:3000`. The included `.env.example` contains only the public Supabase URL and publishable key; never use a service-role key in `NEXT_PUBLIC_` variables. For production, set those same variables in your hosting provider and deploy the `web/` directory as a Next.js app. The website has not been deployed by this repository alone. The `web` GitHub Actions job typechecks, tests, and builds it on changes.
