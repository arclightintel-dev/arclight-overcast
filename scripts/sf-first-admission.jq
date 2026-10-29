# ShuttleForge first-admission allowance: SF-only and temporary (DR-18).
#
# Input: the ShuttleForge /ready/detail body. Used by deploy-service.yml and by hand (G4) only
# when /ready answered 200 with status "degraded". An empty-inventory ShuttleForge reports
# "degraded" by design (V1-AC-032; owner C7 ruling 2026-10-29, SF PR #34 a3a5da8), and
# TESTING_PROTOCOLS section 3 (Complex PR #20) allows deploy verification to read SF's
# unauthenticated /ready/detail.
#
# Passes only when: status is "degraded"; the check names are exactly the expected set, each
# once; every check is "ok" except snapshot, which is "warn" with exactly the empty-inventory
# detail. jwks must be "ok" like the rest. Anything else (an unknown or missing check, any other
# non-ok check, a changed detail string, a missing field) fails. Build identity is the ECS image
# digest, checked separately.
#
# Remove this file and its use in deploy-service.yml once provider inventory exists: plain
# /ready "ready" is the gate after that.

# Pinned check set. Currently SF's r4 set (13 checks, relayed by Complex 2026-10-29); replace
# it with SF's r5 set, from SF's verbatim r5 capture, before G4. A stale set fails closed.
def expected:
  ["background_workers", "database", "dataplane_auth", "health_checker", "hmac_key", "jwks",
   "kek_ring", "lease_recording", "lease_store", "policy_engine", "provider_validation",
   "proxy_engine", "snapshot"];

def names: [.checks[].name];

.status == "degraded"
and (names | length) == (names | unique | length)
and (names | sort) == (expected | sort)
and all(.checks[];
  if .name == "snapshot"
  then .status == "warn" and .detail == "snapshot has no usable config or endpoint inventory"
  else .status == "ok"
  end)
