#!/usr/bin/env python3
"""Tiny OpenAI-compatible mock for developing Haku without LM Studio.

  python3 tools/mock-llm/server.py [port]

Streams replies; emits tool calls for a few keywords so the tool paths can be exercised:
  "open <app>"           -> open_app
  "run the tests in X"   -> delegate_agent (claude, dir ~/code/X)
  "list files"           -> run_shell (ls)
  "think hard"           -> escalate
"""
import json, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODELS = ["gemma-4-e4b", "qwen3.8-27b"]

def tool_for(text):
    t = text.lower()
    m = re.search(r"\bopen (\w+)", t)
    if m: return ("open_app", {"name": m.group(1)})
    m = re.search(r"run the tests in (\S+)", t)
    if m: return ("delegate_agent", {"agent": "claude", "task": f"Run the test suite in this repo and report which tests fail and why.", "dir": (lambda d: d if d.startswith("/") else f"~/code/{d}")(m.group(1).strip(".?"))})
    if "list files" in t: return ("run_shell", {"cmd": "ls -la", "dir": "~"})
    if "think hard" in t: return ("escalate", {"prompt": text})
    return None

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        if self.path.endswith("/models"):
            return self._json({"data": [{"id": m} for m in MODELS]})
        self._json({"error": "not found"}, 404)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or b"{}")
        msgs = req.get("messages", [])
        last = msgs[-1] if msgs else {}
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()

        def send(delta, finish=None):
            chunk = {"choices": [{"delta": delta, "finish_reason": finish}]}
            self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode()); self.wfile.flush()

        user = next((m.get("content") or "" for m in reversed(msgs) if m.get("role") == "user"), "")
        call = tool_for(user) if req.get("tools") and last.get("role") == "user" else None
        if call:
            name, args = call
            send({"tool_calls": [{"index": 0, "id": "call_1", "function": {"name": name, "arguments": json.dumps(args)}}]}, "tool_calls")
        else:
            if last.get("role") == "tool":
                reply = f"Done — {last.get('content','')[:80]}"
            elif req.get("model", "").startswith("qwen"):
                reply = "Thinking it through: the short answer is that it depends on ==your constraints==."
            elif "title for this task" in user:
                reply = "Run tests and report failures"
            elif "spoken sentence" in user:
                reply = "Claude Code finished; three tests are failing in compose spec."
            else:
                reply = f"You said: {user[:120]}. I'm the mock model, so that's all I've got."
            for word in re.findall(r"\S+\s*", reply):
                send({"content": word}); time.sleep(0.02)
            send({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 1234
    print(f"mock LLM on http://localhost:{port}/v1")
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
