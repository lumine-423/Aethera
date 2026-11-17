"""A loopback-only allowlisted server for the integration harness and Web build."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit
import mimetypes

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / 'build' / 'web'
STATIC = {'/': ROOT/'web'/'player.html', '/probe': ROOT/'web'/'harness.html', '/protocol.mjs': ROOT/'web'/'protocol.mjs',
          '/host-coordinator.mjs':ROOT/'web'/'host-coordinator.mjs',
          '/art-study':ROOT/'web'/'art-study.html',
          '/art-sheet.png':ROOT/'assets'/'characters'/'rin-study'/'cast-study.png',
          '/art-data.json':ROOT/'assets'/'characters'/'rin-study'/'cast-study.json'}
STATIC.update({'/motion-sheet.png':ROOT/'assets'/'characters'/'rin-motion-v2'/'motion.png',
               '/motion-data.json':ROOT/'assets'/'characters'/'rin-motion-v2'/'motion.json'})
MIME = {'.wasm':'application/wasm', '.pck':'application/octet-stream', '.js':'text/javascript', '.mjs':'text/javascript'}
STATIC['/party-art']=ROOT/'web'/'party-art.html'
STATIC['/player-shell.mjs']=ROOT/'web'/'player-shell.mjs'
for actor in ('mingkong','ye'):
    for filename in ('motion.png','motion.json'):
        STATIC[f'/party/{actor}/{filename}']=ROOT/'assets'/'characters'/f'{actor}-07'/filename

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = unquote(urlsplit(self.path).path)
        target = STATIC.get(route)
        if target is None and route.startswith('/ui-review/'):
            review_root = ROOT/'evidence'/'ui-10'
            candidate = (review_root / route[len('/ui-review/'):]).resolve()
            if candidate.is_relative_to(review_root.resolve()) and candidate.is_file() and candidate.suffix.lower() in {'.html','.json','.md','.png'}:
                target = candidate
        if target is None and route.startswith('/references/'):
            reference_root = ROOT/'design-reference'
            candidate = (reference_root / route[len('/references/'):]).resolve()
            if candidate.is_relative_to(reference_root.resolve()) and candidate.is_file() and candidate.suffix.lower() in {'.html','.json','.md','.png','.jpg','.webp'}:
                target = candidate
        if target is None and route.startswith('/play/'):
            game_root = ROOT/'build'/'game'
            candidate = (game_root / route[len('/play/'):]).resolve()
            if candidate.is_relative_to(game_root.resolve()) and candidate.is_file():
                target = candidate
        if target is None and route.startswith('/game/'):
            candidate = (WEB / route[len('/game/'):]).resolve()
            if candidate.is_relative_to(WEB.resolve()) and candidate.is_file():
                target = candidate
        if target is None or not target.is_file():
            self.send_error(404, 'Only the test harness and exported game are served')
            return
        self.send_response(200)
        self.send_header('Content-Type', MIME.get(target.suffix, mimetypes.guess_type(target)[0] or 'application/octet-stream'))
        self.send_header('Content-Length', str(target.stat().st_size))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        with target.open('rb') as source:
            while chunk := source.read(256*1024):
                try: self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError): break

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--port',type=int,default=8765)
    port = parser.parse_args().port
    print(f'Local integration probe: http://127.0.0.1:{port}', flush=True)
    ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()
