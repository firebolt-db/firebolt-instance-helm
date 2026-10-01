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


class GatewayLifecycleTests(unittest.TestCase):
    def test_discovery_and_serving_endpoints_are_separate(self):
        docs = render()
        discovery = resource(docs, "Service", "audit-engine-default-hl")["spec"]
        serving = resource(docs, "Service", "audit-engine-default-ready")["spec"]
        self.assertTrue(discovery["publishNotReadyAddresses"])
        self.assertFalse(serving["publishNotReadyAddresses"])
        self.assertEqual(serving["clusterIP"], "None")
        self.assertEqual(discovery["selector"], serving["selector"])
        config = resource(docs, "ConfigMap", "audit-gateway")["data"]["envoy.yaml"]
        self.assertIn('-ready.audit.svc.cluster.local:3473', config)
        self.assertIn('no_default_search_domain: true', config)

    def test_gateway_drain_and_probes_match_listener_names(self):
        docs = render()
        pod = resource(docs, "Deployment", "audit-gateway")["spec"]["template"]["spec"]
        envoy = pod["containers"][0]
        self.assertEqual(envoy["livenessProbe"]["httpGet"]["port"], "metrics")
        self.assertEqual(envoy["readinessProbe"]["httpGet"]["port"], "metrics")
        self.assertIn("--drain-time-s", envoy["args"])
        script = envoy["lifecycle"]["preStop"]["exec"]["command"][-1]
        self.assertIn("http.gateway.downstream_cx_active", script)
        self.assertIn("/drain_listeners?inboundonly&graceful", script)
        config = envoy_config()
        self.assertEqual(config["static_resources"]["listeners"][0]["traffic_direction"], "INBOUND")
        self.assertNotIn("traffic_direction", config["static_resources"]["listeners"][1])

    def test_engine_certificate_covers_serving_service(self):
        docs = render({"tls": {"engine": {"enabled": True, "certManager": {"issuerRef": {"name": "ca"}}}}})
        names = resource(docs, "Certificate", "audit-tls-engine")["spec"]["dnsNames"]
        self.assertIn("audit-engine-default-ready.audit.svc.cluster.local", names)
        self.assertIn("audit-engine-default-node-0-0.audit-engine-default-hl.audit.svc.cluster.local", names)


class ConfigurationTests(unittest.TestCase):
    def test_existing_database_secret_reaches_both_consumers(self):
        docs = render({"postgresql": {"credentials": {"existingSecret": "database-creds"}}})
        pg = resource(docs, "StatefulSet", "audit-metadata-pg")["spec"]["template"]["spec"]
        refs = [e["valueFrom"]["secretKeyRef"]["name"] for e in pg["containers"][0]["env"] if "valueFrom" in e]
        self.assertEqual(refs, ["database-creds"] * 3)
        metadata = resource(docs, "Deployment", "audit-metadata-service")["spec"]["template"]["spec"]
        self.assertIn("database-creds", [v["secret"]["secretName"] for v in metadata["volumes"] if "secret" in v])
        self.assertFalse(any(d["kind"] == "Secret" for d in docs))

    def test_storage_class_absent_empty_and_named(self):
        for storage_class in (None, "", "fast"):
            with self.subTest(storage_class=storage_class):
                storage = {"accessModes": ["ReadWriteOnce"], "resources": {"requests": {"storage": "1Gi"}}}
                if storage_class is not None:
                    storage["storageClassName"] = storage_class
                docs = render({"engines": [{"name": "default", "replicas": 1, "storage": storage}]})
                claim = resource(docs, "StatefulSet", "audit-engine-default-node-0")["spec"]["volumeClaimTemplates"][0]["spec"]
                self.assertEqual(claim.get("storageClassName"), storage_class)
                self.assertEqual("storageClassName" in claim, storage_class is not None)

    def test_metadata_rolls_on_identity_and_explicit_secret_restart(self):
        def annotations(values):
            return resource(render(values), "Deployment", "audit-metadata-service")["spec"]["template"]["metadata"]["annotations"]
        baseline = annotations({})
        changed_id = annotations({"customEngineConfig": {"instance": {"id": "01kp98j0000000000000000001"}}})
        self.assertNotEqual(baseline["checksum/config"], changed_id["checksum/config"])
        restarted = annotations({"metadata": {"restartToken": "rotation-2"}})
        self.assertNotEqual(baseline, restarted)
        self.assertEqual(baseline["checksum/config"], restarted["checksum/config"])

    def test_mounts_cannot_shadow_owned_paths_or_duplicate_destinations(self):
        for path in ("/secrets/auth/admin", "/var", "/var/lib/firebolt/../firebolt", "/etc/envoy/tls/gateway"):
            component = "gateway" if path.startswith("/etc/envoy") else "engineSpec"
            extras = {"customVolumes": [{"name": "custom", "emptyDir": {}}],
                      "customVolumeMounts": [{"name": "custom", "mountPath": path}]}
            values = {component: extras} if component == "engineSpec" else {
                component: {"podTemplate": {"volumes": extras["customVolumes"], "volumeMounts": extras["customVolumeMounts"]}}}
            self.assertIn("chart-owned mount", render(values, expect_error=True))
        self.assertIn("duplicate volume mount", render({"engineSpec": {
            "customVolumeMounts": [{"name": "custom", "mountPath": "/custom"},
                                   {"name": "other", "mountPath": "/custom/"}]}}, expect_error=True))
        render({"engineSpec": {"customVolumes": [{"name": "custom", "emptyDir": {}}],
                             "customVolumeMounts": [{"name": "custom", "mountPath": "/custom"}]}})

    def test_reject_invalid_combinations(self):
        cases = [
            ({"engines": [{"name": "same", "replicas": 1}] * 2}, "duplicate engine"),
            ({"engines": [{"name": "x" * 63, "replicas": 1}]}, "exceeds 63"),
            ({"engineSpec": {"extraEnv": [{"name": "FIREBOLT_CORE_NODE", "value": "99"}]}}, "chart-owned environment"),
            ({"engineSpec": {"customVolumes": [{"name": "data", "emptyDir": {}}]}}, "chart-owned volume"),
            ({"engineSpec": {"customVolumeMounts": [{"name": "custom", "mountPath": "/var/lib/firebolt/config.yaml"}]}}, "chart-owned mount"),
            ({"gateway": {"podTemplate": {"podAnnotations": {"checksum/config": "override"}}}}, "reserved"),
            ({"auth": {"signingKeys": [{"id": "same"}] * 2}}, "duplicate signing"),
            ({"postgresql": {"local_enabled": False}}, "postgresql.host is required"),
        ]
        for values, message in cases:
            with self.subTest(values=values):
                self.assertIn(message, render(values, expect_error=True))


