"""Exercise the production MCP server over real subprocess stdin/stdout.
Usage: python tests/mcp_stdio_test.py dist/McpHarness.exe
Linux: python tests/mcp_stdio_test.py /path/to/mono dist/McpHarness.exe
"""
import json
import queue
import subprocess
import sys
import threading
import time
import unittest

COMMAND = sys.argv[1:]
sys.argv = sys.argv[:1]
SESSION = "b5edb816-649f-4f19-ae89-d17c8b72f057"


class StdioTests(unittest.TestCase):
    def setUp(self):
        self.process = subprocess.Popen(COMMAND, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE)
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=self.read_stdout, daemon=True)
        self.reader.start()

    def read_stdout(self):
        for line in self.process.stdout:
            self.lines.put(line)

    def tearDown(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
                self.fail("MCP server did not terminate on stdin EOF")
        self.reader.join(timeout=1)
        for stream in [self.process.stdin, self.process.stdout, self.process.stderr]:
            if not stream.closed:
                stream.close()

    def send(self, method, params=None, request_id=None):
        message = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        if request_id is not None:
            message["id"] = request_id
        self.raw(json.dumps(message, ensure_ascii=False).encode("utf-8") + b"\n")

    def raw(self, data):
        self.process.stdin.write(data)
        self.process.stdin.flush()

    def response(self, timeout=3):
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            detail = self.process.stderr.read().decode('utf-8', errors='replace') if self.process.poll() is not None else ''
            self.fail("No JSON-RPC response within deadline. " + detail)
        value = json.loads(line.decode("utf-8"))
        self.assertEqual("2.0", value["jsonrpc"])
        return value

    def initialize(self, version="2025-11-25"):
        self.send("initialize", {"protocolVersion": version, "capabilities": {},
                                "clientInfo": {"name": "stdio-test", "version": "1"}}, 1)
        result = self.response()["result"]
        self.send("notifications/initialized")
        return result

    def call(self, text, request_id=2):
        self.send("tools/call", {"name": "sketchup_ping",
                                "arguments": {"session_id": SESSION, "text": text}}, request_id)

    def test_initialization_and_tool_contract(self):
        result = self.initialize()
        self.assertEqual("2025-11-25", result["protocolVersion"])
        self.assertEqual({"tools"}, set(result["capabilities"]))
        self.send("tools/list", {}, 2)
        tools = self.response()["result"]["tools"]
        self.assertEqual(47, len(tools))
        self.assertEqual(47, len({tool["name"] for tool in tools}))
        for tool in tools:
            self.assertFalse(tool["inputSchema"]["additionalProperties"])
            self.assertEqual("object",tool["inputSchema"]["type"])
        self.assertTrue(next(t for t in tools if t["name"] == "sketchup_ping")["annotations"]["readOnlyHint"])
        for name in ["sketchup_get_model_summary", "sketchup_get_selection_info"]:
            tool = next(t for t in tools if t["name"] == name)
            self.assertEqual(["session_id", "model_id"], tool["inputSchema"]["required"])
            self.assertTrue(tool["annotations"]["readOnlyHint"])

    def test_library_tools_accept_model_free_lifecycle_and_reject_mode_mixing(self):
        self.initialize()
        request = dict(request_id="11111111-1111-4111-8111-111111111111", action="create_library",
                       title="기법 모음", scope="user")
        self.send("tools/call", dict(name="sketchup_library_manage", arguments=request), 2)
        result = self.response()["result"]
        self.assertFalse(result["isError"])
        self.assertEqual(request, json.loads(result["content"][0]["text"])["arguments"])
        for name, args in [
            ("sketchup_library_manage", dict(request, arbitrary=True)),
            ("sketchup_library_run", dict(mode="apply", request_id=request["request_id"], params={})),
            ("sketchup_library_transfer", dict(action="export", selections=[], package_info=dict(title="Empty"))),
            ("sketchup_library_list", dict(limit=True)),
        ]:
            self.send("tools/call", dict(name=name, arguments=args), 3)
            self.assertEqual(-32602, self.response()["error"]["code"])

    def test_read_query_validation_and_paging(self):
        self.initialize()
        for args in [{"session_id": SESSION}, {"session_id": SESSION, "model_id": "invalid"},
                     {"session_id": SESSION, "model_id": SESSION, "limit": 0},
                     {"session_id": SESSION, "model_id": SESSION, "limit": 26},
                     {"session_id": SESSION, "model_id": SESSION, "limit": True},
                     {"session_id": SESSION, "model_id": SESSION, "limit": 1.5},
                     {"session_id": SESSION, "model_id": SESSION, "offset": -1},
                     {"session_id": SESSION, "model_id": SESSION, "offset": 1000001}]:
            self.send("tools/call", {"name": "sketchup_get_selection_info", "arguments": args}, 2)
            self.assertEqual(-32602, self.response()["error"]["code"])
        args = {"session_id": SESSION, "model_id": SESSION, "offset": 20, "limit": 25}
        self.send("tools/call", {"name": "sketchup_get_selection_info", "arguments": args}, 3)
        payload = json.loads(self.response()["result"]["content"][0]["text"])
        self.assertEqual(args, payload["arguments"])

    def test_discovery_contract_and_nested_arguments(self):
        self.initialize()
        self.send('tools/list', {}, 2)
        tools = {t['name']: t for t in self.response()['result']['tools']}
        common = dict(session_id=SESSION, model_id=SESSION)
        cases = [
            ('sketchup_find_entities', dict(scope='model', name='기둥🙂', tag='구조', entity_type='Group', max_depth=32, limit=25)),
            ('sketchup_find_entities', dict(name='🙂'*256)),
            ('sketchup_get_children', dict(parent_path=[], limit=1)),
            ('sketchup_get_children', dict(parent_path=['100','101'], cursor='opaque-cursor')),
        ]
        for number, (name, fields) in enumerate(cases, 10):
            tool = tools[name]
            self.assertTrue(tool['annotations']['readOnlyHint'])
            self.assertTrue(tool['annotations']['idempotentHint'])
            self.send('tools/call', {'name':name, 'arguments':dict(common, **fields)}, number)
            result = self.response()['result']
            self.assertFalse(result['isError'])
            self.assertEqual(dict(common, **fields), json.loads(result['content'][0]['text'])['arguments'])
        self.assertEqual(['session_id','model_id','parent_path'], tools['sketchup_get_children']['inputSchema']['required'])

    def test_discovery_rejects_invalid_filters_paths_and_limits(self):
        self.initialize()
        common = dict(session_id=SESSION, model_id=SESSION)
        invalid = [
            ('sketchup_find_entities', dict(limit=True)),
            ('sketchup_find_entities', dict(limit=1.5)),
            ('sketchup_find_entities', dict(limit=26)),
            ('sketchup_find_entities', dict(max_depth=0)),
            ('sketchup_find_entities', dict(max_depth=33)),
            ('sketchup_find_entities', dict(scope='selection')),
            ('sketchup_find_entities', dict(entity_type='Edge')),
            ('sketchup_find_entities', dict(name='')),
            ('sketchup_find_entities', dict(name='🙂'*257)),
            ('sketchup_find_entities', dict(tag=None)),
            ('sketchup_find_entities', dict(name='bad\x00name')),
            ('sketchup_find_entities', dict(cursor='x'*8193)),
            ('sketchup_find_entities', dict(cursor='')),
            ('sketchup_find_entities', dict(parent_path=[])),
            ('sketchup_get_children', {}),
            ('sketchup_get_children', dict(parent_path='100')),
            ('sketchup_get_children', dict(parent_path=[100])),
            ('sketchup_get_children', dict(parent_path=['0'])),
            ('sketchup_get_children', dict(parent_path=['1']*32)),
            ('sketchup_get_children', dict(parent_path=[], name='x')),
        ]
        for number, (name, fields) in enumerate(invalid, 10):
            self.send('tools/call', {'name':name, 'arguments':dict(common, **fields)}, number)
            self.assertEqual(-32602, self.response()['error']['code'], (name, fields))

    def test_basic_drawing_edit_query_and_batch_contract(self):
        self.initialize()
        self.send('tools/list',{},2)
        tools={t['name']:t for t in self.response()['result']['tools']}
        common=dict(session_id=SESSION,model_id=SESSION,command_id=SESSION+':1',expected_context=[])
        cases=[
            ('sketchup_create_rectangle',dict(name='r',origin_mm=[0,0,0],size_mm=[1,2],plane='XY')),
            ('sketchup_create_circle',dict(name='c',origin_mm=[0,0,0],radius_mm=10,plane='XZ')),
            ('sketchup_create_polyline',dict(name='p',points_mm=[[0,0,0],[1,0,0]])),
            ('sketchup_rotate_entities',dict(entity_ids=['101'],pivot_mm=[0,0,0],axis=[0,0,1],angle_degrees=30)),
            ('sketchup_scale_entities',dict(entity_ids=['101'],pivot_mm=[0,0,0],factors=[2,1,1])),
            ('sketchup_erase_entities',dict(entity_ids=['101'])),
            ('sketchup_group_entities',dict(entity_ids=['101','102'])),
            ('sketchup_make_unique',dict(entity_ids=['101'])),
            ('sketchup_push_pull',dict(entity_ids=['101'],distance_mm=-1000)),
            ('sketchup_run_self_test',dict(confirm_test_model=True)),
        ]
        for number,(name,fields) in enumerate(cases,30):
            self.assertFalse(tools[name]['annotations']['readOnlyHint'])
            self.send('tools/call',{'name':name,'arguments':dict(common,**fields)},number)
            self.assertFalse(self.response()['result']['isError'])
        self.assertTrue(tools['sketchup_erase_entities']['annotations']['destructiveHint'])
        self.assertTrue(tools['sketchup_get_entity_info']['annotations']['readOnlyHint'])
        self.assertNotIn('segments',tools['sketchup_create_circle']['inputSchema']['required'])
        self.send('tools/call',{'name':'sketchup_get_entity_info','arguments':dict(session_id=SESSION,model_id=SESSION,instance_path=['101','102'],child_offset=25,child_limit=10)},70)
        self.assertFalse(self.response()['result']['isError'])

    def test_basic_commands_reject_bad_vectors_ranges_and_unconfirmed_batch(self):
        self.initialize()
        common=dict(session_id=SESSION,model_id=SESSION,command_id=SESSION+':1',expected_context=[])
        cases=[
            ('sketchup_create_rectangle',dict(name='r',origin_mm=[0,0,0],size_mm=[1,2,3],plane='XY')),
            ('sketchup_create_circle',dict(name='c',origin_mm=[0,0,0],radius_mm=0,plane='XY')),
            ('sketchup_create_circle',dict(name='c',origin_mm=[0,0,0],radius_mm=1,plane='XY',segments=True)),
            ('sketchup_create_polyline',dict(name='p',points_mm=[[0,0,0],[True,0,0]])),
            ('sketchup_rotate_entities',dict(entity_ids=['101'],pivot_mm=[0,0,0],axis=[0,0,0],angle_degrees=30)),
            ('sketchup_scale_entities',dict(entity_ids=['101'],pivot_mm=[0,0,0],factors=[-1,1,1])),
            ('sketchup_push_pull',dict(entity_ids=['101','102'],distance_mm=1000)),
            ('sketchup_push_pull',dict(entity_ids=['101'],distance_mm=0)),
            ('sketchup_run_self_test',dict(confirm_test_model=False)),
            ('sketchup_run_self_test',dict(confirm_test_model=True,expected_context=['101'])),
            ('sketchup_run_self_test',dict(confirm_test_model=True,ruby='anything')),
        ]
        for number,(name,fields) in enumerate(cases,30):
            args=dict(common); args.update(fields)
            self.send('tools/call',{'name':name,'arguments':args},number)
            self.assertEqual(-32602,self.response()['error']['code'],(name,fields))
        for number,path in enumerate([[],['0'],[1],['1']*33],80):
            self.send('tools/call',{'name':'sketchup_get_entity_info','arguments':dict(session_id=SESSION,model_id=SESSION,instance_path=path)},number)
            self.assertEqual(-32602,self.response()['error']['code'])

    def test_extended_tools_accept_typed_contracts(self):
        self.initialize()
        common=dict(session_id=SESSION,model_id=SESSION,command_id=SESSION+':1',expected_context=[])
        cases=[
            ('manage_resource',dict(kind='materials',action='create',options=dict(name='paint',color_rgb=[1,2,3],alpha=0.5))),
            ('component',dict(action='instantiate',options=dict(definition_id='definition:123',origin_mm=[0,0,0]))),
            ('create_geometry',dict(kind='arc_three_point',name='arc',options=dict(points_mm=[[1,0,0],[0,1,0],[-1,0,0]],segments=12))),
            ('edit_geometry',dict(container_id='101',affect_all_instances=True,action='move_vertices',options=dict(vertex_moves=[dict(edge_id='102',endpoint='end',position_mm=[1,2,3])]))),
            ('mirror_entities',dict(entity_ids=['101'],axis='X',pivot_mm=[0,0,0])),
            ('configure_camera',dict(eye_mm=[1,2,3],target_mm=[0,0,0],up=[0,0,1],perspective=True,fov_degrees=45)),
            ('scene',dict(action='create',name='view',options={})),
            ('run_self_test',dict(confirm_test_model=True,suite='all')),
        ]
        for index,(name,fields) in enumerate(cases,50):
            self.send('tools/call',dict(name='sketchup_'+name,arguments=dict(common,**fields)),index)
            self.assertFalse(self.response()['result']['isError'],name)
        self.send('tools/call',dict(name='sketchup_get_resources',arguments=dict(session_id=SESSION,model_id=SESSION,kind='definitions',limit=25)),80)
        self.assertFalse(self.response()['result']['isError'])

    def test_extended_tools_reject_untyped_nested_options_and_unknown_keys(self):
        self.initialize()
        common=dict(session_id=SESSION,model_id=SESSION,command_id=SESSION+':1',expected_context=[])
        cases=[
            ('manage_resource',dict(kind='tags',action='create',options=dict(name='tag',visible=1))),
            ('manage_resource',dict(kind='materials',action='create',options=dict(name='paint',color_rgb=[256,0,0]))),
            ('manage_resource',dict(kind='materials',action='purge_unused',options=dict(confirm_model_wide='yes'))),
            ('component',dict(action='instantiate',options=dict(definition_id='123',origin_mm=[0,0,0]))),
            ('create_geometry',dict(kind='face',name='f',options=dict(points_mm=[[0,0,True]]))),
            ('create_geometry',dict(kind='freehand',name='f',options=dict(points_mm=[[0,0,0]]*257))),
            ('edit_geometry',dict(container_id='1',action='erase',options=dict(entity_ids=['0']))),
            ('edit_geometry',dict(container_id='1',action='move_vertices',options=dict(vertex_moves=[dict(edge_id='1',endpoint='start',position_mm=[0,0,0],ruby='bad')]))),
            ('configure_camera',dict(eye_mm=[1,2,3],target_mm=[0,0,0],up=[0,0,1],perspective=True,fov_degrees=121)),
            ('scene',dict(action='eval',name='s',options={})),
            ('run_self_test',dict(confirm_test_model=True,suite='unknown')),
        ]
        for index,(name,fields) in enumerate(cases,50):
            self.send('tools/call',dict(name='sketchup_'+name,arguments=dict(common,**fields)),index)
            self.assertEqual(-32602,self.response()['error']['code'],name)

    def test_window_recipe_schema_and_typed_parameters(self):
        self.initialize()
        self.send('tools/list',{},2)
        tools={t['name']:t for t in self.response()['result']['tools']}
        schema=tools['sketchup_create_sliding_window']['inputSchema']
        self.assertFalse(tools['sketchup_create_sliding_window']['annotations']['readOnlyHint'])
        self.assertNotIn('ruby',schema['properties'])
        args=dict(session_id=SESSION,model_id=SESSION,command_id=SESSION+':1',expected_context=[],name='window',origin_mm=[0,0,0],width_mm=1200,height_mm=900,depth_mm=100,materials=dict(frame='white',glass='glass',seal='seal',hardware='dark'))
        self.send('tools/call',dict(name='sketchup_create_sliding_window',arguments=args),3)
        self.assertFalse(self.response()['result']['isError'])
        changes=[dict(width_mm=True),dict(height_mm=399),dict(depth_mm=301),dict(open_fraction=1.1),dict(open_sash='both'),dict(materials=dict(frame='white',glass='glass')),dict(replace_entity_id='0'),dict(ruby='anything')]
        for i,change in enumerate(changes,10):
            self.send('tools/call',dict(name='sketchup_create_sliding_window',arguments=dict(args,**change)),i)
            self.assertEqual(-32602,self.response()['error']['code'],change)

    def test_batch_schema_and_nested_validation(self):
        self.initialize()
        self.send('tools/list',{},2)
        tools={t['name']:t for t in self.response()['result']['tools']}
        schema=tools['sketchup_run_batch']['inputSchema']
        self.assertEqual(18,len(schema['properties']['steps']['items']['oneOf']))
        self.assertNotIn('ui_updates',schema['required'])
        common=dict(session_id=SESSION,model_id=SESSION,command_id=SESSION+':1',expected_context=[],ui_updates='defer')
        step=dict(method='create_geometry',arguments=dict(kind='polygon',name='polygon',options=dict(origin_mm=[0,0,0],plane='XY',radius_mm=100,sides=6)))
        self.send('tools/call',dict(name='sketchup_run_batch',arguments=dict(common,steps=[step])),3)
        self.assertFalse(self.response()['result']['isError'])
        self.send('tools/call',dict(name='sketchup_create_box',arguments=dict(common,name='box',origin_mm=[0,0,0],size_mm=[1,2,3],ui_updates='normal')),4)
        self.assertFalse(self.response()['result']['isError'])

    def test_batch_rejects_forbidden_actions_overrides_and_bad_inner_types(self):
        self.initialize()
        common=dict(session_id=SESSION,model_id=SESSION,command_id=SESSION+':1',expected_context=[])
        invalid=[[],[dict(method='scene',arguments={})],[dict(method='run_batch',arguments={})],
            [dict(method='set_selection',arguments={})],
            [dict(method='move_entities',arguments=dict(entity_ids=['1'],delta_mm=[True,0,0]))],
            [dict(method='create_box',arguments=dict(name='b',origin_mm=[0,0,0],size_mm=[1,2,3],command_id=SESSION+':2'))],
            [dict(method='create_box',arguments=dict(name='b',origin_mm=[0,0,0],size_mm=[1,2,3],ui_updates='normal'))],
            [dict(method='component',arguments=dict(action='instantiate',options=dict(definition_id='123',origin_mm=[0,0,0])))],
            [dict(method='create_box',arguments={},ruby='bad')],
            [dict(method='make_unique',arguments=dict(entity_ids=['1']))]*65]
        for index,steps in enumerate(invalid,10):
            self.send('tools/call',dict(name='sketchup_run_batch',arguments=dict(common,steps=steps)),index)
            self.assertEqual(-32602,self.response()['error']['code'])
        for index,mode in enumerate(['off',False,None],50):
            self.send('tools/call',dict(name='sketchup_create_box',arguments=dict(common,name='b',origin_mm=[0,0,0],size_mm=[1,2,3],ui_updates=mode)),index)
            self.assertEqual(-32602,self.response()['error']['code'])

    def test_protocol_negotiation(self):
        self.assertEqual("2025-11-25", self.initialize("unsupported-future-version")["protocolVersion"])

    def test_command_validation_and_nested_input(self):
        self.initialize()
        common = dict(session_id=SESSION, model_id=SESSION, command_id=SESSION + ':1', expected_context=[])
        valid = {
            'sketchup_set_selection': dict(entity_ids=['101'], mode='replace'),
            'sketchup_set_view': dict(preset='isometric'),
            'sketchup_zoom': dict(scope='model', entity_ids=[]),
            'sketchup_update_entity_properties': dict(entity_ids=['101'], properties={'name': '🙂' * 256, 'material': None, 'hidden': False}),
            'sketchup_move_entities': dict(entity_ids=['101'], delta_mm=[1.25, -2, 0]),
        }
        for number, (name, fields) in enumerate(valid.items(), 20):
            args = dict(common, **fields)
            self.send('tools/call', {'name': name, 'arguments': args}, number)
            payload = self.response()['result']
            self.assertFalse(payload['isError'])
            self.assertEqual(args, json.loads(payload['content'][0]['text'])['arguments'])
        invalid = [
            ('sketchup_set_selection', dict(entity_ids=['101'], mode='clear')),
            ('sketchup_set_selection', dict(entity_ids=[], mode='replace')),
            ('sketchup_set_view', dict(preset='eval_ruby')),
            ('sketchup_zoom', dict(scope='model', entity_ids=['101'])),
            ('sketchup_move_entities', dict(entity_ids=['101','101'], delta_mm=[1,0,0])),
            ('sketchup_move_entities', dict(entity_ids=['0'], delta_mm=[1,0,0])),
            ('sketchup_move_entities', dict(entity_ids=['101'], delta_mm=[True,0,0])),
            ('sketchup_move_entities', dict(entity_ids=['101'], delta_mm=[1e10,0,0])),
            ('sketchup_move_entities', dict(entity_ids=['101'], delta_mm=[1,0])),
            ('sketchup_move_entities', dict(entity_ids=['101'], delta_mm=[1,0,0], dry_run='true')),
            ('sketchup_update_entity_properties', dict(entity_ids=['101'], properties={})),
            ('sketchup_update_entity_properties', dict(entity_ids=['101'], properties={'hidden':'yes'})),
            ('sketchup_update_entity_properties', dict(entity_ids=['101'], properties={'ruby':'anything'})),
            ('sketchup_update_entity_properties', dict(entity_ids=['101'], properties={'name':'🙂'*257})),
            ('sketchup_update_entity_properties', dict(entity_ids=['101'], properties={'name':'invalid\x00name'})),
        ]
        for number, (name, fields) in enumerate(invalid, 50):
            self.raw(json.dumps({'jsonrpc':'2.0','id':number,'method':'tools/call',
                'params':{'name':name,'arguments':dict(common, **fields)}}, ensure_ascii=True).encode('utf-8') + b'\n')
            response = self.response()
            self.assertIn('error', response, (name, fields))
            self.assertEqual(-32602, response['error']['code'], (name, fields))

    def test_command_tool_annotations_and_result_schema(self):
        self.initialize()
        self.send('tools/list', {}, 2)
        tools = {t['name']: t for t in self.response()['result']['tools']}
        for name in ['sketchup_set_selection','sketchup_set_view','sketchup_zoom','sketchup_update_entity_properties','sketchup_move_entities']:
            self.assertFalse(tools[name]['annotations']['readOnlyHint'])
            self.assertTrue(tools[name]['annotations']['idempotentHint'])
            self.assertIn('command_id', tools[name]['inputSchema']['required'])
            self.assertIn('expected_context', tools[name]['inputSchema']['required'])
        self.assertTrue(tools['sketchup_get_command_result']['annotations']['readOnlyHint'])

    def test_creation_and_duplication_contract_and_arguments(self):
        self.initialize()
        self.send('tools/list', {}, 2)
        tools = {t['name']:t for t in self.response()['result']['tools']}
        common = dict(session_id=SESSION, model_id=SESSION, command_id=SESSION+':1', expected_context=[])
        cases = [
            ('sketchup_create_box', dict(name='A동🙂', origin_mm=[0,-200,300], size_mm=[1,2000,1000000], dry_run=True)),
            ('sketchup_create_box', dict(name='🙂'*256, origin_mm=[0,0,0], size_mm=[1,1,1])),
            ('sketchup_duplicate_entities', dict(entity_ids=['101','102'], delta_mm=[0,0,0])),
        ]
        for number, (name, fields) in enumerate(cases, 10):
            self.assertFalse(tools[name]['annotations']['readOnlyHint'])
            self.assertTrue(tools[name]['annotations']['idempotentHint'])
            self.assertIn('command_id',tools[name]['inputSchema']['required'])
            self.send('tools/call',{'name':name,'arguments':dict(common,**fields)},number)
            result = self.response()['result']
            self.assertFalse(result['isError'])
            self.assertEqual(dict(common,**fields),json.loads(result['content'][0]['text'])['arguments'])

    def test_creation_and_duplication_reject_invalid_geometry_and_targets(self):
        self.initialize()
        common = dict(session_id=SESSION,model_id=SESSION,command_id=SESSION+':1',expected_context=[])
        box = dict(name='box',origin_mm=[0,0,0],size_mm=[1000,2000,3000])
        invalid_boxes = [
            dict(box,size_mm=[0,1,1]),dict(box,size_mm=[-1,1,1]),dict(box,size_mm=[.5,1,1]),
            dict(box,size_mm=[1000001,1,1]),dict(box,size_mm=[True,1,1]),dict(box,size_mm=[1,1]),
            dict(box,origin_mm=[1000000001,0,0]),dict(box,origin_mm=['0',0,0]),
            dict(box,name=''),dict(box,name='🙂'*257),dict(box,name='bad\x00name'),dict(box,entity_ids=[]),
        ]
        invalid_boxes.append(dict(origin_mm=[0,0,0],size_mm=[1,1,1]))
        invalid = [('sketchup_create_box',fields) for fields in invalid_boxes]
        invalid += [('sketchup_duplicate_entities',fields) for fields in [
            dict(entity_ids=[],delta_mm=[1,0,0]),dict(entity_ids=['101']*2,delta_mm=[1,0,0]),
            dict(entity_ids=[str(n) for n in range(1,27)],delta_mm=[1,0,0]),
            dict(entity_ids=['101'],delta_mm=[True,0,0]),dict(entity_ids=['101']),
        ]]
        for number,(name,fields) in enumerate(invalid,10):
            self.send('tools/call',{'name':name,'arguments':dict(common,**fields)},number)
            self.assertEqual(-32602,self.response()['error']['code'],(name,fields))

    def test_requires_initialized_notification(self):
        self.send("tools/list", {}, 1)
        self.assertEqual(-32002, self.response()["error"]["code"])
        self.send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                "clientInfo": {"name": "test", "version": "1"}}, 2)
        self.assertEqual("2025-06-18", self.response()["result"]["protocolVersion"])
        self.send("tools/list", {}, 3)
        self.assertEqual(-32002, self.response()["error"]["code"])

    def test_unicode_and_fragmented_input(self):
        self.initialize()
        data = json.dumps({"jsonrpc": "2.0", "id": "unicode", "method": "tools/call",
                           "params": {"name": "sketchup_ping", "arguments": {
                               "session_id": SESSION, "text": "한글 日本語 🙂\n두 번째 줄"}}},
                          ensure_ascii=False).encode("utf-8") + b"\n"
        for offset in range(0, len(data), 7):
            self.raw(data[offset:offset + 7])
        response = self.response()
        self.assertEqual("unicode", response["id"])
        payload = json.loads(response["result"]["content"][0]["text"])
        self.assertEqual("한글 日本語 🙂\n두 번째 줄", payload["arguments"]["text"])

    def test_validation_and_unknown_methods(self):
        self.initialize()
        for args in [{}, {"session_id": "not-a-uuid"}, {"session_id": SESSION, "extra": 1},
                     {"session_id": SESSION, "text": "x" * 4097}]:
            self.send("tools/call", {"name": "sketchup_ping", "arguments": args}, 2)
            self.assertEqual(-32602, self.response()["error"]["code"])
        self.send("tools/call", {"name": "execute_arbitrary_ruby", "arguments": {}}, 3)
        self.assertEqual(-32602, self.response()["error"]["code"])
        self.send("resources/list", {}, 4)
        self.assertEqual(-32601, self.response()["error"]["code"])

    def test_parse_error_and_invalid_request_do_not_break_session(self):
        self.raw(b"{bad json\n")
        self.assertEqual(-32700, self.response()["error"]["code"])
        self.raw(b"[]\n")
        self.assertEqual(-32600, self.response()["error"]["code"])
        self.raw(b'{"jsonrpc":"2.0","id":1.5,"method":"ping"}\n')
        self.assertEqual(-32600, self.response()["error"]["code"])
        self.send("ping", {}, 8)
        self.assertEqual({}, self.response()["result"])

    def test_concurrent_calls_and_cancellation(self):
        self.initialize()
        self.call("slow", "slow-id")
        self.call("fast", "fast-id")
        self.assertEqual("fast-id", self.response()["id"])
        self.send("notifications/cancelled", {"requestId": "slow-id", "reason": "test"})
        canceled = self.response()
        self.assertEqual("slow-id", canceled["id"])
        self.assertTrue(canceled["result"]["isError"])
        self.assertEqual("canceled", json.loads(canceled["result"]["content"][0]["text"])["error"])

    def test_runtime_failure_is_tool_error(self):
        self.initialize()
        self.call("offline")
        response = self.response()
        self.assertNotIn("error", response)
        self.assertTrue(response["result"]["isError"])

    def test_unknown_notification_has_no_response(self):
        self.initialize()
        self.send("notifications/unknown")
        self.send("ping", {}, "only")
        self.assertEqual("only", self.response()["id"])
        self.assertTrue(self.lines.empty())

    def test_eof_cancels_pending_call(self):
        self.initialize()
        self.call("slow")
        self.process.stdin.close()
        self.process.wait(timeout=3)
        self.assertEqual(0, self.process.returncode)

    def test_oversized_frame_closes_connection(self):
        self.raw(b"x" * (1048576 + 1) + b"\n")
        self.process.stdin.close()
        self.process.wait(timeout=3)
        self.assertEqual(1, self.process.returncode)

    def test_duplicate_active_id_closes_without_repeating_tool(self):
        self.initialize()
        self.call("slow", 2)
        self.call("slow", 2)
        self.process.stdin.close()
        self.process.wait(timeout=3)
        self.assertEqual(1, self.process.returncode)


if __name__ == "__main__":
    if not COMMAND:
        raise SystemExit(__doc__)
    unittest.main(verbosity=2)
