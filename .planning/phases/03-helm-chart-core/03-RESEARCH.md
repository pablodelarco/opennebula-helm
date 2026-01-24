# Phase 3: Helm Chart Core - Research

**Researched:** 2026-01-24
**Domain:** Helm chart development, Kubernetes StatefulSet, subchart dependencies
**Confidence:** HIGH

## Summary

This research covers best practices for creating a production-ready Helm chart that deploys OpenNebula on Kubernetes. The chart will use a StatefulSet for oned with persistent storage, integrate Bitnami MariaDB as a subchart dependency, manage SSH keys via Kubernetes secrets, and expose FireEdge via Ingress.

Key findings:
1. Helm chart structure follows well-established conventions from `helm create` with templates for StatefulSet, ConfigMaps, Secrets, and Ingress
2. Bitnami MariaDB is the standard subchart for database dependencies, though there are licensing changes (August 2025) that may require monitoring
3. Secret generation for passwords and SSH keys requires the `lookup` function pattern to persist across upgrades
4. Chart publishing can use either GitHub Pages (traditional) or GHCR OCI registry (modern approach)

**Primary recommendation:** Use standard Helm patterns with `helm create` scaffold, Bitnami MariaDB subchart, StatefulSet with volumeClaimTemplates for oned, lookup function for credential persistence, and GitHub Pages for chart hosting with GHCR OCI as optional modern alternative.

## Standard Stack

The established libraries/tools for Helm chart development:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Helm | 3.17+ | Package manager | Industry standard for K8s deployments |
| Bitnami MariaDB | 14.x | Database subchart | Most widely used MySQL-compatible subchart |
| Kubernetes API | networking.k8s.io/v1 | Ingress | Current stable Ingress API version |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| chart-releaser-action | v1.7.0 | GitHub Actions release | Automated chart publishing |
| helm-oci-chart-releaser | latest | OCI registry push | Publishing to GHCR |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bitnami MariaDB | MariaDB Operator | Operator is more complex but future-proof; Bitnami is simpler but has licensing changes |
| GitHub Pages | GHCR OCI only | OCI is modern but GitHub Pages has better tooling and discoverability |
| StatefulSet | Deployment + PVC | Deployment cannot use volumeClaimTemplates; StatefulSet is correct for stateful apps |

**Chart Dependencies (Chart.yaml):**
```yaml
dependencies:
  - name: mariadb
    version: "~14.0"
    repository: "oci://registry-1.docker.io/bitnamicharts"
    condition: mariadb.enabled
```

## Architecture Patterns

### Recommended Chart Structure
```
opennebula/
├── .helmignore                    # Patterns to ignore when packaging
├── Chart.yaml                     # Chart metadata and dependencies
├── values.yaml                    # Default configuration values
├── charts/                        # Subchart dependencies (populated by helm dep update)
└── templates/
    ├── NOTES.txt                  # Post-install help text
    ├── _helpers.tpl               # Template helper functions
    ├── statefulset.yaml           # oned StatefulSet
    ├── service.yaml               # ClusterIP service for oned
    ├── service-fireedge.yaml      # Service for FireEdge UI
    ├── configmap.yaml             # OpenNebula config files
    ├── secret.yaml                # Passwords and SSH keys
    ├── ingress.yaml               # Optional Ingress for FireEdge
    ├── serviceaccount.yaml        # Optional ServiceAccount
    └── tests/
        └── test-connection.yaml   # Helm test for connectivity
```

### Pattern 1: StatefulSet with volumeClaimTemplates
**What:** StatefulSet manages pods with stable network identity and persistent storage
**When to use:** Any stateful application like oned that needs data persistence
**Example:**
```yaml
# Source: Kubernetes StatefulSet documentation, Elastic Helm charts
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "opennebula.fullname" . }}
  labels:
    {{- include "opennebula.labels" . | nindent 4 }}
spec:
  serviceName: {{ include "opennebula.fullname" . }}
  replicas: 1
  selector:
    matchLabels:
      {{- include "opennebula.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "opennebula.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: opennebula
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          volumeMounts:
            - name: data
              mountPath: /var/lib/one
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        {{- if .Values.persistence.storageClass }}
        storageClassName: {{ .Values.persistence.storageClass | quote }}
        {{- end }}
        resources:
          requests:
            storage: {{ .Values.persistence.size | default "20Gi" }}
```

