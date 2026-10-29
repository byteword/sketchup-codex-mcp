"""Verify design specimens only; this does not implement Probe, Jint or SketchUp."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
from collections import defaultdict
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def revision(files):
    h = hashlib.sha256(b"probe-technique/1\n")
    for name, content in sorted(files.items()):
        content = content.replace(b"\r\n", b"\n")
        assert not content.startswith(b"\xef\xbb\xbf")
        h.update(name.encode("utf-8") + b"\0" + str(len(content)).encode("ascii") + b"\0" + content)
    return "sha256:" + h.hexdigest()


def verify_mesh(mesh):
    points = mesh["points_mm"]
    edges = defaultdict(list)
    volume = 0.0
    for face in mesh["faces"]:
        assert all(0 <= i < len(points) for i in face)
        for a, b in zip(face, face[1:] + face[:1]):
            edges[tuple(sorted((a, b)))].append((a, b))
        a = points[face[0]]
        for j, k in zip(face[1:], face[2:]):
            b, c = points[j], points[k]
            volume += (a[0]*(b[1]*c[2]-b[2]*c[1]) + a[1]*(b[2]*c[0]-b[0]*c[2]) + a[2]*(b[0]*c[1]-b[1]*c[0])) / 6
    assert all(len(e) == 2 and e[0] == e[1][::-1] for e in edges.values())
    assert volume > 0
    assert len(mesh["faces"]) == len(mesh["face_roles"])
    return volume


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default="node")
    args = parser.parse_args()
    for name in ("manifest", "plan", "report", "tests", "package"):
        Draft202012Validator.check_schema(read(ROOT / (name + ".schema.json")))
    package = ROOT / "example" / "solid-panel"
    manifest = read(package / "manifest.json")
    Draft202012Validator(read(ROOT / "manifest.schema.json")).validate(manifest)
    inputs = read(package / manifest["input_schema"])
    Draft202012Validator.check_schema(inputs)
    validator = Draft202012Validator(inputs)
    fixtures = read(package / manifest["tests"])
    Draft202012Validator(read(ROOT / "tests.schema.json")).validate(fixtures)
    source = (package / manifest["entrypoint"]).read_text(encoding="utf-8")
    harness = """
const vm = require('vm');
const fs = require('fs');
const request = JSON.parse(fs.readFileSync(0, 'utf8'));
const scope = { invocation: { params: request.params, inputs: {} } };
const output = vm.runInNewContext(request.source + '\\nJSON.stringify(build(invocation));',
                                  scope, {timeout: 1000, displayErrors: false});
process.stdout.write(output);
"""
    positive = negative = 0
    plan_validator = Draft202012Validator(read(ROOT / "plan.schema.json"))
    for case in fixtures["cases"]:
        params = copy.deepcopy(case["params"])
        for key, schema in inputs["properties"].items():
            if key not in params and key not in inputs["required"] and "default" in schema:
                params[key] = copy.deepcopy(schema["default"])
        errors = list(validator.iter_errors(params))
        expect = case["expect"]
        if not expect["ok"]:
            assert errors, case["id"]
            pointers = set()
            for error in errors:
                path = "/" + "/".join(map(str, error.absolute_path))
                pointers.add(path)
                if error.validator == "additionalProperties":
                    pointers.update("/" + key for key in params if key not in inputs["properties"])
            assert expect["code"] == "input_invalid" and expect["path"] in pointers
            negative += 1
            continue
        assert not errors, errors
        response = subprocess.run(
            [args.node, "-e", harness], input=json.dumps(dict(source=source, params=params)),
            text=True, capture_output=True, check=True, timeout=5)
        plan = json.loads(response.stdout)
        plan_validator.validate(plan)
        known = set()
        mesh_faces = 0
        points = []
        for node in plan["nodes"]:
            assert node["id"] not in known
            if node["id"] == plan["root"]:
                assert node["kind"] == "group" and "parent" not in node
            else:
                assert node["parent"] in known
            known.add(node["id"])
            if node["kind"] == "mesh":
                volume = verify_mesh(node)
                assert abs(volume - params["width_mm"]*params["height_mm"]*params["depth_mm"]) < 0.001
                assert set(node["face_roles"]) <= set(manifest["material_roles"])
                points.extend(node["points_mm"])
                mesh_faces += len(node["faces"])
        bounds = {"min": [min(p[i] for p in points) for i in range(3)],
                  "max": [max(p[i] for p in points) for i in range(3)]}
        assert bounds == expect["bounds_mm"]
        assert len(plan["nodes"]) == expect["groups"]
        assert mesh_faces == expect["mesh_faces"]
        # Structural rejection is part of this design specimen.
        broken = copy.deepcopy(plan)
        broken["nodes"][1]["ruby"] = "arbitrary code"
        assert not plan_validator.is_valid(broken)
        positive += 1
    files = {p.name: p.read_bytes() for p in package.iterdir() if p.is_file()}
    digest = revision(files)
    vector_path = ROOT / "revision-vector.json"
    expected_digest = read(vector_path)
    assert expected_digest["revision"] == digest
    assert expected_digest["files"] == sorted(files)
    assert revision(dict(reversed(list(files.items())))) == digest
    assert revision({k: v.replace(b"\n", b"\r\n") for k, v in files.items()}) == digest
    changed = dict(files)
    changed["technique.js"] += b"// changed\n"
    assert revision(changed) != digest
    print("Design specimens: 5 schemas valid; " + str(positive) +
          " positive plans / closed outward meshes; " + str(negative) +
          " rejected inputs; unexpected code fields rejected; revision vector verified.")
    print("Example revision: " + digest)
    print("Scope: Python jsonschema + Node JS only. Probe/Jint/native integration not tested.")


if __name__ == "__main__":
    main()
