from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'build/home'
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs): super().__init__(*args,directory=str(ROOT),**kwargs)
    def list_directory(self,path): self.send_error(404); return None
    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        super().end_headers()
if __name__=='__main__':
    print('Home UI: http://127.0.0.1:8771',flush=True)
    ThreadingHTTPServer(('127.0.0.1',8771),Handler).serve_forever()
