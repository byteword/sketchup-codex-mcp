---
name: sketchup-sliding-window
description: "Create or replace a two-panel sliding window in connected SketchUp from dimensions, opening and existing materials, preserving the optimized frame, outer-stile recessed pulls and simple render structure. Use for similar parametric window modeling requests."
---

# SketchUp two-panel sliding window

Prefer the Probe library engine when the seven `sketchup_library_*` tools are available (0.8.0+). The editable geometry recipe lives outside the RBZ. Discover the active `byteword.sliding-window` technique and read its contract; preserve an existing user-improved revision. If absent, get `kind=authoring, sections=["window_example"]`, save its complete `window_files` as a new technique, then verify and activate it with the expected active revision. Use library jobs to await completion.

On older adapters, use `sketchup_create_sliding_window` (0.7.0+) as a compatibility path. If neither route is available, explain the runtime update needed. Do not reconstruct the window with hundreds of face/edge calls or arbitrary Ruby.

## Interpret the request

- Dimensions are **width × height × depth**, in mm. Model axes are **X=width, Y=depth, Z=height**, with origin at the outer bottom-left-front corner. This recipe is aligned to model axes even inside a rotated/scaled edit parent.
- “가로 2분할” here means two equal-width leaves side by side, sliding along X on separate depth tracks. Defaults: outer frame width 40, sash width 35, glass thickness 6, meeting overlap 40 mm; both leaves closed.
- `open_sash=left` moves the left leaf rightward; `right` moves the right leaf leftward. `open_fraction` is 0–1 of available travel, **not** a fraction of total window width. Keep `none,0` for a closed window.
- Reuse a supplied reference's existing materials. Read material resources once, preserve exact names (including leading spaces), and map frame/glass/seal/hardware separately. Do not change shared material definitions merely to fit this window.
- [assets/defaults.json](assets/defaults.json) stores the approved 1200×900×100 example and its material hints. These names are hints, not universally available materials; resolve them in the current model. Origin, replacement ID and session IDs are deliberately omitted.
- The native command accepts width 600–6000, height 400–3600, depth 80–300 mm, with cross-field clearance checks. Use the installed schema and returned validation for other parameters. A different window family, uneven split, extra leaves or detailed fabrication hardware needs another recipe.

## Execute

Discover instances with `sketchup_list_instances`; resolve the current session/model. Read current edit context and next command ID immediately before each mutation. Use the local panel's human execution grant; reuse authorization already given for this task. No implicit edit-path changes.

For the library route, pin the chosen revision and send dimensions/opening as `params` to `sketchup_library_run mode=plan`. Set `bindings.session_id`, `model_id`, `expected_context`, `origin_mm=[x,y,z]`, optional `name`, and `materials={frame: exactName, glass: exactName, seal: exactName, hardware: exactName}` from the current model. Supply the exact direct-child replacement target when redrawing an existing window, keeping the user's reference separate. Read the plan summary before applying. Then use `mode=apply` with the returned plan ID/hash, fresh command ID, session/model IDs and expected edit context. Poll the library job for the native result. Replan if bindings, target or context changed.

For the older native route, send one `sketchup_create_sliding_window` request containing name, origin, dimensions, materials and opening. Set `replace_entity_id` only for an exact direct-child replacement. Optional `dry_run` consumes a command ID; execution needs a fresh ID.

Both routes remove an old target only after the replacement passes native checks, within the same Undo. After an unknown outcome, poll the library job or query `sketchup_get_command_result`; never automatically repeat creation.

## Preserve quality and verify

- Both recessed pulls are centered vertically in the **outside stiles**: left leaf's left stile, right leaf's right stile. Keep them away from the overlapping meeting stiles; keep the tracks separated for clearance.
- The entire object has four groups: one parent, fixed frame, left sash, right sash. Each sash contains its own closed glass volume without another nested group. Avoid individual bar/bead/handle groups.
- Native cleanup dissolves compatible untextured coplanar seams and hides compatible textured seams to preserve UV regions. Keep real profile corners, material boundaries and track detail.
- Check returned outer model bounds against X/Y/Z dimensions, all three sections `solid=true`, group structure, cleanup counts and timing. A single follow-up parent/children query is sufficient when needed; do not enumerate every surface.
- State that one Undo reverts the whole creation/replacement. Native bounds/solidity checks do not prove appearance: use a user screenshot or approved viewport access for a visual claim. Do not change the camera merely to validate bounds.

The source recipe matches the previously modeled and optimized 0.6.3 prototype at default dimensions. The Probe JavaScript example is checked against that prototype face-by-face, including material roles. New 0.8.0 library execution still needs installed native acceptance; API-double regression results are separate evidence.