### Pattern 2: Secret Generation with Lookup Function
**What:** Generate passwords once and persist across Helm upgrades
**When to use:** Any auto-generated credentials (admin password, SSH keys)
**Example:**
```yaml
# Source: Helm community best practices for secret generation
{{- $secretName := printf "%s-credentials" (include "opennebula.fullname" .) }}
{{- $existingSecret := (lookup "v1" "Secret" .Release.Namespace $secretName) }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ $secretName }}
  annotations:
    "helm.sh/resource-policy": keep
type: Opaque
data:
  {{- if $existingSecret }}
  # Reuse existing secret values on upgrade
  oneadmin-password: {{ index $existingSecret.data "oneadmin-password" }}
  {{- else if .Values.auth.oneadminPassword }}
  # Use user-provided password
  oneadmin-password: {{ .Values.auth.oneadminPassword | b64enc | quote }}
  {{- else }}
  # Generate new random password
  oneadmin-password: {{ randAlphaNum 16 | b64enc | quote }}
  {{- end }}
```

### Pattern 3: SSH Key Secret Management
**What:** Store SSH keys in Kubernetes secrets, mount into container
**When to use:** When SSH keys must persist across pod restarts
**Example:**
```yaml
# Source: Kubernetes secrets best practices
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "opennebula.fullname" . }}-ssh
  annotations:
    "helm.sh/resource-policy": keep
type: Opaque
data:
  {{- $sshSecret := (lookup "v1" "Secret" .Release.Namespace (printf "%s-ssh" (include "opennebula.fullname" .))) }}
  {{- if $sshSecret }}
  id_rsa: {{ index $sshSecret.data "id_rsa" }}
  id_rsa.pub: {{ index $sshSecret.data "id_rsa.pub" }}
  {{- else if and .Values.ssh.privateKey .Values.ssh.publicKey }}
  id_rsa: {{ .Values.ssh.privateKey | b64enc | quote }}
  id_rsa.pub: {{ .Values.ssh.publicKey | b64enc | quote }}
  {{- else }}
  # Keys will be generated by entrypoint if not provided
  # Store empty placeholders - entrypoint handles generation
  {{- end }}
```

### Pattern 4: Bitnami Subchart Integration
**What:** Use Bitnami MariaDB as dependency with parent chart overrides
**When to use:** When deploying MariaDB alongside the main application
**Example (values.yaml):**
```yaml
# Source: Bitnami MariaDB chart documentation
mariadb:
  enabled: true
  architecture: standalone
  auth:
    database: opennebula
    username: oneadmin
    # Password auto-generated if not set, uses existingSecret pattern
  primary:
    persistence:
      enabled: true
      size: 8Gi
```

### Pattern 5: ConfigMap for Application Config
**What:** Store configuration files in ConfigMaps, mount as volumes
**When to use:** Configuration that may need updates without image rebuild
**Example:**
```yaml
# Source: Helm best practices documentation
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "opennebula.fullname" . }}-config
data:
  oned.conf: |
    PORT = 2633
    LISTEN_ADDRESS = "0.0.0.0"
    DB = [ BACKEND = "mysql",
           SERVER  = "{{ include "opennebula.mariadb.host" . }}",
           PORT    = 3306,
           USER    = "{{ .Values.mariadb.auth.username }}",
           PASSWD  = "{{ include "opennebula.mariadb.password" . }}",
           DB_NAME = "{{ .Values.mariadb.auth.database }}" ]
```

### Anti-Patterns to Avoid
- **Using Deployment for stateful apps:** StatefulSet is required for apps needing stable identity and persistent storage. Deployment + PVC is a common anti-pattern that breaks on pod reschedule.
- **Regenerating secrets on upgrade:** Using `randAlphaNum` without `lookup` causes password changes on every `helm upgrade`, breaking authentication.
- **Hardcoding image tags:** Always parameterize in values.yaml for customization.
- **Using `latest` image tag:** Use fixed version tags (e.g., `7.0.0`) for reproducibility.
- **Deeply nested values.yaml:** Prefer flat structure to avoid complex existence checks in templates.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MySQL database | Deploy standalone MySQL | Bitnami MariaDB subchart | Handles backup, HA, persistence, credentials properly |
| Secret persistence | Custom ConfigMap + Job | `lookup` function + `helm.sh/resource-policy: keep` | Standard Helm pattern, works reliably |
| Chart publishing | Manual packaging and hosting | chart-releaser-action | Automated releases, index.yaml management |
| Random password | Custom init container | `randAlphaNum` + `lookup` pattern | Built into Helm, well-tested |
| Health checks | Custom sidecar | Native K8s probes (exec/http) | Built-in restart behavior, standard observability |

