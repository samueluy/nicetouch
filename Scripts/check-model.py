"""End-to-end real-model smoke checks. No keyboard actions or saved-rule mutations."""
import json
from pathlib import Path
import selectors
import subprocess
import sys
import time
import jsonschema

root = Path(__file__).resolve().parent.parent
resources = root / "Sources/NiceTouch/Resources"
schema = json.loads((resources / "rule.schema.json").read_text())
prompt = (resources / "system-prompt.txt").read_text()
model = str(Path(sys.argv[1]).resolve(strict=True))
process = subprocess.Popen([sys.executable, "-u", str(resources / "mlx_worker.py"), model], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)

def reply():
    if not selector.select(timeout=120):
        raise TimeoutError("No worker response in 120 seconds")
    line = process.stdout.readline()
    if not line:
        raise RuntimeError("Worker exited: " + process.stderr.read()[-2000:])
    result = json.loads(line)
    if "error" in result:
        raise RuntimeError(result["error"])
    return result

try:
    started = time.monotonic()
    assert reply().get("ready") is True
    print(f"Model loaded offline in {time.monotonic() - started:.2f}s", flush=True)
    cases = [
        ("When I swipe three fingers left in Chrome, switch to the previous tab.", "com.google.Chrome", "swipe", 3, "left", "anywhere", "previousTab"),
        ("When I tap with four fingers in the top zone in Safari, reopen the closed tab.", "com.apple.Safari", "tap", 4, "none", "top", "reopenTab"),
        ("When I swipe four fingers up in all apps, copy.", "*", "swipe", 4, "up", "anywhere", "copy"),
    ]
    for command, app, kind, fingers, direction, zone, action in cases:
        started = time.monotonic()
        process.stdin.write(json.dumps({"system": prompt, "prompt": command}) + "\n"); process.stdin.flush()
        result = json.loads(reply()["text"])
        jsonschema.validate(result, schema)
        assert result["app"] == app, result
        assert result["gesture"] == {"kind": kind, "fingers": fingers, "direction": direction, "zone": zone}, result
        assert result["action"] == action, result
        print(f"PASS ({time.monotonic() - started:.2f}s): {command}\n{json.dumps(result)}", flush=True)
    process.stdin.write(json.dumps({"system": prompt, "prompt": "Make my trackpad better"}) + "\n"); process.stdin.flush()
    result = json.loads(reply()["text"])
    assert set(result) == {"error"} and result["error"], result
    print("PASS: ambiguous request asks for clarification", flush=True)
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill(); process.wait()
    selector.close()
