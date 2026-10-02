"""Run the chart's Envoy retry policy against a deliberately disconnecting backend.

Requires Docker, Helm, and PyYAML. Only the created test container is removed.
The fixture substitutes the upstream address and removes routing/discovery filters;
the chart's route and retry policy are exercised unmodified.
"""
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

import yaml
from test_render import envoy_config, render, resource


class RetryRuntimeTests(unittest.TestCase):
    def test_delivered_reset_is_not_replayed_but_drained_response_is(self):
        calls = {"/reset": 0, "/drained": 0}

        class Backend(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                self.rfile.read(int(self.headers.get("Content-Length", 0)))
                calls[self.path] += 1
                if self.path == "/reset":
                    # The mutation has happened. Close before response headers.
                    self.close_connection = True
                    return
                drained = calls[self.path] == 1
                self.send_response(503 if drained else 200)
                if drained:
                    self.send_header("X-Firebolt-Drained", "true")
                self.send_header("Content-Length", "0")
                self.end_headers()

        server = ThreadingHTTPServer(("0.0.0.0", 0), Backend)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        config = envoy_config()
        listener = config["static_resources"]["listeners"][0]
        hcm = listener["filter_chains"][0]["filters"][0]["typed_config"]
        hcm["http_filters"] = [f for f in hcm["http_filters"] if f["name"] in {
            "envoy.filters.http.health_check", "envoy.filters.http.router",
        }]
        config["static_resources"]["clusters"] = [{
            "name": "dynamic_forward_proxy", "type": "LOGICAL_DNS", "connect_timeout": "1s",
            "dns_lookup_family": "V4_ONLY",
            "load_assignment": {"cluster_name": "dynamic_forward_proxy", "endpoints": [{
                "lb_endpoints": [{"endpoint": {"address": {"socket_address": {
                    "address": "host.docker.internal", "port_value": server.server_port,
                }}}}],
            }]},
        }]
        config["static_resources"]["listeners"] = [listener]
        image = resource(render(), "Deployment", "audit-gateway")["spec"]["template"]["spec"]["containers"][0]["image"]
        container = None
        try:
            with tempfile.TemporaryDirectory(prefix="firebolt-gateway-test-") as temp:
                path = Path(temp) / "envoy.yaml"
                path.write_text(yaml.safe_dump(config))
                container = subprocess.check_output([
                    "docker", "run", "-d",
                    *(["--add-host=host.docker.internal:host-gateway"] if sys.platform == "linux" else []),
                    "-p", "127.0.0.1::8080", "-v", f"{path}:/etc/envoy/envoy.yaml:ro",
                    image, "envoy", "-c", "/etc/envoy/envoy.yaml", "--concurrency", "1",
                ], text=True).strip()
                port = int(subprocess.check_output(["docker", "port", container, "8080/tcp"], text=True).strip().rsplit(":", 1)[1])

                def request(method, path, body=None):
                    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=20)
                    try:
                        conn.request(method, path, body=body)
                        response = conn.getresponse()
                        response.read()
                        return response.status
                    finally:
                        conn.close()

                deadline = time.monotonic() + 30
                while True:
                    try:
                        if request("GET", "/healthz") == 200:
                            break
                    except (OSError, http.client.HTTPException):
                        pass
                    if time.monotonic() >= deadline:
                        self.fail(subprocess.check_output(["docker", "logs", container], text=True, stderr=subprocess.STDOUT))
                    time.sleep(0.1)
                self.assertEqual(request("POST", "/reset", "mutation"), 503)
                self.assertEqual(calls["/reset"], 1, subprocess.check_output(["docker", "logs", container], text=True, stderr=subprocess.STDOUT))
                self.assertEqual(request("POST", "/drained", "mutation"), 200)
                self.assertEqual(calls["/drained"], 2, "the pre-work fence should be retried")
        finally:
            if container:
                subprocess.run(["docker", "rm", "-f", container], check=True, stdout=subprocess.DEVNULL)
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
