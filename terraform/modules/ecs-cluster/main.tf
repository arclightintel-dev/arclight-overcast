# ECS Cluster Module
#
# Provisions per D-056 §1, §6:
#   - ECS cluster with Container Insights enabled
#   - Fargate capacity provider (for Core, ShuttleForge)
#   - EC2 capacity provider association (for Podbay — provisioned separately)
#   - Cloud Map private DNS namespace (*.arclight.local)
#   - Service Connect defaults
#
# One cluster per environment. Mixed capacity providers:
#   Fargate = stateless services (Core, ShuttleForge)
#   EC2 = host-level needs (Podbay workspaces needing SYS_ADMIN, custom /dev/shm)
