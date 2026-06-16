# Agentic local deployment

A single-command, no-human-in-the-loop path to deploy the `firebolt-instance`
chart to a local [kind](https://kind.sigs.k8s.io/) cluster, prove it serves
queries, and tear it back down. Built for AI agents iterating on chart changes:
the output is machine-parseable and the exit code is authoritative.

```bash
make agent-up      # clean machine -> running instance + smoke query
# ... edit the chart, re-verify in seconds with the fast loop below ...
make agent-verify  # apply changes in place (helm upgrade) + smoke query
make agent-down    # return the host to a clean state
```

## Tiered iteration loop

Teardown/reinstall is the wrong tool for iterating — pick the cheapest tier that
can catch your change:

| Tier | Command | Cluster? | Cost | Use for |
| --- | --- | --- | --- | --- |
| 0 | `make lint` | none | sub-second | every edit — `helm lint --strict` + `helm template` catch template/schema errors |
| 1 | `make agent-verify` | reused | ~5s | the inner loop — `helm upgrade --install` applies the change in place; the chart's `checksum/config` annotations roll only the pods whose effective config changed (an unchanged engine stays warm, no cold restart), then a single `SELECT 1` proves it serves |
| 1+ | `make agent-verify THOROUGH=true` | reused | ~40s | same as tier 1, then the chart's **full helm test suite** (`helm/templates/tests/*.yaml`: DNS for every service, configmaps, postgres, metadata, engine-pods-reachable, auth, plus its own `SELECT 1`). Opt in when a change touches wiring the fast query won't exercise |
| 2 | `make agent-up` | reused/created | ~1–2 min | clean from-scratch validation, or changes `helm upgrade` can't apply in place (immutable fields: StatefulSet `volumeClaimTemplates`, selector labels) |

The agent chooses depth per change: a narrow template tweak needs only tier 0/1;
a change to services, ConfigMaps, DNS, or storage wiring warrants tier 1+
(`THOROUGH=true`, which also works on `agent-up`). The result JSON's
`verify_mode` field (`fast`/`thorough`) records which depth actually ran.

A typical loop:

```bash
vim helm/templates/gateway-deployment.yaml
make lint                        # tier 0, instant
make agent-verify                # tier 1, helm upgrade + query (~5s; only the gateway rolls)
make agent-verify THOROUGH=true  # tier 1+, when the change warrants the full suite (~40s)
# ... repeat ...
make agent-down                  # done
```

`agent-verify` falls back signal: a `helm upgrade` that hits an immutable field
fails with `failure_reason=helm_upgrade_failed` — re-run `make agent-up` for a
clean reinstall.

## The agent contract

| | |
| --- | --- |
| **Clean install** | `make agent-up` (`scripts/agent/up.sh`) — fresh `helm install`, drops stale release + PVCs |
| **Fast in-place verify** | `make agent-verify` (`scripts/agent/verify.sh`) — `helm upgrade --install`, reuses release + PVCs |
| **Teardown** | `make agent-down` (`scripts/agent/down.sh`) — delete the cluster |
| **Success** | exit code `0` **and** `status":"success"` in the result JSON |
| **Failure** | non-zero exit code; `failure_reason` names the failing phase |
| **stdout** | exactly one line: the result JSON object |
| **stderr** | all human-readable logs (phase markers, rollout waits, debug dumps) |

An agent should capture and parse stdout, and key its success/failure decision
off the **exit code + `status`** — never off grepping the logs (a transient,
self-healing retry can print `ERROR` to stderr without the run failing).

```bash
result=$(make agent-up 2>/tmp/agent-up.log)   # JSON on stdout, logs in the file
echo "$result" | jq -e '.status == "success"' # decide on the structured result
```

### Result schema (stdout)

```json
{
  "schema_version": "1",
  "status": "success",
  "phase": "query",
  "failure_reason": null,
  "verify_mode": "fast",
  "cluster": "firebolt-instance-helm",
  "namespace": "firebolt",
  "release": "firebolt",
  "engine": "default",
  "gateway_service": "firebolt-gateway",
  "exit_code": 0
}
```

On failure, `status` is `"failure"`, `phase` is the step that failed, and
`failure_reason` is one of the tokens below. `exit_code` mirrors the process
exit code.

| `phase` / `failure_reason` | Meaning | Where to look |
| --- | --- | --- |
| `cluster` / `cluster_setup_failed` | kind cluster create/reuse failed | stderr: kind output; is Docker up, `memlock` raised, kind ≥ v0.31? |
| `floci` / `floci_not_ready` | floci emulator or the bucket Job did not become ready in 120s | stderr: floci pod/Job state |
| `install` / `helm_install_failed` | `helm install` rejected the release (`agent-up`) | stderr: helm error + namespace debug dump |
| `upgrade` / `helm_upgrade_failed` | `helm upgrade` rejected the change (`agent-verify`); often an immutable field — retry with `make agent-up` | stderr: helm error + namespace debug dump |
| `rollout` / `rollout_timeout` | a workload did not roll out in time (engine budget is 900s for its multi-GB first pull) | stderr: per-pod describe + logs + events |
| `query` / `query_failed` | the instance rolled out but `SELECT 1` never returned through the gateway | stderr: last query output + namespace debug |
| `helm_test` / `helm_test_failed` | `THOROUGH=true` only: a chart test hook failed after the query passed | stderr: `helm test --logs` output + namespace debug |

Every wait has a bounded timeout, so a failure surfaces as a structured error
rather than a silent hang.

## Prerequisites

- **Docker** running, with the `memlock` ulimit unlimited (the engine's
  `io_uring` needs it). Docker Desktop is unlimited by default; on Linux add
  `{"default-ulimits":{"memlock":{"Name":"memlock","Hard":-1,"Soft":-1}}}` to
  `/etc/docker/daemon.json` and restart Docker.
- **kind ≥ v0.31** (boots the pinned Kubernetes 1.35 node image).
- **kubectl** and **helm** (v3) on `PATH`.
- **No registry auth or `docker login`** — the `ghcr.io/firebolt-db` engine and
  metadata images are public, so `GHCR_PACKAGES_PUBLIC` defaults to `true` and
  the kind nodes pull them directly. (Override to `false` only to exercise the
  private-package path through the local registry; see the root `AGENTS.md`.)

## Inputs (environment overrides)

All optional; the defaults match a clean local run.

| Variable | Default | Effect |
| --- | --- | --- |
| `OUTPUT` | `json` | `json` (result on stdout, logs on stderr) or `text` (everything on stdout, like `make helm-test`) |
| `THOROUGH` | `false` | `true` also runs the chart's full `helm test` suite after the smoke query (`agent-up` and `agent-verify`) |
| `KIND_CLUSTER` | `firebolt-instance-helm` | kind cluster name (create/reuse/delete) |
| `NAMESPACE` | `firebolt` | target namespace |
| `RELEASE` | `firebolt` | helm release name |
| `ENGINE_NAME` | `default` | engine the smoke query targets |
| `CHART_DIR` | `./helm` | chart directory to install |
| `NODE_IMAGE` | pinned in the `Makefile` | kind node image / Kubernetes version |
| `REMOVE_REGISTRY` | `false` | `agent-down` only: also drop the local registry container |

## How it relates to CI

`agent-up`, `agent-verify`, and the PR gate (`make helm-test`, run by
`.github/workflows/helm-test.yaml`) share one deploy/rollout/query
implementation — `deploy_and_verify` in `scripts/lib/deploy.sh` (which
lives under `scripts/lib/`, not `scripts/ci/`, precisely because both CI and the
agent path use it). `agent-up`/`agent-verify` add the cluster bootstrap and the
JSON output layer; `helm-test.sh` adds human framing and cleanup. The only
behavioral difference between the agent entrypoints is the install strategy
(`agent-up` clean-installs, `agent-verify` upgrades in place), passed as one
argument to the same function — so none of these paths can drift apart.
