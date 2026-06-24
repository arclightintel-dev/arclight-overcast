# Route 53 Module
#
# Provisions per D-056 §3:
#   - Public hosted zone for the platform domain
#   - Alias records for ALB (core.[domain], podbay.[domain], shuttleforge.[domain])
#   - Private hosted zone for internal service discovery (*.arclight.local)
#
# DNS delegation: if domain is registered outside Route 53,
# NS records must be added to the registrar manually.
