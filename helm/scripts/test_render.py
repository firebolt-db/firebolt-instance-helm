"""Chart behavior regressions. Requires Helm and PyYAML (also used by yamllint)."""
import json
import os
from pathlib import Path
import subprocess
import unittest

import yaml

CHART = Path(__file__).resolve().parents[1]


def render(values=None, release="audit", namespace="audit", expect_error=False):
    result = subprocess.run(
        [os.environ.get("HELM", "helm"), "template", release, str(CHART),
         "--namespace", namespace, "-f", "-"],
        input=json.dumps(values or {}), text=True, capture_output=True,
    )
    if expect_error:
        if result.returncode == 0:
            raise AssertionError("invalid values rendered successfully")
        return result.stderr
    if result.returncode:
        raise AssertionError(result.stderr)
    return [doc for doc in yaml.safe_load_all(result.stdout) if doc]


def resource(docs, kind, name):
    return next(d for d in docs if d["kind"] == kind and d["metadata"]["name"] == name)


def envoy_config(values=None):
    return yaml.safe_load(resource(render(values), "ConfigMap", "audit-gateway")["data"]["envoy.yaml"])


class GatewaySafetyTests(unittest.TestCase):
    def test_retries_do_not_replay_delivered_requests(self):
        config = envoy_config()
        hcm = config["static_resources"]["listeners"][0]["filter_chains"][0]["filters"][0]["typed_config"]
        policy = hcm["route_config"]["virtual_hosts"][0]["routes"][0]["route"]["retry_policy"]
        self.assertEqual(set(policy["retry_on"].split(",")), {
            "connect-failure", "refused-stream", "reset-before-request", "retriable-headers",
        })
        self.assertEqual(policy["retriable_headers"], [{"name": "X-Firebolt-Drained", "present_match": True}])


if __name__ == "__main__":
    unittest.main()
