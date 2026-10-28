"""One native SketchUp smoke command over production MCP STDIO. No retries."""
import argparse
import json
import pathlib
import queue
import subprocess
import threading
import time


class Client:
    def __init__(self, command, timeout):
        self.timeout = timeout
        self.number = 0
        self.lines = queue.Queue()
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL,
                                        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        def read():
            try:
                for line in self.process.stdout:
                    self.lines.put(json.loads(line.decode('utf-8')))
            except Exception as error:
                self.lines.put({'reader_error': str(error)})
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()

    def send(self, message):
        self.process.stdin.write(json.dumps(message, ensure_ascii=True).encode('utf-8') + b'\n')
        self.process.stdin.flush()

    def rpc(self, method, params):
        self.number += 1
        request_id = self.number
        self.send(dict(jsonrpc='2.0', id=request_id, method=method, params=params))
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('MCP response deadline exceeded')
            try:
                response = self.lines.get(timeout=remaining)
            except queue.Empty as error:
                raise TimeoutError('MCP response deadline exceeded') from error
            if 'reader_error' in response:
                raise RuntimeError(response['reader_error'])
            if response.get('id') != request_id:
                continue
            if 'error' in response:
                raise RuntimeError(str(response['error']))
            return response['result']

    def tool(self, name, args=None):
        result = self.rpc('tools/call', dict(name=name, arguments=args or {}))
        block = next((c for c in result.get('content', []) if c.get('type') == 'text'), None)
        if block is None:
            raise RuntimeError('Missing structured tool response')
        value = json.loads(block['text'])
        if result.get('isError') or value.get('ok') is False:
            raise RuntimeError(value.get('status') or value.get('message') or str(value))
        return value

    def close(self):
        try:
            self.process.stdin.close()
            self.process.wait(timeout=5)
        except (BrokenPipeError, subprocess.TimeoutExpired):
            if self.process.poll() is None:
                self.process.kill()  # Only this runner's adapter, never GUI/SketchUp.
                self.process.wait()
        finally:
            self.reader.join(timeout=1)
            self.process.stdout.close()


def run(args):
    started = time.monotonic()
    client = Client([str(pathlib.Path(args.mcp_exe).resolve())] + args.mcp_arg, args.timeout)
    command_id = None
    submitted = False
    try:
        initialized = client.rpc('initialize', dict(protocolVersion='2025-11-25', capabilities={},
                                                     clientInfo=dict(name='sketchup-native-batch', version='1')))
        client.send(dict(jsonrpc='2.0', method='notifications/initialized'))
        instances = client.tool('sketchup_list_instances')['instances']
        if not any(i['session_id'] == args.session_id and i['model_id'] == args.model_id for i in instances):
            raise RuntimeError('Target session/model is no longer current; rediscover it')
        target = dict(session_id=args.session_id, model_id=args.model_id)
        bridge = client.tool('sketchup_bridge_status')
        state = client.tool('sketchup_get_instance', dict(session_id=args.session_id))['state']
        version = initialized['serverInfo']['version']
        if not (version == bridge['version'] == state['extension_version']):
            raise RuntimeError('Adapter/bridge/extension versions differ; restart matching runtime files')
        tools = client.rpc('tools/list', {})['tools']
        if not any(t['name'] == 'sketchup_run_self_test' for t in tools):
            raise RuntimeError('Installed adapter has no batch test tool')
        if state['model_id'] != args.model_id or state['authority'] != 'mcp':
            raise RuntimeError('Target changed or local execution permission is missing')
        selection = client.tool('sketchup_get_selection_info', target)['data']
        context = selection['edit_context']
        if context['path_truncated'] or context['path']:
            raise RuntimeError('Exit group editing; batch test requires model root')
        state = client.tool('sketchup_get_instance', dict(session_id=args.session_id))['state']
        if state['model_id'] != args.model_id or state['authority'] != 'mcp':
            raise RuntimeError('Target or permission changed before test submission')
        command_id = state['next_command_id']
        fields = dict(target, command_id=command_id, expected_context=[], confirm_test_model=True)
        submitted = True
        recovered = False
        try:
            result = client.tool('sketchup_run_self_test', fields)['result']
        except TimeoutError:
            # Read the cached outcome once; never repeat the test command.
            result = client.tool('sketchup_get_command_result', dict(target, command_id=command_id))['result']
            recovered = True
        if result.get('state') != 'completed':
            raise RuntimeError('Command outcome is not completed: ' + str(result.get('state')))
        report = result['data']
        if report.get('dry_run') or not report.get('cleanup_verified'):
            raise RuntimeError('Suite did not certify execution and cleanup')
        return dict(status='passed' if report.get('passed') else 'failed', version=version,
                    session_id=args.session_id, model_id=args.model_id, command_id=command_id,
                    recovered_by_result_lookup=recovered, elapsed_ms=round((time.monotonic()-started)*1000),
                    report=report)
    except Exception as error:
        return dict(status='unknown' if submitted else 'blocked', session_id=args.session_id,
                    model_id=args.model_id, command_id=command_id, message=str(error),
                    instruction='Query this command_id; do not automatically rerun.' if submitted else 'Resolve target/version/root-context/local permission before a new run.')
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mcp-exe', required=True)
    parser.add_argument('--mcp-arg', action='append', default=[])
    parser.add_argument('--session-id', required=True)
    parser.add_argument('--model-id', required=True)
    parser.add_argument('--confirm-test-model', action='store_true', required=True)
    parser.add_argument('--timeout', type=float, default=20)
    parser.add_argument('--output', default='native-test-report.json')
    args = parser.parse_args()
    if not pathlib.Path(args.mcp_exe).is_file() or not 0.05 <= args.timeout <= 120:
        parser.error('Executable must exist; timeout must be between 0.05 and 120 seconds')
    try:
        result = run(args)
    except Exception as error:
        result = dict(status='blocked', message=str(error))
    path = pathlib.Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
