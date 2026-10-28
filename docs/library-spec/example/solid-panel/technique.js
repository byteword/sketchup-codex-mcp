// Design specimen: pure JS entry point; does not access SketchUp or the filesystem.
function build(ctx) {
  var p = ctx.params, w = p.width_mm, h = p.height_mm, d = p.depth_mm;
  return {
    format_version: "sketchup-plan/1",
    units: "mm",
    root: "assembly",
    nodes: [
      { kind: "group", id: "assembly", name: "Panel example" },
      {
        kind: "mesh", id: "panel", name: "Panel", parent: "assembly",
        points_mm: [[0,0,0],[w,0,0],[w,d,0],[0,d,0],
                    [0,0,h],[w,0,h],[w,d,h],[0,d,h]],
        faces: [[0,3,2,1],[4,5,6,7],[0,1,5,4],
                [1,2,6,5],[2,3,7,6],[3,0,4,7]],
        face_roles: ["panel","panel","panel","panel","panel","panel"],
        solid: true, cleanup: "none"
      }
    ],
    assertions: [
      { kind: "bounds", node: "assembly",
        min_mm: [0,0,0], max_mm: [w,d,h], tolerance_mm: 0.001 },
      { kind: "solid", node: "panel" }
    ]
  };
}
