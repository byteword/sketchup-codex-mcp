"""STDIO fixture for the standalone runner; no SketchUp or Windows pipes."""
import json
import pathlib
import sys

mode, log = sys.argv[1], pathlib.Path(sys.argv[2])
session = '11111111-1111-4111-8111-111111111111'
model = '22222222-2222-4222-8222-222222222222'
report = dict(dry_run=False, passed=True, cleanup_verified=True, passed_count=56,
              failed_count=0, skipped_count=0, checks=[dict(name='cleanup', status='passed')], duration_ms=12)
for line in sys.stdin:
    message = json.loads(line)
    if 'id' not in message:
        continue
    method, params = message['method'], message.get('params', {})
    if method == 'initialize':
        result = dict(serverInfo=dict(version='0.6.0'), capabilities={}, protocolVersion='2025-11-25')
    elif method == 'tools/list':
        result = dict(tools=[dict(name='sketchup_run_self_test',inputSchema=dict(properties={} if mode == 'old_schema' else dict(suite={})))])
    else:
        name = params['name']
        with log.open('a', encoding='utf-8') as stream:
            stream.write(name + '\n')
        if name == 'sketchup_list_instances':
            value = dict(instances=[dict(session_id=session, model_id=model)])
        elif name == 'sketchup_bridge_status':
            value = dict(version='0.4.1' if mode == 'version' else '0.6.0')
        elif name == 'sketchup_get_instance':
            value = dict(state=dict(model_id=model, authority='user' if mode == 'permission' else 'mcp',
                                    extension_version='0.6.0', next_command_id=session + ':1'))
        elif name == 'sketchup_get_selection_info':
            value = dict(data=dict(edit_context=dict(path=[], path_truncated=False)))
        elif name in ('sketchup_run_self_test', 'sketchup_get_command_result'):
            if name == 'sketchup_run_self_test' and params['arguments'].get('suite') != 'all':
                raise RuntimeError('Runner must select the requested all suite')
            if mode == 'lost' and name == 'sketchup_run_self_test':
                continue
            value = dict(ok=True, result=dict(state='completed', data=report))
        else:
            raise RuntimeError('Unexpected tool ' + name)
        result = dict(isError=False, content=[dict(type='text', text=json.dumps(value))])
    print(json.dumps(dict(jsonrpc='2.0', id=message['id'], result=result)), flush=True)
