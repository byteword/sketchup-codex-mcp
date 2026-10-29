---
name: sketchup-mcp
description: "Operate connected SketchUp models through the local MCP bridge, or extend its drawing and model-information tools. Use for model queries, explicit geometry requests, native acceptance tests, and development of this bridge."
---

# SketchUp MCP

Use the installed SketchUp MCP tools for model work. A skill supplies operating guidance; it does not grant model control or add tools that the running adapter lacks.

## Work on a connected model

- Discover the available SketchUp tools, then call `sketchup_list_instances` first. Target the returned exact session and current model IDs. If multiple instances could match, resolve the intended PID/model before changing anything.
- Read the current model, selection, and edit context as needed. Use `find_entities`/`get_children` for unselected objects; a shared child PID is not a unique occurrence. Preserve its full `instance_path` and `parent_path`.
- Queries work in user control. For changes, check fresh instance state and the local execution grant. In0.13.0+ this is toolbar button2 (권한 부여 / 회수); older versions use the panel's MCP 명령 실행 허용. If absent, ask the user to press that local button; do not change permission through another channel. Reuse existing human authorization within the requested task.
- Before each new command, obtain `next_command_id` from fresh `get_instance` state. Build `expected_context` from the ordered `persistent_id` strings in fresh selection/model `edit_context.path`; root is `[]`. Stop if the path is truncated. Existing targets must be direct children of that current context; do not open/close an edit path implicitly.
- Interpret distances as **mm along model axes**, including inside rotated/scaled parents. State any consequential geometric choices. Use actual tool schemas for supported kinds, limits, and required arguments instead of inventing generic Ruby or keyboard execution.
- `dry_run` consumes its own command ID. A later execution needs a fresh ID; a preview is not a reservation of unchanged geometry. Preview when useful for the requested operation, without making it an extra approval gate for already authorized work.
- After a timeout, disconnect, or unknown outcome, do not resend a mutation or mint a replacement command ID to repeat it. Query `get_command_result` and current objects. Cached results describe history, including after Undo; replay is not Redo.
- A new/opened model needs a fresh model ID and local grant. Re-resolve targets rather than carrying entity IDs across documents. If the user changed documents but a running old adapter still reports the same ID, avoid further mutations until the identity fault is resolved.
- Validate completion using returned before/after data and a fresh query where useful. Say which results are API-verified and which were visually/Undo-confirmed by the user. Geometry/resource edits use one Undo operation per request; selection/camera and legacy scene changes are separate.

For component/raw-geometry/resource/curve/scene work, read [extended tool guidance](references/extended-tools.md). Use the installed schema to determine which release is available; do not treat planned or development-only features as installed capabilities.

## Extend or validate the bridge

For fast native acceptance, use the installed `sketchup-self-test` skill and `sketchup_run_self_test` when available. A single confirmed test-model run replaces per-step interactive geometry checks; lifecycle/Undo scenarios remain separate. Do not require a user reply after every successful batch step.

Read [development guidance](references/development.md) for source locations, model lifecycle rules, Windows test setup, and minimal packaging. Locate the user's current checkout first; do not assume this installed skill lives inside the repository.

Keep each capability's contract, units and regression evidence clear while connecting validation, routing and Ruby execution. Honor an explicitly requested feature bundle; do not stop after one feature merely because development was previously incremental. Native acceptance results and API doubles are different evidence. Consult the latest handoff, validation and feature plan instead of treating an old successful test as general release approval.
