"""Serves model files from a folder on 127.0.0.1 for the first-run test, so no download touches the internet.

Throttled (--rate bytes per second) so progress, speed and Cancel can be seen; honours Range so resuming is tested.
Logs each request's Range header to stdout. Usage: model-server.py <folder> <port> [--rate N]
"""
import http.server
import os
import sys
import time

folder, port = sys.argv[1], int(sys.argv[2])
rate = int(sys.argv[sys.argv.index("--rate") + 1]) if "--rate" in sys.argv else 0


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = os.path.join(folder, os.path.basename(self.path))
        if not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        start = 0
        rng = self.headers.get("Range")
        print(f"GET {self.path} range={rng}", flush=True)
        if rng and rng.startswith("bytes="):
            start = int(rng[6:].split("-")[0])
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{size - 1}/{size}")
        else:
            self.send_response(200)
        self.send_header("Content-Length", str(size - start))
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            chunk = 64 * 1024
            while True:
                data = f.read(chunk)
                if not data:
                    break
                try:
                    self.wfile.write(data)
                except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
                    return
                if rate:
                    time.sleep(len(data) / rate)

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
