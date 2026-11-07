---
name: run-shotdev
description: Run, debug and stop ShotDev through Xcode, keeping exactly one copy running and stopping it when finished. Use whenever you need Shot running to see or check a change, read its logs, set a breakpoint, send it a shot-dev:// link, or before a QA or capture session (shot-capture-session builds on this), and whenever the user says run, launch, start, try, test it for real or debug the app.
---

# Run ShotDev

ShotDev is the dev build of Shot. Run it from Xcode, through the `mcp__plugin_xcode-integration_xcode__*` tools, so you get Xcode's incremental Debug build, its console with every `Logger` line, and lldb. Only one copy may run at a time, and you stop it when you're done, every time.

## The one-copy rule

- The **Shot** scheme's Run pre-action runs `scripts/dev.sh prepare`. It quits every other ShotDev (another worktree's, an earlier `make run`, a copy Xcode is debugging) and the installed release, whose global shortcuts would catch hotkeys, and records that the release was running. `make run` and `scripts/perf.sh` go through the same script. Never launch ShotDev any other way: no `open …/ShotDev.app`, no running the executable, no plain `open 'shot-dev://…'`, which can start a stale copy.
- Never touch `/Applications/Shot.app` beyond what `scripts/dev.sh` does. It's the copy the user relies on.
- `scripts/dev.sh status` shows what's running. Check it before you start and after you stop.

## Start

1. **Open this checkout's project.** Call `XcodeListWorkspaces`. Use the workspace whose path is the `Shot.xcodeproj` in your current checkout or worktree, never another worktree's. If it isn't listed, call `XcodeOpenWorkspace` with that absolute path, and note that you opened it. Pass its identifier (such as `workspace-7pNMxYHpS1`, not the path, which the run tools reject) as `workspaceIdentifier` to every call below, since other sessions may have their own Shot windows open.
2. **Pick the scheme.** `XcodeSwitchScheme` to `Shot`, and check `activeDestinationDisplayTitle` is `My Mac`; if not, `XcodeSwitchRunDestination` to it.
3. **Build.** `BuildProject`. On failure, read `GetBuildLog` (severity `error`) and fix the code before running. `Shot Dev` signing errors mean `scripts/make-dev-cert.sh` hasn't been run; tell the user rather than signing another way.
4. **Run.** `RunProject`, with `attachDebugger: true` only when you need lldb. It returns once ShotDev is up. Confirm with `scripts/dev.sh status`: one ShotDev, running from Xcode's DerivedData.
5. **First launch needs the user.** If ShotDev opens its welcome window asking for Screen Recording, never change that setting yourself; ask the user to turn it on. The window's **Relaunch** button starts a new ShotDev outside Xcode, so after it, `StopProject` and `RunProject` again to get the console and debugger back.

## While it runs

- **Links:** `scripts/shotdev-open.sh 'shot-dev://gallery'` sends a link to the running copy by its path, and refuses when none or several are running. The full list of actions is in `site/src/guide/10-automation-reference.md`.
- **Logs:** `GetConsoleOutput` with a `pattern` and a small `tailLimit`. ShotDev logs under subsystem `dev.lorcan.Shot.dev`, by category from `Logger.shot("…")`; `includeMetadata: true` shows both, but makes each line long. System frameworks log their own errors at launch; they aren't Shot's, so don't chase them.
- **Debugger:** `InvokeDebuggerCommand`. Start with `process status`; prefer `v` and `p` to `po`. Breakpoints you set persist in the shared session, so clear them (`breakpoint delete`) before you hand back. Don't `kill` or `pkill` a copy under the debugger: it pauses in lldb instead of quitting. Use `StopProject`, or `scripts/dev.sh stop`, which ends its `debugserver` first.
- **Another language:** the Shot scheme has `-AppleLanguages (de)` as a launch argument that starts off, and `RunProject` can't pass arguments. Use the fallback below with `APP_ARGS`, rather than editing the scheme.
- **Driving the UI** (clicks, keys, screenshots): hand over to `shot-capture-session` or computer use, with ShotDev already running.
- **A code change:** call `RunProject` again. Xcode rebuilds and replaces the running copy, and the pre-action makes sure nothing else is left.

## Stop, always

When you've finished checking, and before you report back, even when something failed part way:

1. `StopProject` for the workspace.
2. `scripts/dev.sh stop`. It quits any ShotDev still running and reopens the installed Shot if the run quit it.
3. `scripts/dev.sh status` should report no ShotDev.
4. If you opened the workspace in step 1 of Start, `XcodeCloseWorkspace` it.

Don't leave ShotDev running for the user unless they ask you to; say so in your report if they did.

## Fallback without the Xcode tools

If the Xcode tools aren't available, or you need launch arguments:

```bash
make run                                          # Debug build into build/DerivedData, then the one-copy launch
make run APP_ARGS="-AppleLanguages '(de)'"        # German
/usr/bin/log stream --predicate 'subsystem == "dev.lorcan.Shot.dev"'   # logs; in zsh, plain log is a builtin
make stop                                         # always, when finished
```
