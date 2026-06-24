# ALB Module
#
# Provisions per D-056 §3:
#   - Public Application Load Balancer in public subnets
#   - HTTPS listener (443) with ACM certificate
#   - HTTP listener (80) redirecting to HTTPS
#   - Host-based routing rules:
#       core.[domain]         → Core target group
#       podbay.[domain]       → Podbay target group
#       shuttleforge.[domain] → ShuttleForge target group (if public)
#   - Target groups with /ready health checks (D-052)
#
# Podbay target group: idle_timeout = 3600s for WebSocket browser streams.
# ALB does NOT handle ShuttleForge dataplane (CONNECT tunnels) — use Cloud Map.
