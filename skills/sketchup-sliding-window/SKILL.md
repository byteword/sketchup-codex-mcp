---
name: sketchup-sliding-window
description: "Create or replace a two-panel sliding window in connected SketchUp from dimensions, opening and existing materials, preserving the optimized frame, outer-stile recessed pulls and simple render structure. Use for similar parametric window modeling requests."
---

# SketchUp two-panel sliding window

Use the installed `sketchup_create_sliding_window` tool (adapter and extension 0.7.0+). The geometry recipe lives in the plugin; this skill supplies design decisions and verification. Check actual tool availability first. If unavailable, explain the required runtime update; do not rebuild the window with hundreds of face/edge calls or arbitrary Ruby.

## Interpret the request

- Dimensions are **width × height × depth**, in mm. Model axes are **X=width, Y=depth, Z=height**, with origin at the outer bottom-left-front corner. This recipe is aligned to model axes even inside a rotated/scaled edit parent.
- “가로 2분할” here means two equal-width leaves side by side, sliding along X on separate depth tracks. Defaults: outer frame width 40, sash width 35, glass thickness 6, meeting overlap 40 mm; both leaves closed.
- `open_sash=left` moves the left leaf rightward; `right` moves the right leaf leftward. `open_fraction` is 0–1 of available travel, **not** a fraction of total window width. Keep `none,0` for a closed window.
- Reuse a supplied reference's existing materials. Read material resources once, preserve exact names (including leading spaces), and map frame/glass/seal/hardware separately. Do not change shared material definitions merely to fit this window.
- [assets/defaults.json](assets/defaults.json) stores the approved 1200×900×100 example and its material hints. These names are hints, not universally available materials; resolve them in the current model. Origin, replacement ID and session IDs are deliberately omitted.
- The native command accepts width 600–6000, height 400–3600, depth 80–300 mm, with cross-field clearance checks. Use the installed schema and returned validation for other parameters. A different window family, uneven split, extra leaves or detailed fabrication hardware needs another recipe.

## Execute

Discover instances with `sketchup_list_instances`; resolve the current session/model. Read current edit context and next command ID immediately before each mutation. Use the local panel's human execution grant; reuse authorization already given for this task. No implicit edit-path changes.

Send one typed `sketchup_create_sliding_window` request containing name, origin, dimensions, materials and desired opening. Optional `dry_run` validates without geometry but consumes a command ID. Execution needs its own fresh ID.

For “redraw/replace that window”, resolve the exact direct-child target and provide `replace_entity_id`. The old object is removed only after the replacement passes native checks, in the same Undo operation. Preserve a separate user reference. Creating a new window leaves `replace_entity_id` absent.

After an unknown outcome, query `sketchup_get_command_result` and current objects; do not automatically repeat a creation request.

## Preserve quality and verify

- Both recessed pulls are centered vertically in the **outside stiles**: left leaf's left stile, right leaf's right stile. Keep them away from the overlapping meeting stiles; keep the tracks separated for clearance.
- The entire object has four groups: one parent, fixed frame, left sash, right sash. Each sash contains its own closed glass volume without another nested group. Avoid individual bar/bead/handle groups.
- Native cleanup dissolves compatible untextured coplanar seams and hides compatible textured seams to preserve UV regions. Keep real profile corners, material boundaries and track detail.
- Check returned outer model bounds against X/Y/Z dimensions, all three sections `solid=true`, group structure, cleanup counts and timing. A single follow-up parent/children query is sufficient when needed; do not enumerate every surface.
- State that one Undo reverts the whole creation/replacement. Native bounds/solidity checks do not prove appearance: use a user screenshot or approved viewport access for a visual claim. Do not change the camera merely to validate bounds.

The source recipe matches the previously modeled and optimized 0.6.3 prototype at default dimensions. The new 0.7.0 command still requires its own installed native acceptance; API-double regression results are separate evidence.
