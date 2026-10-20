"""Serves a System One answer function on 127.0.0.1: GET /health, POST /v1/systemone."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


def serve(name, port, answer, health=None):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path == "/health":
                return self._send(200, {"ok": True, **(health or {})})
            self._send(404, {"detail": "not found"})

        def do_POST(self):  # noqa: N802
            if self.path != "/v1/systemone":
                return self._send(404, {"detail": "not found"})
            try:
                req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                self._send(200, answer(req))
            except (KeyError, ValueError) as exc:
                self._send(422, {"detail": f"{type(exc).__name__}: {exc}"})
            except Exception as exc:  # noqa: BLE001
                self._send(500, {"detail": f"{type(exc).__name__}: {exc}"})

        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    print(f"{name} serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
