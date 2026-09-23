"""Local preview with a narrowly scoped endpoint for rendered roster portraits."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parent.parent
ALLOWED = {"tribal", "bunny", "skull-orc", "evolved-dragon", "orc", "hulk"}

class Handler(SimpleHTTPRequestHandler):
    def do_POST(self):
        name = self.path.removeprefix('/__portrait/')
        length = int(self.headers.get('Content-Length', '0'))
        if not self.path.startswith('/__portrait/') or name not in ALLOWED or not 0 < length < 2000000:
            self.send_error(400)
            return
        data = self.rfile.read(length)
        if data[:4] != b'RIFF' or data[8:12] != b'WEBP':
            self.send_error(415)
            return
        (ROOT / 'assets' / 'portraits' / (name + '.webp')).write_bytes(data)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

if __name__ == '__main__':
    os.chdir(ROOT)
    ThreadingHTTPServer(('127.0.0.1', 4177), Handler).serve_forever()
