# 0.8.1

fix: invoke engine via 'firebolt server' with FIREBOLT_CORE_MODE (FB-1088) (#56)

# 0.8.0

feat: use YAML format for engine configuration and switch to new structure (FB-959) (#55)

# 0.7.0

feat(gateway): support X-Firebolt-Drained and expose envoy per_connection_buffer_limit_bytes (FB-849) (#54)

# 0.6.0

feat: enable AWS IRSA by default (FB-875) (#53)

# 0.5.15

chore: use latest version of engine/metadata images (FB-908) (#52)

# 0.5.14

chore: agentify repo (FB-923) (#51)

# 0.5.13

fix: allow overriding engine config fields at root (FB-902) (#50)

# 0.5.12

chore: make gateway.podTemplate fields explicit (FB-890) (#49)

# 0.5.11

chore: document deployment divergence (FB-889) (#48)

# 0.5.10

fix: terminationGracePeriod and preStop (FB-888) (#47)

# 0.5.9

fix: add gateway pdb (FB-887) (#46)

# 0.5.8

fix: add startupProbe (FB-886) (#45)

# 0.5.7

chore: add podSecurityContext configuration option (FB-884) (#44)

# 0.5.6

chore: adjust terminationGracePeriod (FB-883) (#43)

# 0.5.5

fix: use UID/GID 3473 to match current Docker image (FB-873) (#42)

# 0.5.4

chore: bump versions (FB-858) (#39)

# 0.5.3

fix: rename customNodeConfig -> customEngineConfig (FB-866) (#41)

# 0.5.2

chore: change default registry (FB-865) (#40)

# 0.5.1

chore: bump AppVersion and remove obsolete init container (FB-858) (#37)

# 0.5.0

feat(o11y): add pod monitor for envoy gateway (FB-855) (#36)

# 0.4.2

fix: disallow 2 metadata service instances running at the same time (FB-828) (#35)

# 0.4.1

fix(metadata): set default_account_id in pensieve_lite config (FB-769) (#31)

# 0.4.0

feat: implement helm tests (FB-719) (#28)

# 0.3.4

fix(postgres): change labeling to allow upgrade (FB-740) (#27)

# 0.3.3

chore(envoy): bump to v1.37.2 (FB-720) (#26)

# 0.3.2

fix(helm): align gateway and engine config with operator (FB-661) (#23)

# 0.3.1

fix: health checks for envoy (FB-557) (#22)

# 0.3.0

feat: replace Core Gateway with Envoy (FB-557) (#21)

# 0.2.1

chore: remove bitnami exceptions (FB-571) (#19)

# 0.2.0

feat: create docs generation workflow (FB-672) (#17)

