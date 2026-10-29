"""Production MCP -> isolated production control hub -> actual Win32 Ruby peers.
HeadlessHub must be running. Arguments: Ruby executable and optional host arguments.
"""
import json
import pathlib
import queue
import re
import subprocess
import sys
import threading
import time
import unittest
import uuid

RUBY = sys.argv[1:]
sys.argv = sys.argv[:1]
ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = re.search(r'public const string Version = "([^"]+)"', (ROOT / 'shared/BuildInfo.cs').read_text(encoding='utf-8')).group(1)


def capture(stream):
    output = queue.Queue()
    def read():
        for line in stream:
            output.put(json.loads(line.decode('utf-8')))
    thread = threading.Thread(target=read, daemon=True)
    thread.start()
    return output, thread


class WindowsMcpTests(unittest.TestCase):
    def setUp(self):
        self.control = ROOT / 'dist' / ('fixture-' + str(uuid.uuid4()) + '.json')
        self.sequence = 0
        self.write_control({})
        self.fixture = subprocess.Popen(RUBY + ['tests/windows_session_fixture.rb', str(self.control)],
                                        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.fixture_lines, self.fixture_reader = capture(self.fixture.stdout)
        self.adapter = None
        self.addCleanup(self.cleanup_fixture)
        self.instances = self.fixture_lines.get(timeout=10)['instances']
        self.request_id = 0
        self.start_adapter()
        deadline = time.monotonic() + 5
        while len(self.tool('sketchup_list_instances')['instances']) != 2:
            if time.monotonic() > deadline:
                self.fail('Ruby peers did not register')
            time.sleep(.02)

    def write_control(self, fields):
        data = dict(fields, sequence=self.sequence)
        temporary = self.control.with_suffix('.tmp')
        temporary.write_text(json.dumps(data), encoding='utf-8')
        # Ruby's short File.read can briefly hold a Windows handle without
        # delete-sharing. Retry only this idempotent test-control replacement.
        deadline = time.monotonic() + 2
        while True:
            try:
                temporary.replace(self.control)
                break
            except PermissionError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(.01)

    def command(self, **fields):
        self.sequence += 1
        self.write_control(fields)
        while True:
            result = self.fixture_lines.get(timeout=5)
            if result.get('ack') == self.sequence:
                self.instances = result['instances']
                return

    def start_adapter(self):
        self.adapter = subprocess.Popen([str(ROOT / 'dist/SketchUpMcp.Test.exe')],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.lines, self.reader = capture(self.adapter.stdout)
        self.errors = []
        self.error_reader = threading.Thread(target=lambda: self.errors.append(self.adapter.stderr.read()), daemon=True)
        self.error_reader.start()
        result = self.rpc('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {},
                                        'clientInfo': {'name': 'windows-integration', 'version': '1'}})
        self.assertEqual(VERSION, result['result']['serverInfo']['version'])
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

    def stop_adapter(self):
        if self.adapter is None:
            return
        self.adapter.stdin.close()
        try:
            self.adapter.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.adapter.kill()
            self.adapter.wait()
            self.fail('Adapter did not exit on EOF')
        finally:
            self.reader.join(timeout=2)
            self.error_reader.join(timeout=2)
            self.adapter.stdout.close()
            self.adapter.stderr.close()
            self.adapter = None

    def cleanup_fixture(self):
        try:
            self.stop_adapter()
        finally:
            self.sequence += 1
            try:
                self.write_control({'stop': True})
            except OSError:
                # Cleanup must run even when setUp or control-file writing failed.
                if self.fixture.poll() is None:
                    self.fixture.kill()
            try:
                self.fixture.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.fixture.kill()
                self.fixture.wait()
            errors = self.fixture.stderr.read().decode('utf-8', errors='replace')
            self.fixture_reader.join(timeout=2)
            self.fixture.stdout.close()
            self.fixture.stderr.close()
            self.control.unlink(missing_ok=True)
            self.assertEqual(0, self.fixture.returncode, errors)

    def send(self, message):
        self.adapter.stdin.write(json.dumps(message, ensure_ascii=False).encode('utf-8') + b'\n')
        self.adapter.stdin.flush()

    def rpc(self, method, params):
        self.request_id += 1
        self.send({'jsonrpc': '2.0', 'id': self.request_id, 'method': method, 'params': params})
        result = self.lines.get(timeout=12)
        self.assertEqual(self.request_id, result['id'])
        self.assertNotIn('error', result)
        return result

    def tool(self, name, args=None, error=False):
        result = self.rpc('tools/call', {'name': name, 'arguments': args or {}})['result']
        self.assertEqual(error, result['isError'], result)
        return json.loads(result['content'][0]['text'])

    def target(self, index, model=False):
        keys = ['session_id', 'model_id'] if model else ['session_id']
        return {key: self.instances[index][key] for key in keys}

    def library_wait(self, response):
        self.assertTrue(response["ok"], response)
        job_id = response["data"]["job_id"]
        for _ in range(150):
            job = self.tool("sketchup_library_job", dict(action="get", job_id=job_id, wait_ms=100))["data"]
            if job["state"] not in ("queued", "running"):
                return job
        self.fail("library job did not finish")

    def library_panel(self):
        folder = ROOT / "docs/library-spec/example/solid-panel"
        files = {p.name: p.read_text(encoding="utf-8") for p in folder.iterdir() if p.is_file()}
        manifest = json.loads(files["manifest.json"])
        manifest["id"] = "integration.panel-" + uuid.uuid4().hex[:12]
        files["manifest.json"] = json.dumps(manifest, ensure_ascii=False)
        saved = self.tool("sketchup_library_save", dict(request_id=str(uuid.uuid4()), technique_id=manifest["id"],
                         base_revision=None, files=files, change_summary="native pipe integration"))
        self.assertTrue(saved["ok"], saved)
        return saved["data"]["technique_ref"]

    def test_toolbar_stop_reaches_worker_and_is_scoped_to_model(self):
        folder = ROOT / "docs/library-spec/example/solid-panel"
        files = {p.name: p.read_text(encoding="utf-8") for p in folder.iterdir() if p.is_file()}
        manifest = json.loads(files["manifest.json"])
        manifest["id"] = "integration.stop-" + uuid.uuid4().hex[:12]
        manifest["budgets"]["plan_ms"] = 5000
        files["manifest.json"] = json.dumps(manifest)
        files["technique.js"] = "function build(ctx){ while(true){} }"
        ref = self.tool("sketchup_library_save", dict(request_id=str(uuid.uuid4()), technique_id=manifest["id"],
                        base_revision=None, files=files, change_summary="toolbar cancellation test"))["data"]["technique_ref"]
        self.command(grant=0); self.command(grant=1)
        jobs=[]
        for index in (0,1):
            bindings=dict(self.target(index,True),expected_context=[],materials=dict(panel="콘크리트"))
            jobs.append(self.tool("sketchup_library_run",dict(ref, mode="plan",params={},bindings=bindings,request_id=str(uuid.uuid4()))))
        first=jobs[0]["data"]["job_id"]; second=jobs[1]["data"]["job_id"]
        deadline=time.monotonic()+3
        while True:
            state=self.tool("sketchup_get_instance",self.target(0))["state"]
            ids=[j["job_id"] for j in state.get("library_jobs",[])]
            if first in ids:break
            self.assertLess(time.monotonic(),deadline,"Bound work did not reach toolbar")
            time.sleep(.03)
        self.assertNotIn(second,ids)
        self.command(emergency_stop=0)
        canceled=self.library_wait(jobs[0])
        self.assertEqual("canceled",canceled["state"],canceled)
        self.assertEqual("none",canceled["effect"])
        self.assertFalse(canceled["submitted"])
        self.assertEqual("user",self.tool("sketchup_get_instance",self.target(0))["state"]["authority"])
        self.assertEqual("mcp",self.tool("sketchup_get_instance",self.target(1))["state"]["authority"])
        other=self.tool("sketchup_library_job",dict(action="get",job_id=second))["data"]
        self.assertIn(other["state"],("queued","running"),other)
        self.tool("sketchup_library_job",dict(action="cancel",job_id=second))
        self.assertEqual("canceled",self.library_wait(jobs[1])["state"])

    def test_library_plan_apply_permission_replay_and_native_history(self):
        ref = self.library_panel()
        verified = self.library_wait(self.tool("sketchup_library_run", dict(ref, mode="verify",
                        request_id=str(uuid.uuid4()), activate_if_passed=True, expected_active_revision=None)))
        self.assertEqual("succeeded", verified["state"], verified)
        bindings = dict(self.target(0, True), expected_context=[], origin_mm=[3000,0,0], materials=dict(panel="콘크리트"))
        plan = self.library_wait(self.tool("sketchup_library_run", dict(ref, mode="plan", params={}, bindings=bindings,
                                                                      request_id=str(uuid.uuid4()))))["result"]
        args = self.command_args(mode="apply", request_id=str(uuid.uuid4()), plan_id=plan["plan_id"], plan_hash=plan["plan_hash"])
        denied = self.library_wait(self.tool("sketchup_library_run", args))
        self.assertEqual("failed", denied["state"], denied)
        self.assertEqual("none", denied["effect"])
        self.command(grant=0)
        plan = self.library_wait(self.tool("sketchup_library_run", dict(ref, mode="plan", params={}, bindings=bindings,
                                                                      request_id=str(uuid.uuid4()))))["result"]
        args = self.command_args(mode="apply", request_id=str(uuid.uuid4()), plan_id=plan["plan_id"], plan_hash=plan["plan_hash"])
        initial = self.tool("sketchup_library_run", args)
        applied = self.library_wait(initial)
        self.assertEqual("succeeded", applied["state"], applied)
        self.assertEqual("model_applied", applied["effect"])
        self.assertEqual([3000,0,0], applied["result"]["plans"][0]["geometry_bounds"]["min"])
        self.assertEqual([4200,100,900], applied["result"]["plans"][0]["geometry_bounds"]["max"])
        self.assertEqual(initial, self.tool("sketchup_library_run", args))
        conflict = self.tool("sketchup_library_run", dict(args, request_id=str(uuid.uuid4())), error=True)
        self.assertEqual("plan_in_use", conflict["error"]["code"])
        history = self.tool("sketchup_get_command_result", dict(self.target(0, True), command_id=args["command_id"]))
        self.assertEqual(applied["job_id"], history["result"]["library_job_id"])

    def test_library_native_verification_aborts_and_snapshot_staleness(self):
        ref = self.library_panel()
        self.command(grant=0)
        bindings = dict(self.target(0, True), expected_context=[], origin_mm=[5000,0,0], materials=dict(panel="콘크리트"))
        before = self.tool("sketchup_get_model_summary", self.target(0, True))["data"]["top_level_entities"]
        native = self.library_wait(self.tool("sketchup_library_run", dict(ref, mode="verify",
                    request_id=str(uuid.uuid4()), environment="native", bindings=bindings,
                    command_id=self.command_args()["command_id"])))
        self.assertEqual("succeeded", native["state"], native)
        self.assertEqual("none", native["effect"])
        after = self.tool("sketchup_get_model_summary", self.target(0, True))["data"]["top_level_entities"]
        self.assertEqual(before, after)

    def window_fields(self, **changes):
        fields=dict(name='Recipe window',origin_mm=[2000,0,0],width_mm=1200,height_mm=900,depth_mm=100,materials=dict(frame='콘크리트',glass='콘크리트',seal='콘크리트',hardware='콘크리트'))
        fields.update(changes)
        return fields

    def test_window_recipe_is_one_command_with_permission_and_replay(self):
        fields=self.command_args(**self.window_fields())
        self.assertEqual('authority_or_model_mismatch',self.tool('sketchup_create_sliding_window',fields,True)['status'])
        self.command(grant=0)
        fields=self.command_args(**self.window_fields())
        response=self.tool('sketchup_create_sliding_window',fields)
        data=response['result']['data']
        self.assertEqual(1,len(data['created'])); self.assertEqual(3,len(data['sections']))
        self.assertEqual(4,data['planned']['group_count'])
        self.assertEqual([3200,100,900],data['created'][0]['model_bounds']['max'])
        self.assertTrue(data['ui_update']['operation_closed'])
        self.assertTrue(self.tool('sketchup_create_sliding_window',fields)['replayed'])
        summary=self.tool('sketchup_get_model_summary',self.target(0,True))['data']
        self.assertEqual(2,summary['top_level_entities']['total'])

    def test_window_recipe_invalid_native_parameters_do_not_change_model(self):
        self.command(grant=0)
        bad=self.command_args(**self.window_fields(depth_mm=80,glass_thickness_mm=12))
        self.assertEqual('invalid_arguments',self.tool('sketchup_create_sliding_window',bad,True)['status'])
        preview=self.tool('sketchup_create_sliding_window',self.command_args(**self.window_fields(dry_run=True)))['result']['data']
        self.assertTrue(preview['dry_run'])
        self.assertEqual(1,self.tool('sketchup_get_model_summary',self.target(0,True))['data']['top_level_entities']['total'])
        self.assertNotEqual(bad['command_id'],self.tool('sketchup_get_instance',self.target(0))['state']['next_command_id'])

    def test_reads_route_to_exact_model_in_user_mode(self):
        for index in range(2):
            args = self.target(index, True)
            result = self.tool('sketchup_get_model_summary', args)
            self.assertEqual(args['session_id'], result['session_id'])
            self.assertEqual(args['model_id'], result['model_id'])
            self.assertEqual(index, result['data']['instance_index'])
            result = self.tool('sketchup_get_selection_info', dict(args, offset=12, limit=3))
            self.assertEqual(12, result['data']['offset'])
            self.assertEqual('get_selection_info', result['data']['method'])
            self.assertEqual('user', self.tool('sketchup_get_instance', self.target(index))['state']['authority'])
        stale = self.target(0, True)
        self.command(change_model=0)
        for name in ['sketchup_get_model_summary', 'sketchup_get_selection_info']:
            self.assertEqual('model_mismatch', self.tool(name, stale, True)['status'])
        self.assertEqual('pong', self.tool('sketchup_ping', dict(self.target(0), text='한글🙂'))['status'])

    def test_jobs_history_and_adapter_restart_still_work(self):
        args = self.target(0, True)
        self.assertEqual('authority_or_model_mismatch', self.tool('sketchup_start_demo', args, True)['status'])
        self.command(grant=0)
        self.assertEqual('mcp', self.tool('sketchup_get_instance', self.target(0))['state']['authority'])
        job = self.tool('sketchup_start_demo', args)['job_id']
        self.command(clock=10)
        self.assertEqual(50, self.tool('sketchup_get_job', dict(self.target(0), job_id=job))['job']['progress'])
        self.tool('sketchup_cancel_job', dict(self.target(0), job_id=job))
        self.assertEqual('canceled', self.tool('sketchup_get_job', dict(self.target(0), job_id=job))['job']['status'])
        fresh = self.tool('sketchup_start_demo', args)['job_id']
        self.assertEqual('not_running', self.tool('sketchup_cancel_job', dict(self.target(0), job_id=job))['status'])
        self.assertEqual('running', self.tool('sketchup_get_job', dict(self.target(0), job_id=fresh))['job']['status'])
        self.stop_adapter()
        self.start_adapter()
        self.assertEqual(2, len(self.tool('sketchup_list_instances')['instances']))
        self.assertEqual('user', self.tool('sketchup_get_instance', self.target(0))['state']['authority'])
        self.assertEqual('authority_or_model_mismatch', self.tool('sketchup_start_demo', args, True)['status'])

    def test_discovery_routes_nested_occurrences_and_connects_to_selection(self):
        for index in range(2):
            target = self.target(index, True)
            before = self.tool('sketchup_get_instance', self.target(index))['state']
            first = self.tool('sketchup_find_entities', dict(target, scope='model', limit=1))['data']
            self.assertEqual([str(1000+index)], first['items'][0]['instance_path'])
            self.assertTrue(first['items'][0]['in_current_context'])
            second = self.tool('sketchup_find_entities', dict(target, scope='model', limit=1, cursor=first['next_cursor']))['data']
            self.assertEqual([str(1000+index),str(2000+index)], second['items'][0]['instance_path'])
            self.assertTrue(second['complete'])
            self.assertFalse(second['items'][0]['in_current_context'])
            children = self.tool('sketchup_get_children', dict(target, parent_path=first['items'][0]['instance_path']))['data']
            self.assertEqual(second['items'], children['items'])
            found = self.tool('sketchup_find_entities', dict(target, name='기둥', tag='구조', entity_type='ComponentInstance'))['data']
            self.assertEqual(children['items'], found['items'])
            after = self.tool('sketchup_get_instance', self.target(index))['state']
            self.assertEqual('user', after['authority'])
            self.assertEqual(before['next_command_id'], after['next_command_id'])
            bad = self.tool('sketchup_find_entities', dict(target, cursor='not-a-cursor'), True)
            self.assertEqual('query_failed', bad['status'])
            self.assertEqual('pong', self.tool('sketchup_ping', self.target(index))['status'])
        self.command(grant=0)
        root = self.tool('sketchup_find_entities', self.target(0, True))['data']['items'][0]
        self.tool('sketchup_set_selection', self.command_args(entity_ids=[root['persistent_id']], expected_context=root['parent_path'], mode='replace'))
        selection = self.tool('sketchup_get_selection_info', self.target(0, True))['data']
        self.assertEqual(root['persistent_id'], selection['items'][0]['persistent_id'])
        stale = self.target(0, True)
        self.command(change_model=0)
        for name, fields in [('sketchup_find_entities', {}), ('sketchup_get_children', {'parent_path':[]})]:
            self.assertEqual('model_mismatch', self.tool(name, dict(stale, **fields), True)['status'])

    def test_create_duplicate_and_replay_flow_returns_discoverable_ids(self):
        fields = dict(name='새 박스🙂',origin_mm=[100,200,300],size_mm=[1000,2000,3000])
        args = self.command_args(**fields)
        self.assertEqual('authority_or_model_mismatch',self.tool('sketchup_create_box',args,True)['status'])
        self.command(grant=0)
        preview = self.tool('sketchup_create_box',self.command_args(dry_run=True,**fields))
        self.assertEqual('preview',preview['result']['state'])
        self.assertEqual([],self.tool('sketchup_find_entities',dict(self.target(0,True),name=fields['name']))['data']['items'])
        args = self.command_args(**fields)
        result = self.tool('sketchup_create_box',args)
        box = result['result']['data']['created'][0]
        self.assertEqual([100,200,300],box['model_bounds']['min'])
        self.assertEqual([1100,2200,3300],box['model_bounds']['max'])
        self.assertTrue(self.tool('sketchup_create_box',args)['replayed'])
        self.assertEqual(1,len(self.tool('sketchup_find_entities',dict(self.target(0,True),name=fields['name']))['data']['items']))
        duplicate = self.command_args(entity_ids=[box['persistent_id']],delta_mm=[2000,0,0])
        copied = self.tool('sketchup_duplicate_entities',duplicate)['result']['data']['created'][0]
        self.assertNotEqual(box['persistent_id'],copied['persistent_id'])
        self.assertEqual([2100,200,300],copied['model_bounds']['min'])
        self.assertTrue(self.tool('sketchup_duplicate_entities',duplicate)['replayed'])
        found = self.tool('sketchup_find_entities',dict(self.target(0,True),name=fields['name']))['data']['items']
        self.assertEqual({box['persistent_id'],copied['persistent_id']},{i['persistent_id'] for i in found})
        self.assertEqual([],self.tool('sketchup_find_entities',dict(self.target(1,True),name=fields['name']))['data']['items'])
        self.tool('sketchup_set_selection',self.command_args(entity_ids=[box['persistent_id'],copied['persistent_id']],mode='replace'))
        items = self.tool('sketchup_get_selection_info',self.target(0,True))['data']['items']
        self.assertEqual([[100,200,300],[2100,200,300]],[i['model_bounds']['min'] for i in items])
        cached = self.tool('sketchup_get_command_result',dict(self.target(0,True),command_id=duplicate['command_id']))
        self.assertEqual(copied,cached['result']['data']['created'][0])

    def test_same_wrapper_new_and_open_reject_stale_commands_and_revoke_permission(self):
        for event in ['new', 'open']:
            self.command(grant=0)
            old_target = self.target(0, True)
            wrapper_id = self.instances[0]['test_model_wrapper_id']
            other_target = self.target(1, True)
            stale = self.command_args(entity_ids=['1000'], delta_mm=[1000, 0, 0])
            before = self.tool('sketchup_get_selection_info', old_target)['data']['items'][0]['model_bounds']
            self.command(change_model=0, change_model_event=event)
            self.assertEqual(wrapper_id, self.instances[0]['test_model_wrapper_id'])
            self.assertEqual(old_target['session_id'], self.target(0)['session_id'])
            self.assertNotEqual(old_target['model_id'], self.target(0, True)['model_id'])
            self.assertEqual(other_target, self.target(1, True))
            state = self.tool('sketchup_get_instance', self.target(0))['state']
            self.assertEqual('user', state['authority'])
            self.assertEqual(stale['command_id'], state['next_command_id'])
            self.assertEqual('model_mismatch', self.tool('sketchup_move_entities', stale, True)['status'])
            self.assertEqual('model_mismatch', self.tool('sketchup_get_selection_info', old_target, True)['status'])
            fresh = self.command_args(entity_ids=['1000'], delta_mm=[1000, 0, 0])
            self.assertEqual('authority_or_model_mismatch', self.tool('sketchup_move_entities', fresh, True)['status'])
            after = self.tool('sketchup_get_selection_info', self.target(0, True))['data']['items'][0]['model_bounds']
            self.assertEqual(before, after)
            self.command(grant=0)
            moved = self.tool('sketchup_move_entities', self.command_args(entity_ids=['1000'], delta_mm=[1000, 0, 0]))
            self.assertEqual('completed', moved['result']['state'])
            self.assertEqual([before['min'][0] + 1000, before['min'][1], before['min'][2]],
                             self.tool('sketchup_get_selection_info', self.target(0, True))['data']['items'][0]['model_bounds']['min'])

    def test_basic_geometry_and_native_suite_use_real_pipe_with_one_request(self):
        self.command(grant=0)
        rect=self.tool('sketchup_create_rectangle',self.command_args(name='r',origin_mm=[0,0,0],size_mm=[1000,2000],plane='XY'))['result']['data']['created'][0]
        query=dict(self.target(0,True),instance_path=rect['instance_path'])
        item=self.tool('sketchup_get_entity_info',query)['data']['item']
        self.assertAlmostEqual(2000000,item['direct_geometry']['face_area_mm2'])
        self.tool('sketchup_push_pull',self.command_args(entity_ids=[rect['persistent_id']],distance_mm=3000))
        self.assertTrue(self.tool('sketchup_get_entity_info',query)['data']['item']['manifold'])
        self.tool('sketchup_rotate_entities',self.command_args(entity_ids=[rect['persistent_id']],pivot_mm=[0,0,0],axis=[0,0,1],angle_degrees=90))
        self.tool('sketchup_scale_entities',self.command_args(entity_ids=[rect['persistent_id']],pivot_mm=[0,0,0],factors=[2,1,1]))
        before=self.tool('sketchup_get_model_summary',self.target(0,True))['data']['top_level_entities']['total']
        args=self.command_args(confirm_test_model=True)
        report=self.tool('sketchup_run_self_test',args)['result']['data']
        self.assertTrue(report['passed'],report)
        self.assertTrue(report['cleanup_verified'])
        self.assertEqual(25,report['passed_count'])
        self.assertEqual(before,self.tool('sketchup_get_model_summary',self.target(0,True))['data']['top_level_entities']['total'])
        replay=self.tool('sketchup_run_self_test',args)
        self.assertTrue(replay['replayed'])
        self.assertEqual(report,replay['result']['data'])
        self.tool('sketchup_erase_entities',self.command_args(entity_ids=[rect['persistent_id']]))
        self.assertEqual('query_failed',self.tool('sketchup_get_entity_info',query,True)['status'])

    def test_extended_suite_and_resource_query_cross_real_pipe(self):
        target=self.target(0,True)
        resources=self.tool('sketchup_get_resources',dict(target,kind='definitions',limit=25))['data']
        self.assertTrue(resources['items'])
        self.assertTrue(resources['items'][0]['definition_id'].startswith('definition:'))
        self.assertEqual('user',self.tool('sketchup_get_instance',self.target(0))['state']['authority'])
        self.command(grant=0)
        before=self.tool('sketchup_get_model_summary',target)['data']['top_level_entities']['total']
        fields=self.command_args(confirm_test_model=True,suite='all')
        report=self.tool('sketchup_run_self_test',fields)['result']['data']
        self.assertTrue(report['passed'],report)
        self.assertEqual(56,report['passed_count'])
        self.assertTrue(report['cleanup_verified'])
        self.assertEqual(before,self.tool('sketchup_get_model_summary',target)['data']['top_level_entities']['total'])
        replay=self.tool('sketchup_run_self_test',fields)
        self.assertTrue(replay['replayed']); self.assertEqual(report,replay['result']['data'])

    def test_atomic_batch_permission_replay_failure_and_ui_restoration(self):
        step=lambda method,**args: dict(method=method,arguments=args)
        steps=[step('create_box',name='A',origin_mm=[0,0,0],size_mm=[100,200,300]),step('create_box',name='B',origin_mm=[1000,0,0],size_mm=[100,200,300])]
        fields=self.command_args(steps=steps)
        self.assertEqual('authority_or_model_mismatch',self.tool('sketchup_run_batch',fields,True)['status'])
        self.command(grant=0)
        fields=self.command_args(steps=steps)
        result=self.tool('sketchup_run_batch',fields)['result']['data']
        self.assertEqual(2,result['step_count']); self.assertTrue(result['ui_update']['operation_closed'])
        self.assertTrue(result['ui_update']['inspectors_refresh_requested'])
        self.assertTrue(self.tool('sketchup_run_batch',fields)['replayed'])
        before=self.tool('sketchup_get_model_summary',self.target(0,True))['data']['top_level_entities']['total']
        self.assertEqual(3,before)
        bad=[step('update_entity_properties',entity_ids=['1000'],properties=dict(name='rolled back')),step('move_entities',entity_ids=['999'],delta_mm=[1,0,0])]
        self.assertEqual('batch_step_failed',self.tool('sketchup_run_batch',self.command_args(steps=bad),True)['status'])
        items=self.tool('sketchup_get_selection_info',self.target(0,True))['data']['items']
        self.assertEqual('block',items[0]['name'])
        next_result=self.tool('sketchup_run_batch',self.command_args(steps=steps))['result']['data']
        self.assertTrue(next_result['ui_update']['operation_closed'])

    def command_args(self, **fields):
        state = self.tool('sketchup_get_instance', self.target(0))['state']
        args = dict(self.target(0, True), command_id=state['next_command_id'], expected_context=[])
        args.update(fields)
        return args

    def test_commands_round_trip_through_real_executor_without_duplicates(self):
        args = self.command_args(entity_ids=['1000'], delta_mm=[1000,500,0])
        self.assertEqual('authority_or_model_mismatch', self.tool('sketchup_move_entities', args, True)['status'])
        self.command(grant=0)
        preview = self.command_args(entity_ids=['1000'], properties={'name':'A동'}, dry_run=True)
        result = self.tool('sketchup_update_entity_properties', preview)
        self.assertEqual('preview', result['result']['state'])
        self.assertEqual('block', self.tool('sketchup_get_selection_info', self.target(0, True))['data']['items'][0]['name'])
        properties = self.command_args(entity_ids=['1000'], properties={'name':'A동','tag':'구조','material':'콘크리트'})
        self.assertEqual('completed', self.tool('sketchup_update_entity_properties', properties)['result']['state'])
        item = self.tool('sketchup_get_selection_info', self.target(0, True))['data']['items'][0]
        self.assertEqual('A동', item['name'])
        self.assertEqual('구조', item['tag']['name'])
        self.tool('sketchup_set_selection', self.command_args(entity_ids=[], mode='clear'))
        self.assertEqual(0, self.tool('sketchup_get_selection_info', self.target(0, True))['data']['total'])
        self.tool('sketchup_set_selection', self.command_args(entity_ids=['1000'], mode='replace'))
        self.tool('sketchup_set_view', self.command_args(preset='top'))
        self.tool('sketchup_zoom', self.command_args(entity_ids=['1000'], scope='entities'))
        move = self.command_args(entity_ids=['1000'], delta_mm=[1000,500,0])
        moved = self.tool('sketchup_move_entities', move)
        self.assertEqual([1000,500,0], moved['result']['data']['after'][0]['model_origin_mm'])
        replay = self.tool('sketchup_move_entities', move)
        self.assertTrue(replay['replayed'])
        self.assertEqual(moved['result'], replay['result'])
        item = self.tool('sketchup_get_selection_info', self.target(0, True))['data']['items'][0]
        self.assertEqual([1000,500,0], item['model_bounds']['min'])
        query = dict(self.target(0, True), command_id=move['command_id'])
        self.assertEqual('completed', self.tool('sketchup_get_command_result', query)['result']['state'])
        conflict = dict(move, delta_mm=[2,0,0])
        self.assertEqual('command_id_conflict', self.tool('sketchup_move_entities', conflict, True)['status'])
        wrong = self.command_args(entity_ids=['1000'], delta_mm=[1,0,0])
        wrong['expected_context'] = ['999']
        self.assertEqual('context_mismatch', self.tool('sketchup_move_entities', wrong, True)['status'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