**Key insight:** Helm and Kubernetes provide sophisticated primitives for stateful applications. The complexity is in knowing the patterns, not building custom solutions.

## Common Pitfalls

### Pitfall 1: VolumeClaimTemplates are Immutable
**What goes wrong:** Attempting to change storage size/class in volumeClaimTemplates fails on upgrade
**Why it happens:** Kubernetes does not allow modification of volumeClaimTemplates after StatefulSet creation
**How to avoid:** Plan storage size carefully upfront; use PVC expansion if storage class supports it
**Warning signs:** Helm upgrade fails with "volumeClaimTemplates is immutable"

### Pitfall 2: Selector Labels Must Be Immutable
**What goes wrong:** Changing selector labels breaks pod matching
**Why it happens:** StatefulSet selectors cannot be changed after creation
**How to avoid:** Use only stable labels in selectors (app.kubernetes.io/name, app.kubernetes.io/instance)
**Warning signs:** Pods not managed by StatefulSet, orphaned pods

### Pitfall 3: Random Secrets Change on Upgrade
**What goes wrong:** Auto-generated passwords regenerate on every `helm upgrade`
**Why it happens:** Template functions like `randAlphaNum` execute fresh each time
**How to avoid:** Use the `lookup` function to check for existing secrets first
**Warning signs:** Authentication failures after helm upgrade, database connection errors

### Pitfall 4: Subchart Values Not Passed Correctly
**What goes wrong:** MariaDB doesn't pick up parent chart configuration
**Why it happens:** Subchart values must be nested under the dependency name key
**How to avoid:** Use `mariadb:` key in values.yaml, not flat structure
**Warning signs:** MariaDB uses default values instead of overrides

### Pitfall 5: Lookup Function Disabled in Dry-Run
**What goes wrong:** `helm template` or `--dry-run` returns empty for lookup
**Why it happens:** Lookup requires cluster connection, disabled by default in dry-run
**How to avoid:** Use `--dry-run=server` for testing with lookup; handle empty lookup results gracefully
**Warning signs:** Template errors or empty values in dry-run output

### Pitfall 6: InitContainer for Database Wait
**What goes wrong:** oned starts before MariaDB is ready, crashes
**Why it happens:** Pod containers start immediately, don't wait for dependencies
**How to avoid:** Use initContainer with wait script or proper startupProbe
**Warning signs:** CrashLoopBackOff, "database connection refused" in logs

## Code Examples

Verified patterns from official sources:

### Standard Labels Helper (_helpers.tpl)
```yaml
# Source: Helm best practices documentation
{{- define "opennebula.labels" -}}
helm.sh/chart: {{ include "opennebula.chart" . }}
{{ include "opennebula.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "opennebula.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opennebula.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "opennebula.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
```

