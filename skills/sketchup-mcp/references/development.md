# Local bridge development

Find the current checkout from the task workspace and Git remote (`byteword/sketchup-codex-mcp`). Paths below are relative to that checkout, not this installed skill.

## Read only what the task needs

- `docs/HANDOFF.md`: current branch, recent changes and setup. Older sections are explicitly historical.
- `docs/FEATURE_PLAN.md`: incremental drawing/query scope; distinguish implemented tools from planned names.
- `docs/VALIDATION.md`, `docs/MANUAL_RESULTS_0.4.0.md`: automated versus native evidence and remaining cases.
- `shared/ToolCatalog.cs`, `CommandCatalog.cs`, `DiscoveryCatalog.cs`: MCP schemas and validation; `bridge/ControlHub.cs`: routing.
- `ToolkitCatalog.cs`/`ToolkitSchemas.json`: generated extended schemas. Edit `scripts/generate_toolkit_catalog.py` and `ToolkitCatalog.template`, then regenerate. `geometry_plan.rb`, `extended_geometry.rb`, `resources.rb`, `view_commands.rb` implement the bounded extension.
- `extension/su_pipe_probe/model_identity.rb`, `main.rb`, `session.rb`: document identity, native wiring, authority, command IDs and result history.
- `model_reader.rb`, `entity_browser.rb`, `entity_details.rb`, `command_executor.rb`, `creation_commands.rb`, `basic_commands.rb` in the same Ruby directory: queries and native operations.
- `native_self_test.rb` and `docs/BATCH_TEST.md`: fixed native smoke suite, cleanup guarantees and limits. It suppresses individual operation boundaries inside one aborted outer operation, so it does not certify per-command native Undo.
- `extended_self_checks.rb`: optional extended/all suites. Scene mutations are excluded because SketchUp2019 does not restore their camera metadata through model abort. Resource PID support is version-dependent; definitions/materials/tags must use the separate model-session IDs on2019.

## Document identity

The process session ID and document ID have different lifetimes. Windows New/Open can reuse a Ruby `Sketchup::Model` wrapper, so `.equal?` alone is insufficient. The application observer renews document identity on `onNewModel`/`onOpenModel`, even with the same wrapper/path/title. Object identity is a fallback for an active-model switch. Do not use path or `Model#guid` as the document key: Save As changes paths and edited saves change the GUID.

Synchronize the Session when the observer fires and before granting/dispatching. A document change revokes the lease/owner and cancels a demo. Old-model reads/writes must not reach their executors; session command numbering and historical result lookup survive. New work needs refreshed IDs and explicit local permission for the new document.

## Execution and tests

Use short UI-thread API operations, explicit target paths, preflight validation and verified postconditions. Keep model edits inside one `start_operation`/`commit_operation`; abort on failure and report unknown if rollback cannot be verified. Basic drawing should use an isolated group so new edges/faces do not merge into unrelated user geometry. Preserve active tag and use the default tag for primitive geometry.

`ui_update_scope.rb` owns synchronous native operation/UI cleanup; `batch_commands.rb` runs bounded typed edits through InlineCommandExecutor under one outer scope. Do not open operations across timer ticks/requests or force inspector/view refresh per entity. The default defer policy uses disable_ui=true and requests final invalidate/refresh_inspectors after closure; postcommit display errors are warnings. `tests/ui_updates_test.rb` covers success/failure/interruption/reentrancy and exactly one explicit refresh for a40-step batch. Native Outliner CPU measurements remain separate from doubles.

`build.cmd` uses Windows x64 .NET Framework / C# 5, with no NuGet packages. `scripts/windows-tests.ps1` is the full test entry point (Ruby x64 2.5 + Minitest 5.15.0, Python 3). `PROBE_TEST` and temporary `SUPIPE_TEST=1` isolate pipes; never attach automatic tests to the user's live GUI/model. Prefer the documented test runner; an embedded SketchUp Ruby DLL host may need an ASCII-path test copy and its matching standard-library path.

Identity regression coverage must exercise the production observer with the **same** model wrapper and same title/path, then send stale requests. Manually editing a metadata UUID tests only the Session and misses lifecycle failures. Also check Save/Save As stability, revocation, stale lease rejection, and another instance's isolation.

## Delivery

Keep C# `shared/BuildInfo.cs` and Ruby `version.rb` versions aligned. `scripts/package.ps1 -TestRelease` checks executable version metadata and builds a runtime ZIP containing exactly two EXEs, two EXE configuration files and one RBZ. Never include source, tests, skill files, helpers, or model data in the installation ZIP.

The canonical skill source is `skills/sketchup-mcp` in the repository; the discoverable installation is the matching directory under the user's Codex skills folder. Update the canonical source first, run the skill-creator validator, then sync the validated skill when authorized. Documentation-only changes do not require rebuilding binaries. Follow the user's current commit/push/release scope; a skill itself does not authorize remote publication.
