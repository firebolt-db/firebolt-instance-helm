# 0.2.0

feat(helm): align with engine FHS image layout (FB-1733) (#12)

# 0.1.2

fix: collect pod logs after helm test (FB-1643) (#2)

# 0.1.1

chore(deps): bump amazon/aws-cli from 2.35.2 to 2.35.3 (#1)

# Changelog

## [0.4.1](https://github.com/firebolt-db/firebolt-instance-helm/compare/0.4.0...0.4.1) (2026-09-03)


### Dependencies

* **deps:** bump packdb appVersion to release-5.0.0-pre.0.20260831081410.a005be0f9030 ([#90](https://github.com/firebolt-db/firebolt-instance-helm/issues/90)) ([5e25329](https://github.com/firebolt-db/firebolt-instance-helm/commit/5e253297df6a649ed11960aa09930e1402158ab8))

## [0.4.0](https://github.com/firebolt-db/firebolt-instance-helm/compare/0.3.2...0.4.0) (2026-08-29)


### ⚠ BREAKING CHANGES

* **helm:** require lowercase instance.id ULIDs (FB-3520) ([#87](https://github.com/firebolt-db/firebolt-instance-helm/issues/87))
* `customEngineConfig.instance.id` must now match `^[0-7][0-9a-hjkmnp-tv-z]{25}$`, a lowercase Crockford ULID. `values.schema.json` rejects uppercase and any character outside the Crockford alphabet, so `helm upgrade` with an unchanged uppercase id fails validation before anything is applied.
* **Lowercase your existing id as part of this upgrade.** The chart passes `instance.id` straight through to the engine config and to the metadata service `default_account_id`. It does not rewrite case for you.
* Requires an engine and metadata image that accept lowercase ids. This release's `appVersion` is `release-5.0.0-pre.0.20260828194119.d0f954993097`, which does. If you override the image, move it to that build in the same change. A lowercased id against an older metadata image fails account reconciliation at startup, and an uppercase id against this engine image fails YAML parse.
* The shipped default `customEngineConfig.instance.id` is now `01kp98j0000000000000000000`.

### Features

* **helm:** require lowercase instance.id ULIDs (FB-3520) ([#87](https://github.com/firebolt-db/firebolt-instance-helm/issues/87)) ([74e592d](https://github.com/firebolt-db/firebolt-instance-helm/commit/74e592d6cdf4346a7b29f4c187e40e64afde357b))

## [0.3.2](https://github.com/firebolt-db/firebolt-instance-helm/compare/0.3.1...0.3.2) (2026-08-25)


### Dependencies

* **deps:** bump packdb appVersion to release-5.0.0-pre.0.20260822175432.75d37cc26c66 ([#80](https://github.com/firebolt-db/firebolt-instance-helm/issues/80)) ([35293b1](https://github.com/firebolt-db/firebolt-instance-helm/commit/35293b163996a3ad5f1be181b097422e572d4149))

## [0.3.1](https://github.com/firebolt-db/firebolt-instance-helm/compare/0.3.0...0.3.1) (2026-08-17)


### Bug Fixes

* **metadata:** render metadata service config as YAML, not XML (FB-3110) ([#72](https://github.com/firebolt-db/firebolt-instance-helm/issues/72)) ([85995d8](https://github.com/firebolt-db/firebolt-instance-helm/commit/85995d810031f8d813b26a85a941ec779c79b1b9))

## [0.3.0](https://github.com/firebolt-db/firebolt-instance-helm/compare/0.2.0...0.3.0) (2026-07-27)


### ⚠ BREAKING CHANGES

* **storage:** migrate engine storage config to schema (FB-1684) ([#25](https://github.com/firebolt-db/firebolt-instance-helm/issues/25))

### Features

* **helm:** add engine authentication and TLS support (FB-1943) ([#23](https://github.com/firebolt-db/firebolt-instance-helm/issues/23)) ([a9a8aa2](https://github.com/firebolt-db/firebolt-instance-helm/commit/a9a8aa2508c6c3d77e92b33b35104cc010f9f8d8))
* **storage:** migrate engine storage config to schema (FB-1684) ([#25](https://github.com/firebolt-db/firebolt-instance-helm/issues/25)) ([91f1f5d](https://github.com/firebolt-db/firebolt-instance-helm/commit/91f1f5ddde4eea2c0b26efe83dcd02c96dc503ec))


### Bug Fixes

* **agent:** remove floci AWS env credentials (FB-2197) ([#36](https://github.com/firebolt-db/firebolt-instance-helm/issues/36)) ([58b56d3](https://github.com/firebolt-db/firebolt-instance-helm/commit/58b56d3e29facec7f79e7b4fadeb5fe11522730a))
* keep the Core UI sidecar image fresh and probe its readiness (FB-2179, FB-2180) ([#32](https://github.com/firebolt-db/firebolt-instance-helm/issues/32)) ([fb88c96](https://github.com/firebolt-db/firebolt-instance-helm/commit/fb88c9606feaad5dec3d8620913643e9829d3c15))
* **security:** disable service account token automount on postgres and gateway ([#47](https://github.com/firebolt-db/firebolt-instance-helm/issues/47)) ([181ac91](https://github.com/firebolt-db/firebolt-instance-helm/commit/181ac91b439aaa139491db09cfcd6e76cffe02b3))


### Dependencies

* **deps:** bump packdb appVersion to release-5.0.1-0.20260709071413.53735f172429 ([#5](https://github.com/firebolt-db/firebolt-instance-helm/issues/5)) ([76ecd18](https://github.com/firebolt-db/firebolt-instance-helm/commit/76ecd18d1601dbad9f820201f49f63830f4f3466))
* **deps:** bump packdb appVersion to release-5.0.1-0.20260713060957.513515666721 ([#29](https://github.com/firebolt-db/firebolt-instance-helm/issues/29)) ([1dd11b3](https://github.com/firebolt-db/firebolt-instance-helm/commit/1dd11b384083806da59e3590bc4e6ad0d45749a5))
* **deps:** bump packdb appVersion to release-5.0.1-0.20260727005216.d09b51086f14 ([#38](https://github.com/firebolt-db/firebolt-instance-helm/issues/38)) ([69909db](https://github.com/firebolt-db/firebolt-instance-helm/commit/69909dbc1324f64b897f949a5f4682ae46605cb1))

## 0.1.0

Initial public release. Consolidated changes from pre-release development:

* docs: polish AGENTS.md and add helm/CLAUDE.md (FB-1608)
* chore: remove internal AWS account and Linear references (FB-1605)
* docs: update Helm chart documentation (FB-1598)
* revert: rename engine data-dir to /firebolt-data/data (FB-1571)
* feat(gateway,metadata): support custom pod labels and annotations (FB-1553)
* feat(gateway,metadata): broaden pod customization surface (FB-1552)
* feat: rename engine data-dir to /firebolt-data/data
* chore: bump appVersion to release-4.32.0-pre.0.20260609145613.22a1ea4abadb (FB-1574)
* feat(engine): add topologySpreadConstraints support for engines (FB-1551)
* helm: harden engine + pin postgres/utilities by digest (FIR-1454)
* docs: add Mintlify user-facing docs and drop unused make wait (FB-1385)
* chore(helm): plain/dev install split + floci local-dev manifest (FB-1361)
* feat: operator parity iteration 2 — five chart-deliverable gaps (FB-1348)
* feat(helm): add values.schema.json for install-time validation (FB-1284)
* fix(postgres): harden security context and drop subPath mount (FB-1282)
* fix(metadata): harden pod and container security context (FB-1283)
* feat(gateway): per-pod LB, active health checks and retry budget (FB-1279)
* feat(helm): render engine.termination_grace_period in engine config (FB-1280)
* fix(helm): roll engine pods on engine/auth ConfigMap change (FB-1281)
* chore(helm): align engine/metadata image defaults (FB-1299)
* fix(helm): drop securityContextCapabilities value, hardcode capabilities.drop=ALL (FB-1297)
* fix: disable service-link env injection on every pod (FB-1215)
* chore: bump engine/metadata to 4.32.0-pre.0.20260518071541.b02639bf849c (FB-1215)
* refactor: drop intra-engine peer ports from engine resources (FB-985)
* fix: invoke engine via 'firebolt server' with FIREBOLT_CORE_MODE (FB-1088)
* feat: use YAML format for engine configuration and switch to new structure (FB-959)
* feat(gateway): support X-Firebolt-Drained and expose envoy per_connection_buffer_limit_bytes (FB-849)
* feat: enable AWS IRSA by default (FB-875)
* chore: use latest version of engine/metadata images (FB-908)
* chore: agentify repo (FB-923)
* fix: allow overriding engine config fields at root (FB-902)
* chore: make gateway.podTemplate fields explicit (FB-890)
* chore: document deployment divergence (FB-889)
* fix: terminationGracePeriod and preStop (FB-888)
* fix: add gateway pdb (FB-887)
* fix: add startupProbe (FB-886)
* chore: add podSecurityContext configuration option (FB-884)
* chore: adjust terminationGracePeriod (FB-883)
* fix: use UID/GID 3473 to match current Docker image (FB-873)
* chore: bump versions (FB-858)
* fix: rename customNodeConfig -> customEngineConfig (FB-866)
* chore: change default registry (FB-865)
* chore: bump AppVersion and remove obsolete init container (FB-858)
* feat(o11y): add pod monitor for envoy gateway (FB-855)
* fix: disallow 2 metadata service instances running at the same time (FB-828)
* fix(metadata): set default_account_id in pensieve_lite config (FB-769)
* feat: implement helm tests (FB-719)
* fix(postgres): change labeling to allow upgrade (FB-740)
* chore(envoy): bump to v1.37.2 (FB-720)
* fix(helm): align gateway and engine config with operator (FB-661)
* fix: health checks for envoy (FB-557)
* feat: replace Core Gateway with Envoy (FB-557)
* chore: remove bitnami exceptions (FB-571)
* feat: create docs generation workflow (FB-672)
