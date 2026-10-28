# Local bridge development

Find the current checkout from the task workspace and Git remote (`byteword/sketchup-codex-mcp`). Paths below are relative to that checkout, not this installed skill.

## Read only what the task needs

- `docs/HANDOFF.md`: current branch, recent changes and setup. Older sections are explicitly historical.
- `docs/FEATURE_PLAN.md`: incremental drawing/query scope; distinguish implemented tools from planned names.
- `docs/VALIDATION.md`, `docs/MANUAL_RESULTS_0.4.0.md`: automated versus native evidence and remaining cases.
- `shared/ToolCatalog.cs`, `CommandCatalog.cs`, `DiscoveryCatalog.cs`: MCP schemas and validation; `bridge/ControlHub.cs`: routing.
- `extension/su_pipe_probe/model_identity.rb`, `main.rb`, `session.rb`: document identity, native wiring, authority, command IDs and result history.
- `model_reader.rb`, `entity_browser.rb`, `command_executor.rb`, `creation_commands.rb` in the same Ruby directory: queries and native operations.

## Document identity

The process session ID and document ID have different lifetimes. Windows New/Open can reuse a Ruby `Sketchup::Model` wrapper, so `.equal?` alone is insufficient. The application observer renews document identity on `onNewModel`/`onOpenModel`, even with the same wrapper/path/title. Object identity is a fallback for an active-model switch. Do not use path or `Model#guid` as the document key: Save As changes paths and edited saves change the GUID.

Synchronize the Session when the observer fires and before granting/dispatching. A document change revokes the lease/owner and cancels a demo. Old-model reads/writes must not reach their executors; session command numbering and historical result lookup survive. New work needs refreshed IDs and explicit local permission for the new document.

## Execution and tests

Use short UI-thread API operations, explicit target paths, preflight validation and verified postconditions. Keep model edits inside one `start_operation`/`commit_operation`; abort on failure and report unknown if rollback cannot be verified. Basic drawing should use an isolated group so new edges/faces do not merge into unrelated user geometry. Preserve active tag and use the default tag for primitive geometry.

`build.cmd` uses Windows x64 .NET Framework / C# 5, with no NuGet packages. `scripts/windows-tests.ps1` is the full test entry point (Ruby x64 2.5 + Minitest 5.15.0, Python 3). `PROBE_TEST` and temporary `SUPIPE_TEST=1` isolate pipes; never attach automatic tests to the user's live GUI/model. Prefer the documented test runner; an embedded SketchUp Ruby DLL host may need an ASCII-path test copy and its matching standard-library path.

Identity regression coverage must exercise the production observer with the **same** model wrapper and same title/path, then send stale requests. Manually editing a metadata UUID tests only the Session and misses lifecycle failures. Also check Save/Save As stability, revocation, stale lease rejection, and another instance's isolation.

## Delivery

Keep C# `shared/BuildInfo.cs` and Ruby `version.rb` versions aligned. `scripts/package.ps1 -TestRelease` checks executable version metadata and builds a runtime ZIP containing exactly two EXEs, two EXE configuration files and one RBZ. Never include source, tests, skill files, helpers, or model data in the installation ZIP.

The canonical skill source is `skills/sketchup-mcp` in the repository; the discoverable installation is the matching directory under the user's Codex skills folder. Update the canonical source first, run the skill-creator validator, then sync the validated skill when authorized. Documentation-only changes do not require rebuilding binaries. Follow the user's current commit/push/release scope; a skill itself does not authorize remote publication.
