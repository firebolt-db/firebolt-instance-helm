"""Run the chart's Envoy retry policy against a deliberately disconnecting backend.

Requires Docker, Helm, and PyYAML. Only the created test container is removed.
The fixture substitutes the upstream address and removes routing/discovery filters;
the chart's route and retry policy are exercised unmodified.
"""
import http.client
from concurrent.futures import ThreadPoolExecutor
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
        calls = {"/reset": 0, "/drained": 0, "/hold": 0}
        accepted = threading.Event()
        release = threading.Event()

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
                if self.path == "/hold":
                    accepted.set()
                    release.wait(15)
                drained = self.path == "/drained" and calls[self.path] == 1
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
        admin_cluster = config["static_resources"]["clusters"][-1]
        config["static_resources"]["clusters"] = [{
            "name": "dynamic_forward_proxy", "type": "LOGICAL_DNS", "connect_timeout": "1s",
            "dns_lookup_family": "V4_ONLY",
            "load_assignment": {"cluster_name": "dynamic_forward_proxy", "endpoints": [{
                "lb_endpoints": [{"endpoint": {"address": {"socket_address": {
                    "address": "host.docker.internal", "port_value": server.server_port,
                }}}}],
            }]},
        }]
        config["static_resources"]["clusters"].append(admin_cluster)
        envoy = resource(render(), "Deployment", "audit-gateway")["spec"]["template"]["spec"]["containers"][0]
        image = envoy["image"]
        container = None
        try:
            with tempfile.TemporaryDirectory(prefix="firebolt-gateway-test-") as temp:
                path = Path(temp) / "envoy.yaml"
                path.write_text(yaml.safe_dump(config))
                container = subprocess.check_output([
                    "docker", "run", "-d",
                    *(["--add-host=host.docker.internal:host-gateway"] if sys.platform == "linux" else []),
                    "-p", "127.0.0.1::8080", "-p", "127.0.0.1::9090", "-v", f"{path}:/etc/envoy/envoy.yaml:ro",
                    image, *envoy["args"], "--concurrency", "1",
                ], text=True).strip()
                port = int(subprocess.check_output(["docker", "port", container, "8080/tcp"], text=True).strip().rsplit(":", 1)[1])

                metrics_port = int(subprocess.check_output(["docker", "port", container, "9090/tcp"], text=True).strip().rsplit(":", 1)[1])

                def request(method, path, body=None, target_port=None):
                    conn = http.client.HTTPConnection("127.0.0.1", target_port or port, timeout=20)
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
                # Run the actual chart preStop while a request is active. It must
                # retain the connection, close query admission, and leave probes up.
                with ThreadPoolExecutor(max_workers=1) as pool:
                    query = pool.submit(request, "POST", "/hold", "long query")
                    self.assertTrue(accepted.wait(5))
                    hook = subprocess.Popen(["docker", "exec", container, *envoy["lifecycle"]["preStop"]["exec"]["command"]], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    try:
                        deadline = time.monotonic() + 5
                        while request("GET", "/healthz", target_port=metrics_port) != 503:
                            self.assertLess(time.monotonic(), deadline)
                            time.sleep(0.1)
                        time.sleep(5.2)  # The chart's endpoint propagation floor.
                        self.assertIsNone(hook.poll(), "preStop exited with a request active")
                        self.assertFalse(query.done())
                        release.set()
                        self.assertEqual(query.result(timeout=5), 200)
                        out, err = hook.communicate(timeout=5)
                        self.assertEqual(hook.returncode, 0, (out, err))
                        self.assertEqual(request("GET", "/healthz", target_port=metrics_port), 503)
                        with self.assertRaises((OSError, http.client.HTTPException)):
                            request("GET", "/healthz")
                    finally:
                        release.set()
                        if hook.poll() is None:
                            hook.terminate()
                            hook.communicate(timeout=5)

        finally:
            if container:
                subprocess.run(["docker", "rm", "-f", container], check=True, stdout=subprocess.DEVNULL)
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
