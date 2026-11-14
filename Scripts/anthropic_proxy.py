"""Anthropic-shaped reverse proxy that swaps auth on the way upstream.

Some providers speak the Anthropic wire format but expect an
`Authorization: Bearer` token rather than the `x-api-key` header an
Anthropic SDK sends. This proxy sits in front of such an endpoint so
`opencode` can reach it through a stock `@ai-sdk/anthropic` provider
block.

Configure it with the environment, never with a path baked into the file:

    APPLEBENCH_PROXY_UPSTREAM   required, e.g. https://example.com/v1/llm
    APPLEBENCH_PROXY_TOKEN      the bearer token, or
    APPLEBENCH_PROXY_TOKEN_FILE a JSON file to read the token out of
    APPLEBENCH_PROXY_TOKEN_PATH dotted key path into that file
                                (default: auth.accessToken)

Point AppleBench at the running proxy with a provider override:

    export APPLEBENCH_OPENCODE_PROVIDER='{"local":{"npm":"@ai-sdk/anthropic",
      "options":{"baseURL":"http://127.0.0.1:8765/v1","apiKey":"unused"},
      "models":{"your-model":{"name":"your-model"}}}}'

Retry policy: transient upstream failures (HTTP 5xx, 429, timeouts,
connection resets) are retried with exponential backoff up to
MAX_ATTEMPTS times, waiting 0.5s, 1s, 2s, 4s. A persistent failure
still surfaces to the agent so the task fails loudly rather than hangs.
"""
import http.server
import json
import os
import socketserver
import sys
import time
import urllib.error
import urllib.request

MAX_ATTEMPTS = 5
RETRYABLE_STATUS = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}
HOP_BY_HOP = {"transfer-encoding", "content-encoding", "content-length", "connection"}


def _load_token() -> str:
    """Resolve the upstream bearer token from the environment.

    Reading it from a file is supported because some runtimes write a
    short-lived token to disk rather than exporting it.
    """
    token = os.environ.get("APPLEBENCH_PROXY_TOKEN")
    if token:
        return token

    path = os.environ.get("APPLEBENCH_PROXY_TOKEN_FILE")
    if not path:
        sys.exit(
            "error: set APPLEBENCH_PROXY_TOKEN or APPLEBENCH_PROXY_TOKEN_FILE"
        )
    try:
        with open(os.path.expanduser(path), encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        sys.exit(f"error: could not read token file {path}: {error}")

    key_path = os.environ.get("APPLEBENCH_PROXY_TOKEN_PATH", "auth.accessToken")
    cursor = document
    for key in key_path.split("."):
        if not isinstance(cursor, dict) or key not in cursor:
            sys.exit(f"error: {path} has no key '{key_path}'")
        cursor = cursor[key]
    if not isinstance(cursor, str) or not cursor:
        sys.exit(f"error: {path}:{key_path} is not a non-empty string")
    return cursor


UPSTREAM = os.environ.get("APPLEBENCH_PROXY_UPSTREAM", "").rstrip("/")
if not UPSTREAM:
    sys.exit("error: set APPLEBENCH_PROXY_UPSTREAM to the upstream base URL")
TOKEN = _load_token()


def _forward(path: str, body: bytes, headers: dict):
    """POST `body` upstream, retrying transient failures.

    Every attempt re-sends the *original* request body and path. An earlier
    version reused the variable holding the error response, so a retry
    silently posted the upstream's error payload back to it.
    """
    last_error = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        request = urllib.request.Request(
            UPSTREAM + path, data=body, headers=headers, method="POST"
        )
        try:
            with urllib.request.urlopen(request, timeout=600) as response:
                return response.status, list(response.getheaders()), response.read()
        except urllib.error.HTTPError as error:
            payload = error.read()
            if error.code not in RETRYABLE_STATUS or attempt == MAX_ATTEMPTS:
                return error.code, list(error.headers.items()), payload
            last_error = error
        except (BrokenPipeError, ConnectionResetError, TimeoutError, urllib.error.URLError) as error:
            if attempt == MAX_ATTEMPTS:
                raise
            last_error = error
        time.sleep(0.5 * (2 ** (attempt - 1)))
    raise last_error  # unreachable; the loop returns or raises first


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self._write(b"ok")
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""
        headers = {
            "Content-Type": self.headers.get("Content-Type", "application/json"),
            "Authorization": f"Bearer {TOKEN}",
            "anthropic-version": self.headers.get("anthropic-version", "2023-06-01"),
        }
        try:
            status, response_headers, response_body = _forward(self.path, body, headers)
        except Exception as error:  # noqa: BLE001 — the agent must see the failure
            self._fail(f"proxy upstream exhausted retries: {error}")
            return

        try:
            self.send_response(status)
            for key, value in response_headers:
                if key.lower() not in HOP_BY_HOP:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            self._write(response_body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _fail(self, message: str) -> None:
        try:
            payload = message.encode()
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self._write(payload)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def _write(self, data: bytes) -> None:
        """Write a body, swallowing the broken pipe an agent causes when it
        cancels mid-stream. Without this every dropped request prints a
        stack trace and the proxy reads as if it crashed."""
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"proxy: 127.0.0.1:{port} → {UPSTREAM} (retry {MAX_ATTEMPTS}x)", file=sys.stderr)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