### Exec Liveness Probe for oned
```yaml
# Source: Kubernetes probe documentation
livenessProbe:
  exec:
    command:
      - /bin/bash
      - -c
      - oneuser show 0 > /dev/null 2>&1
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3

readinessProbe:
  exec:
    command:
      - /bin/bash
      - -c
      - oneuser show 0 > /dev/null 2>&1
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

### Ingress Template (networking.k8s.io/v1)
```yaml
# Source: Helm create default template, Kubernetes Ingress documentation
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "opennebula.fullname" . }}
  labels:
    {{- include "opennebula.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.ingress.className }}
  ingressClassName: {{ .Values.ingress.className }}
  {{- end }}
  rules:
    - host: {{ .Values.ingress.hostname | quote }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "opennebula.fullname" . }}-fireedge
                port:
                  number: 2616
{{- end }}
```

### MariaDB Connection Wait InitContainer
```yaml
# Source: Common Kubernetes pattern for dependency waiting
initContainers:
  - name: wait-for-mariadb
    image: busybox:1.36
    command:
      - /bin/sh
      - -c
      - |
        until nc -z {{ include "opennebula.mariadb.host" . }} 3306; do
          echo "Waiting for MariaDB..."
          sleep 5
        done
        echo "MariaDB is ready"
```

### Chart.yaml with Bitnami Dependency
```yaml
# Source: Helm dependency documentation, Bitnami charts
apiVersion: v2
name: opennebula
description: A Helm chart for OpenNebula cloud management platform
type: application
version: 0.1.0
appVersion: "7.0.0"

dependencies:
  - name: mariadb
    version: "~14.0"
    repository: "oci://registry-1.docker.io/bitnamicharts"
    condition: mariadb.enabled
```

### GitHub Actions Workflow for Chart Release
```yaml
# Source: helm/chart-releaser-action documentation
name: Release Charts

on:
  push:
    branches:
      - main
    paths:
      - 'charts/**'

jobs:
  release:
    permissions:
      contents: write
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Configure Git
        run: |
          git config user.name "$GITHUB_ACTOR"
          git config user.email "$GITHUB_ACTOR@users.noreply.github.com"

      - name: Install Helm
        uses: azure/setup-helm@v4

      - name: Add dependency repos
        run: helm repo add bitnami https://charts.bitnami.com/bitnami

      - name: Run chart-releaser
        uses: helm/chart-releaser-action@v1.7.0
        with:
          charts_dir: charts
        env:
          CR_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| extensions/v1beta1 Ingress | networking.k8s.io/v1 Ingress | K8s 1.22 (2021) | Must use current API version |
| Helm 2 with Tiller | Helm 3 (tillerless) | 2019 | Simplified security model |
| http repository | OCI registry | Helm 3.8 (2022) | Can use ghcr.io directly |
| Bitnami Docker Hub | Bitnami OCI registry | 2024 | Use `oci://registry-1.docker.io/bitnamicharts` |
| nginx.ingress.kubernetes.io | Gateway API | 2024+ | Gateway API is future; Ingress still supported |

**Deprecated/outdated:**
- **extensions/v1beta1 Ingress:** Removed in K8s 1.22, use networking.k8s.io/v1
- **Helm 2:** EOL, use Helm 3.x
- **Bitnami charts via helm repo add:** Deprecated August 2025, use OCI format

**Note on Bitnami licensing (August 2025):** Bitnami announced changes to their catalog. Charts remain available as OCI artifacts but no longer receive updates on Docker Hub. The source code remains Apache 2.0 on GitHub. For production, monitor for updates and consider migration path to MariaDB Operator if needed.

## Open Questions

Things that couldn't be fully resolved:

1. **SSH Key Pre-generation vs Container Generation**
   - What we know: Entrypoint currently generates keys if not present; K8s needs them in secrets for persistence
   - What's unclear: Best UX - require user to provide keys, auto-generate in Helm template, or let container generate and manually create secret after first run?
   - Recommendation: Auto-generate in template using `genPrivateKey "rsa"` if available, or document post-install secret creation

2. **FireEdge Session Persistence**
   - What we know: FireEdge stores sessions; unclear if in-memory or filesystem
   - What's unclear: Whether sessions need persistence or if they can be regenerated on restart
   - Recommendation: Research FireEdge session storage; may need additional volume mount

3. **Bitnami Subchart Long-term Viability**
   - What we know: Bitnami announced licensing changes effective August 2025
   - What's unclear: Whether OCI artifacts will continue receiving updates
   - Recommendation: Use Bitnami for v1, document migration path to MariaDB Operator

## Sources

### Primary (HIGH confidence)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/) - Chart structure, templates, values, labels
- [Helm Chart Template Guide](https://helm.sh/docs/chart_template_guide/) - Template functions, lookup
- [Bitnami MariaDB Chart](https://github.com/bitnami/charts/tree/main/bitnami/mariadb) - Subchart configuration
- [Kubernetes StatefulSet Documentation](https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/) - volumeClaimTemplates
- [Kubernetes Probes Documentation](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) - Health checks
- [OpenNebula 7.0 oned Configuration](https://docs.opennebula.io/7.0/product/operation_references/opennebula_services_configuration/oned/) - API configuration

### Secondary (MEDIUM confidence)
- [chart-releaser-action](https://github.com/helm/chart-releaser-action) - GitHub Actions workflow for chart publishing
- [Elastic Helm Charts](https://github.com/elastic/helm-charts) - StatefulSet volumeClaimTemplates patterns
- [Helm Community Secret Patterns](https://blog.cloudcover.ch/posts/reusing-existing-kubernetes-secrets-in-helm-templates/) - Lookup function usage

### Tertiary (LOW confidence)
- Bitnami licensing changes announcement (GitHub issue #35164) - May change; monitor

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Helm, Bitnami MariaDB, and patterns are well-documented
- Architecture: HIGH - StatefulSet, volumeClaimTemplates, and Ingress patterns are standard
- Pitfalls: HIGH - Common issues are well-documented in Helm and K8s communities
- Chart publishing: HIGH - chart-releaser-action is official Helm project

**Research date:** 2026-01-24
**Valid until:** 2026-02-24 (30 days - Helm ecosystem is stable)
