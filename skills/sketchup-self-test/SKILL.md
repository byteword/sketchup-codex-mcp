---
name: sketchup-self-test
description: "Run the SketchUp bridge's fast native batch acceptance suite and interpret its report. Use when the user wants to verify installed drawing, editing and query tools or rerun a smoke test after an update."
---

# SketchUp batch acceptance

Use `sketchup_run_self_test` to check the installed features in **one command**, rather than asking the user to perform each drawing/edit/Undo separately. The fixed native suite creates only its own temporary groups, runs API assertions, then aborts the enclosing operation and checks geometry/selection/camera restoration.

## Run

1. Call `sketchup_list_instances` first, choose the user's exact session/model, and compare fresh bridge/extension versions. Refresh the MCP adapter after an update if it still exposes an older tool list. Never substitute arbitrary Ruby, keyboard actions, or permission manipulation for an unavailable tool.
2. Confirm that the intended document is a small **test model** and read the current edit context. This confirmation may already be provided by the user asking to run tests in their test model. The suite requires root context `[]`, at most 1000 root entities/selection items and 5000 definitions. It does not save/open files or change edit context. Ask the user to exit group editing if needed.
3. Check fresh instance authority. If permission is missing, ask once for local **MCP 명령 실행 허용**: toolbar button2 **권한 부여 / 회수** in0.13.0+, or the panel button in older versions. Existing authorization to run the suite covers its temporary geometry and checks; do not ask for separate approval for each step.
4. Obtain fresh `next_command_id`. Call `sketchup_run_self_test` with exact `session_id`, `model_id`, `command_id`, `expected_context=[]`, `confirm_test_model=true`. When the schema supports `suite`, select `all` for update acceptance; use `core`/`extended` for a requested subset. Older schemas can run only their original core; report that reduced coverage. Use normal execution; `dry_run` only lists the plan and is not a passed test.
5. Read `result.data.passed`, pass/fail/skip counts, `checks`, `duration_ms`, `cleanup_verified` and modified-before/after values. A completed request can contain failed checks. In0.6.1 also report `ui_update` closure/refresh flags and warnings separately: geometry passing does not certify successful rendering or an Outliner CPU reduction. Do not replay geometry because a final refresh warned. Special camera modes can cause view checks to be skipped; report skips explicitly.
6. A timeout/unknown outcome is not a failed geometry check. Query `sketchup_get_command_result` for the same ID without re-executing. If outcome/cleanup cannot be established, stop, identify the uncertain test model and report it. Do not create a fresh ID to repeat an uncertain run.

Report the summary in Korean with the failed/skipped step names, actual elapsed time, and cleanup result. Save the report or repository acceptance record when requested or relevant to ongoing validation. Keep actual native results separate from API doubles and CI counts.

## Coverage and boundaries

0.6.0 offers core (24 functional checks+cleanup), extended (31+cleanup), and all (55+cleanup=56). Extended covers curves/meshes/offset/revolution/sweep, component definitions and sharing, raw point/vertex/face edits and grouping, smoothing/simplification, temporary material/tag lifecycle, resource queries, mirror and camera. It verifies resource identity sets as well as geometry/UI restoration. Special cameras can skip view checks. A cooperative four-second budget is checked between steps; an individual native API call cannot be forcibly interrupted. If a completed and cleaned all run exceeds the budget, a later new run can use separate core/extended subsets; never do this to repeat an unknown outcome.

The suite runs command executors **inside one aborted operation**, suppressing per-command Undo operations. It certifies native API behavior and cleanup, not each standalone command's Undo history. Scene mutation and model-wide purge are excluded: only scene queries and the suite's own temporary resource lifecycle run. New/Open, Save As, permission revocation and concurrency remain separate acceptance scenarios. Run those selectively once per relevant change, not as an interactive prerequisite for every ordinary geometry test.

## Optional external runner

If the task needs a saved machine-readable report outside direct MCP calls, use [scripts/run_native_tests.py](scripts/run_native_tests.py). It requires Python 3 and the adapter EXE path plus exact session/model IDs and `--confirm-test-model`; it never grants permission or starts another GUI. It checks matching adapter/bridge/extension versions and performs the same single batch command. A lost response is recovered only through result lookup, never mutation replay.

Example (use discovered IDs and the user's installed path):

```powershell
python run_native_tests.py --mcp-exe 'C:\Tools\SketchUp\SketchUpMcp.exe' --session-id '<current-session>' --model-id '<current-model>' --confirm-test-model --output 'native-test-report.json'
```

The script defaults to `--suite all`; `--suite core` or `extended` selects a subset. It is a development/testing helper and stays outside the five-file installation ZIP. If repository development is required, use its current tests/handoff and the `sketchup-mcp` development guidance; do not run the live suite as part of CI.
