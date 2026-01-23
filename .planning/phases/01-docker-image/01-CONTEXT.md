# Phase 1: Docker Image - Context

**Gathered:** 2025-01-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Build a Docker image that runs OpenNebula 7.0 control plane services without systemd. Users can pull and run this image locally or use it as the base for Kubernetes deployment (Phase 3). The image contains oned, Sunstone, FireEdge, OneFlow, and OneGate.

</domain>

<decisions>
## Implementation Decisions

### Default behavior
- All services start by default: oned, Sunstone, FireEdge, OneFlow, OneGate
- Services run as `oneadmin` user (OpenNebula standard, matches docs and permissions)
- Include Dockerfile HEALTHCHECK for `docker run` compatibility, plus design for K8s probes in Phase 3

### Claude's Discretion
- **Database backend**: Claude decides default (likely SQLite for easy testing, but designed to accept external DB connection via env vars)
- **Service management**: How services start and stay running (supervisord vs manual starts vs other)
- **Configuration approach**: What env vars to expose beyond database connection
- **Image structure**: Single image with all services (implied by requirements)

</decisions>

<specifics>
## Specific Ideas

- User has existing repo (https://github.com/pablodelarco/docker_opennebula) with OpenNebula 6.10 that works — can use as reference pattern
- Existing approach uses RUNLEVEL=1 during install and manual service starts in entrypoint — this pattern avoids systemd and is proven
- Target OpenNebula 7.0 (not 6.10 LTS) — may have different package/service requirements

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-docker-image*
*Context gathered: 2025-01-23*
