"""Opens the activation mixer page in headless Edge (DevTools protocol) and checks that the four
clips decode, the timeline draws and the exported settings are right. Saves a screenshot.
Usage: python tools/check_activation_mixer.py
"""
import base64
import json
import os
import subprocess
import tempfile
import time
import urllib.request

import websocket

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(PROJ, "workspaces", "frontend-ui", "materials", "workshop-activation-20261117", "activation_mixer.html")
SHOT = os.path.join(os.path.dirname(PAGE), "_mixer_preview.png")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PORT = 9333


def main():
    prof = tempfile.mkdtemp()
    url = "file:///" + PAGE.replace("\\", "/")
    p = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--remote-debugging-port=%d" % PORT, "--user-data-dir=" + prof,
                          "--window-size=1600,900", "--autoplay-policy=no-user-gesture-required", url])
    try:
        ws_url = None
        for _ in range(50):
            try:
                tabs = json.load(urllib.request.urlopen("http://127.0.0.1:%d/json" % PORT))
                ws_url = next(t["webSocketDebuggerUrl"] for t in tabs if t.get("type") == "page")
                break
            except Exception:
                time.sleep(0.2)
        ws = websocket.create_connection(ws_url, timeout=30)
        mid = [0]

        def call(method, **params):
            mid[0] += 1
            ws.send(json.dumps({"id": mid[0], "method": method, "params": params}))
            while True:
                m = json.loads(ws.recv())
                if m.get("id") == mid[0]:
                    return m.get("result", {})

        def ev(js):
            return call("Runtime.evaluate", expression=js, returnByValue=True, awaitPromise=True).get("result", {}).get("value")

        for _ in range(60):
            msg = ev("document.getElementById('msg').textContent")
            if msg and "就绪" in msg or (msg and "失败" in msg):
                break
            time.sleep(0.5)
        print("status:", msg)
        print("decoded:", ev("JSON.stringify(Object.fromEntries(Object.entries(buffers).map(([k,b])=>[k,+b.duration.toFixed(3)])))"))
        print("export:", ev("exportJson()").replace("\n", ""))
        # drag test: move clip 3 by +1 s through the same code path the mouse uses
        ev("st.start.loop_b += 1; applyAuto(); changed(); 0")
        print("after moving 3 by +1s:", ev("exportJson()").replace("\n", ""))
        ev("defaults(); changed(); 0")
        shot = call("Page.captureScreenshot", format="png")
        with open(SHOT, "wb") as f:
            f.write(base64.b64decode(shot["data"]))
        print("screenshot", SHOT)
        ws.close()
    finally:
        p.terminate()


if __name__ == "__main__":
    main()
