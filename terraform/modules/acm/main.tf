# ACM Certificate Module
#
# Provisions per D-056 §3:
#   - Wildcard ACM certificate for *.[domain]
#   - DNS validation records in Route 53
#   - Auto-renewal (managed by ACM)
#
# The ALB uses this certificate for TLS termination.
