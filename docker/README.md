# OpenNebula Front-end (Community-maintained)

> ## ⚠️ Disclaimer
>
> **This is not an official OpenNebula Systems product and it is not covered by
> OpenNebula support.**
>
> This image is maintained by the community, on a best-effort basis. Issues,
> questions and fixes are handled by community contributors, **not** by
> OpenNebula Systems. Do not open support tickets for it, and do not expect
> commercial SLAs, security advisories or guaranteed release cadence.
>
> If you need a supported deployment, use the official installation methods
> documented at https://docs.opennebula.io.
>
> Use at your own risk. Review the image before running it in production.

A containerized **OpenNebula Front-end**, designed to run on Kubernetes with
hypervisor nodes attached externally.

## What this image is

- A **front-end only**: `oned`, FireEdge, OneFlow, OneGate, OneKS and the
  scheduler.
- Ships **OneForm** (`oneprovision`, `oneprovider`) so you can provision remote
  hosts, and **OneKS** to deploy Kubernetes clusters on them.
- Uses **SQLite** by default, exactly like a stock OpenNebula front-end. No
  external database is required.

## What this image is NOT

- **It is not a hypervisor node.** There is no `libvirt` and no `qemu` inside,
  and no host is registered on startup. Virtual machines cannot run in this
  container by design; they run on the external nodes you attach.

## Quick start

```bash
docker run -d --name opennebula \
  -p 2616:2616 -p 2633:2633 \
  -v one-data:/var/lib/one \
  opennebula/opennebula:latest
```

FireEdge is then available on port 2616. The default `oneadmin` password is
`opennebula`; override it with `ONEADMIN_PASSWORD`.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `ONEADMIN_PASSWORD` | `opennebula` | Password for `oneadmin` and `serveradmin` |
| `DB_BACKEND` | `sqlite` | `sqlite` or `mysql` |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | | Only for `mysql` |
| `DB_WAIT_TIMEOUT` | `120` | Seconds to wait for the database before failing |
| `AUTO_UPDATE_ADDONS` | `yes` | Update OneForm/OneKS to the latest patch of the built series on start |
| `OPENNEBULA_HOSTNAME` | | Address advertised to hypervisor nodes |
| `OPENNEBULA_MONITOR_ADDRESS` | | Where hypervisors send monitoring data |

State lives in `/var/lib/one`; mount it on a volume to survive restarts.

## Logging

All services log to the container's stdout, so `docker logs` and
`kubectl logs` show the real errors, including `oned`'s own log.

## Helm chart

A matching Helm chart is available at
https://github.com/pablodelarco/opennebula-helm
