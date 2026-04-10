import subprocess
import sys
import time
import os
from capture import PacketCapture

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUTDIR = os.path.join(ROOT, 'interface_trials')
os.makedirs(OUTDIR, exist_ok=True)

ifaces = PacketCapture(lambda p, d: None).list_interfaces()
print('Interfaces:', ifaces)

for iface in ifaces:
    if 'Loopback' in iface or 'NPF_Loopback' in iface:
        print('Skipping loopback:', iface)
        continue

    safe_name = iface.replace('\\', '_').replace(
        '/', '_').replace(':', '_').replace('{', '').replace('}', '')
    logfile = os.path.join(OUTDIR, f"{safe_name}.log")
    print('\n=== Trying interface:', iface)

    # Stop any existing backend listening on 8765 (best-effort)
    # Not portable on non-Windows, but this script runs on Windows in this repo's environment
    try:
        import psutil
        for p in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if 'main.py' in ' '.join(p.info.get('cmdline', [])):
                    print('Killing previous backend pid', p.info['pid'])
                    p.kill()
            except Exception:
                pass
    except Exception:
        pass

    # Start backend with interface
    p = subprocess.Popen([sys.executable, os.path.join(
        ROOT, 'backend', 'main.py'), '--iface', iface], cwd=ROOT)
    time.sleep(2)

    # Run collect_ws_logs.py and capture output
    print('Collecting websocket logs to', logfile)
    with open(logfile, 'wb') as f:
        try:
            c = subprocess.Popen([sys.executable, os.path.join(
                ROOT, 'backend', 'collect_ws_logs.py')], cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
            c.wait(timeout=40)
        except subprocess.TimeoutExpired:
            c.kill()
            print('Collector timed out')

    # Stop backend
    try:
        p.terminate()
        time.sleep(0.5)
        p.kill()
    except Exception:
        pass

    # Quick analysis: check if total_damage > 0 in logfile
    has_damage = False
    try:
        with open(logfile, 'r', encoding='utf-8', errors='ignore') as f:
            txt = f.read()
            if '"total_damage":' in txt:
                for line in txt.splitlines():
                    if '"total_damage":' in line:
                        if any(ch.isdigit() for ch in line):
                            if ': 0' not in line:
                                has_damage = True
                                break
    except Exception:
        pass

    print('Result for', iface, 'damage_detected=', has_damage)

print('\nDone. Logs saved in', OUTDIR)
