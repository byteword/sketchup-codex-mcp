"""Production library service + embedded Jint worker. No user SketchUp connection."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid

EXE = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]
ROOT = Path(__file__).resolve().parents[1]


class LibraryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="probe-library-")
        self.start()

    def start(self):
        self.proc = subprocess.Popen([EXE, self.directory.name], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=lambda: [self.lines.put(line) for line in self.proc.stdout], daemon=True)
        self.reader.start()

    def stop(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=8)
        error = self.proc.stderr.read().decode("utf-8", errors="replace")
        self.reader.join(2)
        self.proc.stdout.close()
        self.proc.stderr.close()
        self.assertEqual(0, self.proc.returncode, error)

    def tearDown(self):
        self.stop()
        self.directory.cleanup()

    def call(self, name, **args):
        self.proc.stdin.write((json.dumps(dict(tool="sketchup_library_" + name, arguments=args),
                                          ensure_ascii=False) + "\n").encode("utf-8"))
        self.proc.stdin.flush()
        return json.loads(self.lines.get(timeout=15))

    def ok(self, result):
        self.assertTrue(result["ok"], result)
        return result["data"]

    def package(self, id="demo.solid-panel", source=None, dependencies=None):
        folder = ROOT / "docs/library-spec/example/solid-panel"
        files = {p.name: p.read_text(encoding="utf-8") for p in folder.iterdir() if p.is_file()}
        manifest = json.loads(files["manifest.json"])
        manifest["id"] = id
        if dependencies is not None:
            manifest["dependencies"] = dependencies
        files["manifest.json"] = json.dumps(manifest, ensure_ascii=False)
        if source is not None:
            files["technique.js"] = source
        return files

    def save(self, id="demo.solid-panel", base=None, files=None, request=None, library="user"):
        return self.call("save", request_id=request or str(uuid.uuid4()), library_id=library,
                         technique_id=id, base_revision=base, files=files or self.package(id),
                         change_summary="test change")

    def wait(self, response):
        job = self.ok(response)["job_id"]
        for _ in range(750):
            data = self.ok(self.call("job", action="get", job_id=job))
            if data["state"] not in ("queued", "running"):
                return data
            time.sleep(0.02)
        self.fail("job did not finish")

    def verify(self, ref, **fields):
        return self.wait(self.call("run", request_id=str(uuid.uuid4()), mode="verify", **ref, **fields))

    def export(self, refs):
        data = self.ok(self.call("transfer", action="export", selections=refs,
                                 package_info=dict(title="Shared techniques")))
        content = bytearray()
        offset = 0
        while True:
            chunk = self.ok(self.call("transfer", action="read_export", bundle_id=data["bundle_id"],
                                     offset=offset, max_bytes=16384))
            content.extend(base64.b64decode(chunk["data_base64"]))
            if chunk["next_offset"] is None:
                break
            offset = chunk["next_offset"]
        self.assertEqual(data["digest"], "sha256:" + hashlib.sha256(content).hexdigest())
        return bytes(content)

    def upload(self, content):
        data = self.ok(self.call("transfer", action="open_import", request_id=str(uuid.uuid4()),
                                 total_bytes=len(content), digest="sha256:" + hashlib.sha256(content).hexdigest()))
        for offset in range(0, len(content), 16384):
            self.ok(self.call("transfer", action="write_chunk", upload_id=data["upload_id"], offset=offset,
                              data_base64=base64.b64encode(content[offset:offset+16384]).decode()))
        return data["upload_id"]

    def operations_files(self, method="draw_geometry", arguments=None):
        files = self.package()
        m = json.loads(files["manifest.json"])
        m.update(output="sketchup-operations/1", requires=["commands/1", "verify/1"], material_roles=[])
        files["manifest.json"] = json.dumps(m)
        plan = dict(format_version="sketchup-operations/1", units="mm", steps=[dict(method=method,
            arguments=arguments or dict(kind="polyline", options=dict(points_mm=[[0,0,0],[1200,0,0]])))])
        files["technique.js"] = "function build(ctx) { return " + json.dumps(plan) + "; };"
        files["tests.json"] = json.dumps(dict(format_version="probe-tests/1", cases=[dict(id="raw",params={},expect=dict(ok=True,operation_count=1))]))
        return files

    def test_operations_plan_verified_and_packaged(self):
        ref = self.ok(self.save(files=self.operations_files()))["technique_ref"]
        verified = self.verify(ref)
        self.assertEqual("succeeded", verified["state"], verified)
        planned = self.wait(self.call("run", request_id=str(uuid.uuid4()), mode="plan", params={}, **ref))
        self.assertEqual("succeeded", planned["state"], planned)
        self.assertEqual(1, planned["result"]["summary"]["operation_count"])
        self.assertIn("draw_geometry", planned["result"]["summary"]["methods"])
        self.assertTrue(self.export([ref]))
        schema = self.ok(self.call("get", kind="authoring", sections=["operations_schema"]))["operations_schema"]
        self.assertIn("steps", schema["properties"])

    def test_bundled_raw_drawing_example(self):
        files=self.ok(self.call("get",kind="authoring",sections=["operations_example"]))["operations_files"]
        ref=self.ok(self.save(id="demo.raw-drawing",files=files))["technique_ref"]
        result=self.verify(ref)
        self.assertEqual("succeeded",result["state"],result)
        self.assertEqual(3,len(result["result"]["cases"]))

    def test_operations_reject_non_model_effects_and_transport_override(self):
        base = None
        for method, args in [("configure_camera",{}),("eval_ruby",{}),("draw_geometry",dict(kind="points",options=dict(points_mm=[[0,0,0]]),expected_context=[]))]:
            ref = self.ok(self.save(base=base, files=self.operations_files(method,args)))["technique_ref"]
            base = ref["revision"]
            result = self.verify(ref)
            self.assertEqual("failed",result["state"],result)
            self.assertEqual("plan_invalid",result["result"]["cases"][0]["diagnostic"]["code"],result)

    def test_authoring_bootstrap_with_empty_library(self):
        guide = self.ok(self.call("get", kind="authoring"))
        self.assertEqual("probe-technique/1", guide["format_version"])
        self.assertIn("workflow", guide["profile"])
        ref = self.ok(self.save(files=guide["files"]))["technique_ref"]
        self.assertEqual("succeeded", self.verify(ref)["state"])
        schema = self.ok(self.call("get", kind="authoring", sections=["manifest_schema"]))["manifest_schema"]
        self.assertIn("required", schema)

    def test_sliding_window_script_matches_approved_prototype(self):
        guide = self.ok(self.call("get", kind="authoring", sections=["window_example"]))
        ref = self.ok(self.save(id="byteword.sliding-window", files=guide["window_files"]))["technique_ref"]
        checked = self.verify(ref)
        self.assertEqual("succeeded", checked["state"], checked)
        self.assertEqual(5, len(checked["result"]["cases"]))
        planned = self.wait(self.call("run", request_id=str(uuid.uuid4()), mode="plan",
            params=dict(width_mm=1200, height_mm=900, depth_mm=100), **ref))
        self.assertEqual("succeeded", planned["state"], planned)
        record = json.loads((Path(self.directory.name) / "plans" /
            (planned["result"]["plan_id"] + ".json")).read_text(encoding="utf-8"))
        golden = json.loads((ROOT / "tests/fixtures/sliding-window-prototype.json").read_text(encoding="utf-8"))
        def surfaces(points, faces, roles):
            return sorted((role, tuple(sorted(tuple(round(v, 4) for v in points[i]) for i in face)))
                          for role, face in zip(roles, faces))
        actual = record["plan"]["nodes"][1:]
        for expected, node in zip(golden, actual):
            self.assertEqual(expected["section"], node["id"])
            self.assertEqual(surfaces(expected["points"], expected["faces"], expected["roles"]),
                             surfaces(node["points_mm"], node["faces"], node["face_roles"]))

    def test_create_verify_activate_plan_and_restart(self):
        saved = self.ok(self.save())
        ref = saved["technique_ref"]
        self.assertEqual([], self.ok(self.call("list"))["items"])
        job = self.verify(ref, activate_if_passed=True, expected_active_revision=None)
        self.assertEqual("succeeded", job["state"], job)
        self.assertEqual(6, len(job["result"]["cases"]))
        self.assertEqual(1, len(self.ok(self.call("list"))["items"]))
        planned = self.wait(self.call("run", request_id=str(uuid.uuid4()), mode="plan", params={}, **ref))
        self.assertEqual("succeeded", planned["state"], planned)
        self.assertEqual(2, planned["result"]["summary"]["group_count"])
        self.stop()
        self.start()
        self.assertEqual(ref["revision"], self.ok(self.call("get", technique_id=ref["technique_id"]))["active"])
        self.assertEqual("succeeded", self.ok(self.call("job", action="get", job_id=planned["job_id"]))["state"])

    def test_save_replay_conflict_and_failed_revision_keeps_active(self):
        request = str(uuid.uuid4())
        first = self.ok(self.save(request=request))
        again = self.ok(self.save(request=request))
        self.assertEqual(first, again)
        self.assertEqual("request_id_conflict", self.save(request=request, files=self.package(source="bad"))["error"]["code"])
        ref = first["technique_ref"]
        self.assertEqual("succeeded", self.verify(ref, activate_if_passed=True, expected_active_revision=None)["state"])
        self.assertEqual("revision_conflict", self.save()["error"]["code"])
        broken = self.ok(self.save(base=ref["revision"], files=self.package(source="function build(ctx) {")))
        failed = self.verify(broken["technique_ref"])
        self.assertEqual("failed", failed["state"])
        self.assertEqual(ref["revision"], self.ok(self.call("get", technique_id=ref["technique_id"]))["active"])
        self.assertEqual("active_conflict", self.call("manage", action="activate", request_id=str(uuid.uuid4()),
                                                    **ref, expected_active_revision=None)["error"]["code"])

    def test_multiple_roots_selective_import_and_no_automatic_execution(self):
        a = self.ok(self.save())["technique_ref"]
        b = self.ok(self.save("demo.other-panel"))["technique_ref"]
        content = self.export([a, b, a])
        upload = self.upload(content)
        library = self.ok(self.call("manage", action="create_library", request_id=str(uuid.uuid4()),
                                    title="Recipient"))["library_id"]
        inspected = self.ok(self.call("transfer", action="inspect_import", upload_id=upload, library_id=library,
                                       selected_roots=[dict(technique_id=b["technique_id"], revision=b["revision"])],
                                       conflict_policy="stage"))
        self.assertEqual(1, inspected["required_revision_count"])
        self.assertFalse(inspected["code_executed"])
        commit_args = dict(action="commit_import", request_id=str(uuid.uuid4()), upload_id=upload,
                           import_plan_id=inspected["import_plan_id"], library_id=library, conflict_policy="stage")
        result = self.ok(self.call("transfer", **commit_args))
        self.assertEqual(1, len(result["imported"]))
        self.assertEqual(result, self.ok(self.call("transfer", **commit_args)))
        self.assertFalse(result["active_changed"])
        self.assertEqual([], self.ok(self.call("list", library_id=library))["items"])
        self.assertEqual(b["technique_id"], self.ok(self.call("list", library_id=library, state="all"))["items"][0]["technique_ref"]["technique_id"])

    def test_import_updates_clean_workspace_and_preserves_dirty_files(self):
        first = self.ok(self.save())["technique_ref"]
        one = self.export([first])
        library = self.ok(self.call("manage", action="create_library", request_id=str(uuid.uuid4()),
                                    title="Workspace recipient"))["library_id"]
        def install(content):
            upload = self.upload(content)
            preview = self.ok(self.call("transfer", action="inspect_import", upload_id=upload,
                library_id=library, conflict_policy="stage"))
            return self.ok(self.call("transfer", action="commit_import", request_id=str(uuid.uuid4()),
                upload_id=upload, library_id=library, conflict_policy="stage", import_plan_id=preview["import_plan_id"]))
        install(one)
        files = self.package()
        files["technique.js"] += "\n// Version two\n"
        second = self.ok(self.save(base=first["revision"], files=files))["technique_ref"]
        install(self.export([second]))
        info = self.ok(self.call("get", library_id=library, technique_id=first["technique_id"]))
        source = Path(info["workspace_path"]) / "technique.js"
        self.assertEqual(files["technique.js"], source.read_text(encoding="utf-8"))
        # Marker records the synchronized revision. Dirty edits are never overwritten.
        source.write_text(files["technique.js"] + "// Keep local edits\n", encoding="utf-8")
        install(one)
        self.assertIn("Keep local edits", source.read_text(encoding="utf-8"))

    def test_missing_dependency_and_tampered_archive_rejected(self):
        a = self.ok(self.save())["technique_ref"]
        content = self.export([a])
        broken = b"not a ZIP"
        upload = self.upload(broken)
        self.assertFalse(self.call("transfer", action="inspect_import", upload_id=upload)["ok"])
        files = self.package("demo.dependent", dependencies=[dict(alias="panel", technique_id=a["technique_id"],
                                                               revision="sha256:"+"0"*64)])
        dependent = self.ok(self.save("demo.dependent", files=files))["technique_ref"]
        self.assertEqual("failed", self.verify(dependent)["state"])

    def test_shared_dependency_import_closure_and_fork(self):
        base = self.ok(self.save())["technique_ref"]
        dependency = [dict(alias="base", technique_id=base["technique_id"], revision=base["revision"])]
        source = "function build(ctx){ return ctx.call('base',ctx.params); }"
        a = self.ok(self.save("demo.linked-a", files=self.package("demo.linked-a", source, dependency)))["technique_ref"]
        b = self.ok(self.save("demo.linked-b", files=self.package("demo.linked-b", source, dependency)))["technique_ref"]
        self.assertEqual("succeeded", self.verify(a)["state"])
        content = self.export([a, b])
        upload = self.upload(content)
        target = self.ok(self.call("manage", action="create_library", request_id=str(uuid.uuid4()), title="Forks"))["library_id"]
        inspected = self.ok(self.call("transfer", action="inspect_import", upload_id=upload, library_id=target,
            selected_roots=[dict(technique_id=a["technique_id"], revision=a["revision"])], conflict_policy="fork",
            id_map={"demo.linked-a":"fork.linked-a","demo.solid-panel":"fork.base"}))
        self.assertEqual(2, inspected["required_revision_count"])
        imported = self.ok(self.call("transfer", action="commit_import", request_id=str(uuid.uuid4()),
            upload_id=upload, import_plan_id=inspected["import_plan_id"], library_id=target, conflict_policy="fork"))
        refs = {entry["technique_ref"]["technique_id"]:entry["technique_ref"] for entry in imported["imported"]}
        self.assertEqual({"fork.base", "fork.linked-a"}, set(refs))
        self.assertNotEqual(base["revision"], refs["fork.base"]["revision"])
        self.assertEqual("succeeded", self.verify(refs["fork.linked-a"])["state"])

    def test_source_unicode_state_conflict_cursor_and_archive(self):
        first = self.ok(self.save())["technique_ref"]
        self.assertEqual("succeeded", self.verify(first, activate_if_passed=True, expected_active_revision=None)["state"])
        other = self.ok(self.save("demo.other"))["technique_ref"]
        listed = self.ok(self.call("list", state="all", limit=1))
        self.assertIsNotNone(listed["next_cursor"])
        self.ok(self.save("demo.third"))
        stale = self.call("list", state="all", limit=1, cursor=listed["next_cursor"])
        self.assertEqual("catalog_changed", stale["error"]["code"])
        files = self.package()
        files["technique.js"] = files["technique.js"].replace('"Panel example"', '"한글 창🙂"')
        changed = self.ok(self.save(base=first["revision"], files=files))["technique_ref"]
        checked = self.verify(changed)
        self.assertEqual("succeeded", checked["state"], checked)
        self.ok(self.call("manage", action="archive", request_id=str(uuid.uuid4()), technique_id=first["technique_id"],
                          expected_active_revision=first["revision"]))
        blocked = self.call("run", request_id=str(uuid.uuid4()), mode="plan", params={}, **changed)
        self.assertEqual("technique_archived", blocked["error"]["code"])
        self.ok(self.call("manage", action="restore", request_id=str(uuid.uuid4()), technique_id=first["technique_id"],
                          expected_active_revision=first["revision"]))

    def test_import_rechecks_local_state_and_chunk_replay(self):
        ref = self.ok(self.save())["technique_ref"]
        content = self.export([ref])
        upload = self.upload(content)
        self.ok(self.call("transfer", action="write_chunk", upload_id=upload, offset=0,
                          data_base64=base64.b64encode(content[:16384]).decode()))
        wrong = self.call("transfer", action="write_chunk", upload_id=upload, offset=0,
                          data_base64=base64.b64encode(b"wrong").decode())
        self.assertEqual("upload_chunk_conflict", wrong["error"]["code"])
        planned = self.ok(self.call("transfer", action="inspect_import", upload_id=upload, conflict_policy="stage"))
        self.ok(self.save(base=ref["revision"], files=self.package(source="function build(ctx){return {}; }")))
        result = self.call("transfer", action="commit_import", request_id=str(uuid.uuid4()), upload_id=upload,
                           import_plan_id=planned["import_plan_id"], library_id="user", conflict_policy="stage")
        self.assertEqual("import_conflict", result["error"]["code"])

    def test_archive_path_and_content_hash_validation(self):
        import io
        import zipfile
        ref = self.ok(self.save())["technique_ref"]
        content = self.export([ref])
        output = io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(content)) as original, zipfile.ZipFile(output, "w") as edited:
            for name in original.namelist():
                data = original.read(name)
                if name.endswith("/technique.js"):
                    data += b"// tampered"
                edited.writestr(name, data)
        upload = self.upload(output.getvalue())
        error = self.call("transfer", action="inspect_import", upload_id=upload)
        self.assertEqual("package_digest_mismatch", error["error"]["code"])
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as edited:
            edited.writestr("../outside.txt", "no")
        upload = self.upload(output.getvalue())
        error = self.call("transfer", action="inspect_import", upload_id=upload)
        self.assertEqual("package_path_invalid", error["error"]["code"])

    def test_working_files_reload_without_restart_and_optional_auto_activation(self):
        ref = self.ok(self.save())["technique_ref"]
        self.assertEqual("succeeded", self.verify(ref, activate_if_passed=True, expected_active_revision=None)["state"])
        metadata = self.ok(self.call("get", technique_id=ref["technique_id"]))
        workspace = Path(metadata["workspace_path"])
        source = workspace / "technique.js"
        source.write_text(source.read_text(encoding="utf-8").replace("Panel example", "Working copy"), encoding="utf-8")
        for _ in range(120):
            metadata = self.ok(self.call("get", technique_id=ref["technique_id"]))
            if metadata["head"] != ref["revision"]:
                break
            time.sleep(.05)
        self.assertNotEqual(ref["revision"], metadata["head"])
        self.assertEqual(ref["revision"], metadata["active"])
        self.ok(self.call("manage", action="configure_library", request_id=str(uuid.uuid4()),
                          update_policy="after_checks"))
        source.write_text(source.read_text(encoding="utf-8").replace("Working copy", "Checked working copy"), encoding="utf-8")
        for _ in range(200):
            metadata = self.ok(self.call("get", technique_id=ref["technique_id"]))
            if metadata["active"] == metadata["head"] and metadata["active"] != ref["revision"]:
                break
            time.sleep(.05)
        self.assertEqual(metadata["head"], metadata["active"])
        good = metadata["active"]
        source.write_text("function build(ctx){", encoding="utf-8")
        for _ in range(100):
            metadata = self.ok(self.call("get", technique_id=ref["technique_id"]))
            if metadata["head"] != good:
                break
            time.sleep(.05)
        self.assertNotEqual(good, metadata["head"])
        bad = metadata["head"]
        for _ in range(200):
            history = self.ok(self.call("get", technique_id=ref["technique_id"], sections=["history"]))["history"]["items"]
            verdict = next(x for x in history if x["revision"] == bad)["validation"]["offline"]
            if verdict == "failed":
                break
            time.sleep(.05)
        self.assertEqual("failed", verdict)
        self.assertEqual(good, self.ok(self.call("get", technique_id=ref["technique_id"]))["active"])

    def test_long_source_byte_pages_and_plan_integrity(self):
        source = "//" + "가" * 15000
        ref = self.ok(self.save(files=self.package(source=source)))["technique_ref"]
        info = self.ok(self.call("get", technique_id=ref["technique_id"], sections=["source"]))
        self.assertEqual("utf8-base64", info["source"]["format"])
        content = bytearray(base64.b64decode(info["source"]["data_base64"]))
        offset = info["source"]["next_byte_offset"]
        while offset is not None:
            info = self.ok(self.call("get", technique_id=ref["technique_id"], sections=["source"],
                source_page=dict(file="technique.js", byte_offset=offset, max_bytes=8192)))
            content.extend(base64.b64decode(info["source"]["data_base64"]))
            offset = info["source"]["next_byte_offset"]
        self.assertEqual(source, content.decode("utf-8"))
        ref = self.ok(self.save(base=ref["revision"]))["technique_ref"]
        plan = self.wait(self.call("run", request_id=str(uuid.uuid4()), mode="plan", params={}, **ref))["result"]
        path = Path(self.directory.name) / "plans" / (plan["plan_id"] + ".json")
        record = json.loads(path.read_text(encoding="utf-8"))
        record["plan"]["nodes"][0]["name"] = "Tampered"
        path.write_text(json.dumps(record), encoding="utf-8")
        result = self.call("run", request_id=str(uuid.uuid4()), mode="apply", plan_id=plan["plan_id"],
            plan_hash=plan["plan_hash"], session_id=str(uuid.uuid4()), model_id=str(uuid.uuid4()),
            expected_context=[], command_id="test:1")
        self.assertEqual("plan_corrupt", result["error"]["code"])

    def test_budget_schema_and_source_isolation(self):
        bad = self.package()
        schema = json.loads(bad["inputs.schema.json"])
        schema["additionalProperties"] = True
        bad["inputs.schema.json"] = json.dumps(schema)
        self.assertEqual("schema_unsupported", self.save(files=bad)["error"]["code"])
        files = self.package(source="function build(ctx){while(true){} }")
        ref = self.ok(self.save(files=files))["technique_ref"]
        started = time.monotonic()
        self.assertEqual("failed", self.verify(ref)["state"])
        self.assertLess(time.monotonic()-started, 15)
        self.assertTrue(self.call("list", kind="libraries")["ok"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