class CertificateLifecycleTests(unittest.TestCase):
    def test_restart_tokens_are_component_scoped(self):
        baseline = render()
        def pod(docs, kind, name):
            return resource(docs, kind, name)["spec"]["template"]
        cases = [("engineSpec", "StatefulSet", "audit-engine-default-node-0"),
                 ("gateway", "Deployment", "audit-gateway"),
                 ("metadata", "Deployment", "audit-metadata-service")]
        for component, kind, name in cases:
            docs = render({component: {"restartToken": "rotation-2"}})
            self.assertNotEqual(pod(baseline, kind, name), pod(docs, kind, name))
            for other, other_kind, other_name in cases:
                if other != component:
                    self.assertEqual(pod(baseline, other_kind, other_name), pod(docs, other_kind, other_name))

    def test_tls_hook_verifies_hosts_and_projects_only_ca_keys(self):
        values = {"engines": [{"name": "default", "replicas": 2}], "tls": {
            "engine": {"enabled": True, "existingSecret": {"secretRef": "engine-tls"}},
            "gateway": {"enabled": True, "existingSecret": {"secretRef": "gateway-tls"},
                        "verification": {"serverName": "firebolt.example.com", "caSecret": "gateway-ca"}},
        }}
        hook = resource(render(values), "Pod", "audit-test-tls")["spec"]
        script = hook["containers"][0]["command"][-1]
        self.assertNotIn(" -k", script)
        self.assertNotIn("--insecure", script)
        self.assertIn("--cacert /trust/engine/ca.crt", script)
        self.assertEqual(script.count('--connect-to "$SERVING:3473:$HOST:3473"'), 2)
        self.assertIn("audit-engine-default-ready.audit.svc.cluster.local", script)
        self.assertIn("--connect-to", script)
        self.assertIn("firebolt.example.com", script)
        for volume in hook["volumes"]:
            self.assertEqual(volume["secret"]["items"], [{"key": "ca.crt", "path": "ca.crt"}])
        self.assertFalse(any(d["metadata"]["name"] == "audit-test-tls" for d in render()))
        values["gateway"] = {"enabled": False}
        direct = resource(render(values), "Pod", "audit-test-tls")["spec"]["containers"][0]["command"][-1]
        self.assertNotIn("SERVING=", direct)


if __name__ == "__main__":
    unittest.main()
