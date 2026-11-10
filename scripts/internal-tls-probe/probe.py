# Internal TLS acceptance probe (spec docs/proposals/internal-tls-nlb.md, P1 acceptance 2-4).
# Runs inside Core's image (Python + Debian CA store) as `python -c <this file> NAME NODE_IPS`,
# with no secrets. Standard library only. It prints one line: "PROBE {json}".
import json
import socket
import ssl
import sys
import time
import urllib.request

NAME = sys.argv[1]
NODES = [n for n in (sys.argv[2].split(",") if len(sys.argv) > 2 else []) if n]
CTX = ssl.create_default_context()  # public roots; verifies certificate and hostname
out = {"name": NAME}


def ms(t):
    return int((time.time() - t) * 1000)


try:
    out["resolved"] = sorted({ai[4][0] for ai in socket.getaddrinfo(NAME, 443, proto=socket.IPPROTO_TCP)})
except Exception as e:  # noqa: BLE001 - report, never raise
    out["resolve_error"] = repr(e)[:200]


def get(path):
    t = time.time()
    try:
        with urllib.request.urlopen(f"https://{NAME}{path}", timeout=10, context=CTX) as r:
            body = r.read()
            res = {"status": r.status, "ms": ms(t), "body": body[:200].decode("utf-8", "replace")}
            if path.endswith("jwks.json"):
                res["keys"] = len(json.loads(body).get("keys", []))
            return res
    except Exception as e:  # noqa: BLE001
        return {"error": repr(e)[:300], "ms": ms(t)}


out["jwks"] = get("/.well-known/jwks.json")
out["ready"] = get("/ready")

# Per-node check: connect to each NLB node IP explicitly with SNI NAME and record where a node
# without a local target fails (TCP connect, TLS handshake, or after the handshake).
nodes = {}
for ip in NODES:
    r, t = {}, time.time()
    try:
        s = socket.create_connection((ip, 443), timeout=5)
        r["tcp"] = "ok"
        r["self_ip"] = s.getsockname()[0]
        try:
            ss = CTX.wrap_socket(s, server_hostname=NAME)
            r["tls"] = "ok"
            ss.settimeout(10)
            ss.sendall(f"GET /ready HTTP/1.1\r\nHost: {NAME}\r\nConnection: close\r\n\r\n".encode())
            data = b""
            while True:
                chunk = ss.recv(4096)
                if not chunk:
                    break
                data += chunk
            r["http"] = data.split(b"\r\n", 1)[0].decode("latin-1") if data else "empty"
            ss.close()
        except Exception as e:  # noqa: BLE001
            r["after_tcp_error"] = repr(e)[:200]
    except Exception as e:  # noqa: BLE001
        r["tcp_error"] = repr(e)[:200]
    r["ms"] = ms(t)
    nodes[ip] = r
out["nodes"] = nodes
print("PROBE " + json.dumps(out, sort_keys=True), flush=True)
