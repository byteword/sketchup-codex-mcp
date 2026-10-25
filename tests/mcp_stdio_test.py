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
        self.assertEqual(15, len(tools))
        self.assertEqual(15, len({tool["name"] for tool in tools}))
        for tool in tools:
            self.assertFalse(tool["inputSchema"]["additionalProperties"])
        self.assertTrue(next(t for t in tools if t["name"] == "sketchup_ping")["annotations"]["readOnlyHint"])
        for name in ["sketchup_get_model_summary", "sketchup_get_selection_info"]:
            tool = next(t for t in tools if t["name"] == name)
            self.assertEqual(["session_id", "model_id"], tool["inputSchema"]["required"])
            self.assertTrue(tool["annotations"]["readOnlyHint"])

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
