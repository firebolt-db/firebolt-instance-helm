#!/usr/bin/env bash
# Stop admission after endpoint propagation, then wait for active connections.
set -u
admin() {
  local response status
  response=$(
    exec 3<>/dev/tcp/127.0.0.1/{{ .Values.gateway.adminPort }} || exit 1
    printf '%s\r\n' "$1 $2 HTTP/1.1" 'Host: localhost' 'Content-Length: 0' 'Connection: close' '' >&3 || exit 1
    cat <&3
  ) || return 1
  status=${response%%$'\n'*}
  [[ "$status" == HTTP/1.*" 200 "* ]] || return 1
  printf '%s\n' "$response"
}
until admin POST /healthcheck/fail >/dev/null; do sleep 0.1; done
# Readiness is now failing. Keep accepting until the Service has stopped
# routing here; only then close admission. See the propagation note above.
sleep 5
# graceful: in-flight requests finish and their connections close right after
# (drain-time-s is 0). The drain's completion also stops the INBOUND-marked
# listeners, so the query socket refuses new connections while the stats
# listener (not INBOUND) keeps serving probes and metrics. Verified against
# the pinned Envoy: adding skip_exit suppresses that listener stop and the
# socket keeps accepting, and without it the process still survives the
# drain - so skip_exit must stay absent.
until admin POST '/drain_listeners?inboundonly&graceful' >/dev/null; do sleep 0.1; done
while true; do
  if response=$(admin GET '/stats?filter=^http[.]gateway[.]downstream_cx_active$'); then
    if grep -Fxq 'http.gateway.downstream_cx_active: 0' <<<"$response"; then
      exit 0
    fi
    # TLS provisioning can deliberately omit the public listener entirely.
    # Missing statistics alone cannot establish that there are no connections.
    if ! grep -q '^http[.]gateway[.]downstream_cx_active:' <<<"$response"; then
      if listeners=$(admin GET /listeners) && ! grep -q '^listener::' <<<"$listeners"; then
        exit 0
      fi
    fi
  fi
  sleep 0.1
done
