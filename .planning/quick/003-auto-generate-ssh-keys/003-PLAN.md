---
phase: quick
plan: 003
type: execute
wave: 1
depends_on: []
files_modified:
  - charts/opennebula/templates/job-ssh-keygen.yaml
  - charts/opennebula/templates/secret-ssh.yaml
  - charts/opennebula/templates/statefulset.yaml
  - charts/opennebula/templates/job-host-provisioner.yaml
  - charts/opennebula/values.yaml
autonomous: true

must_haves:
  truths:
    - "When onedeploy.enabled=true and no SSH keys provided, keys are auto-generated"
    - "Frontend can SSH to hypervisors using generated keys"
    - "Provisioner can SSH to hypervisors using same generated keys"
    - "Manual SSH key configuration still works when provided"
  artifacts:
    - path: "charts/opennebula/templates/job-ssh-keygen.yaml"
      provides: "Pre-install hook Job that generates SSH key pair"
    - path: "charts/opennebula/templates/secret-ssh.yaml"
      provides: "Unified SSH secret for frontend and provisioner"
    - path: "charts/opennebula/values.yaml"
      provides: "ssh.autoGenerate configuration option"
  key_links:
    - from: "job-ssh-keygen.yaml"
      to: "secret-ssh.yaml"
      via: "kubectl create secret"
      pattern: "kubectl create secret"
    - from: "statefulset.yaml"
      to: "secret-ssh.yaml"
      via: "volume mount"
      pattern: "secretName.*ssh"
    - from: "job-host-provisioner.yaml"
      to: "secret-ssh.yaml"
      via: "volume mount"
      pattern: "secretName.*ssh"
---

<objective>
Implement automatic SSH key generation for the OpenNebula Helm chart.

Purpose: Eliminate manual SSH key configuration when using onedeploy - users should be able to deploy with zero SSH setup.
Output: Pre-install hook Job generates keys, stores in Secret, both frontend and provisioner use shared secret.
</objective>

<context>
@charts/opennebula/values.yaml
@charts/opennebula/templates/statefulset.yaml
@charts/opennebula/templates/job-host-provisioner.yaml
@charts/opennebula/templates/secret-provisioner-ssh.yaml
@charts/opennebula/templates/secret.yaml
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add ssh.autoGenerate option to values.yaml</name>
  <files>charts/opennebula/values.yaml</files>
  <action>
Update the `ssh:` section in values.yaml to add autoGenerate option:

```yaml
## SSH keys for hypervisor communication
ssh:
  ## Auto-generate SSH keys when onedeploy is enabled
  ## Set to false to disable auto-generation (requires manual key config)
  autoGenerate: true

  ## Provide existing keys (base64 encoded) - overrides autoGenerate
  # privateKey: ""
  # publicKey: ""
```

The logic will be:
- If ssh.privateKey is provided, use it (existing behavior)
- Else if onedeploy.enabled and ssh.autoGenerate=true, generate keys
- Else no SSH keys (existing behavior for non-onedeploy setups)
  </action>
  <verify>helm template charts/opennebula --set onedeploy.enabled=true | grep -i "autoGenerate" || echo "Value exists in values.yaml"</verify>
  <done>values.yaml has ssh.autoGenerate: true default</done>
</task>

<task type="auto">
  <name>Task 2: Create pre-install hook Job for SSH key generation</name>
  <files>charts/opennebula/templates/job-ssh-keygen.yaml</files>
  <action>
Create a new file `charts/opennebula/templates/job-ssh-keygen.yaml`:

The Job should:
1. Only render when: onedeploy.enabled=true AND ssh.autoGenerate=true AND NOT (ssh.privateKey or onedeploy.provisioner.ssh.privateKey or onedeploy.provisioner.ssh.existingSecret)
2. Use helm.sh/hook: pre-install (run before main resources)
3. Use helm.sh/hook-weight: "-5" (run early)
4. Use helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
5. Use a ServiceAccount with RBAC to create secrets

The Job container:
- Image: bitnami/kubectl:latest (has kubectl and can generate keys)
- Command: Generate ed25519 key pair, create Kubernetes secret with id_rsa and id_rsa.pub keys
- Secret name: {{ include "opennebula.fullname" . }}-ssh-generated

RBAC needed:
- ServiceAccount for the job
- Role with create/get permissions on secrets
- RoleBinding

Key generation script:
```bash
#!/bin/bash
set -e
# Generate SSH key pair
ssh-keygen -t ed25519 -f /tmp/id_rsa -N "" -C "oneadmin@opennebula"

# Create or update the secret
kubectl create secret generic RELEASE-ssh-generated \
  --from-file=id_rsa=/tmp/id_rsa \
  --from-file=id_rsa.pub=/tmp/id_rsa.pub \
  --dry-run=client -o yaml | kubectl apply -f -
```
  </action>
  <verify>helm template charts/opennebula --set onedeploy.enabled=true | grep -A 50 "kind: Job" | grep "ssh-keygen"</verify>
  <done>Pre-install hook Job renders when onedeploy.enabled=true and no manual keys provided</done>
</task>

<task type="auto">
  <name>Task 3: Update secret-provisioner-ssh.yaml to handle auto-generated keys</name>
  <files>charts/opennebula/templates/secret-provisioner-ssh.yaml</files>
  <action>
Modify the secret-provisioner-ssh.yaml to NOT render when auto-generate is active.

The conditional should be:
- Render ONLY when: onedeploy.enabled=true AND provisioner.ssh.privateKey is provided AND NOT existingSecret

Add a comment explaining that when ssh.autoGenerate=true, the ssh-keygen job creates the secret instead.

This prevents duplicate secrets and ensures the generated secret is used.
  </action>
  <verify>helm template charts/opennebula --set onedeploy.enabled=true | grep -c "provisioner-ssh" || echo "0 matches expected"</verify>
  <done>Provisioner SSH secret only renders when manual key is provided</done>
</task>

<task type="auto">
  <name>Task 4: Update statefulset.yaml to use generated SSH secret</name>
  <files>charts/opennebula/templates/statefulset.yaml</files>
  <action>
Update the volume mount logic for ssh-keys in statefulset.yaml:

Current condition (lines 121-125, 146-155):
```yaml
{{- if or (and .Values.ssh (or .Values.ssh.privateKey .Values.ssh.publicKey)) (and .Values.onedeploy.enabled .Values.onedeploy.provisioner.ssh.privateKey) }}
```

New condition should be:
```yaml
{{- $hasManualSSH := or (and .Values.ssh (or .Values.ssh.privateKey .Values.ssh.publicKey)) (and .Values.onedeploy.enabled .Values.onedeploy.provisioner.ssh.privateKey) }}
{{- $hasAutoSSH := and .Values.onedeploy.enabled (default true .Values.ssh.autoGenerate) (not .Values.onedeploy.provisioner.ssh.existingSecret) (not .Values.onedeploy.provisioner.ssh.privateKey) }}
{{- if or $hasManualSSH $hasAutoSSH }}
```

For the secret name selection:
- If manual keys provided: use existing logic
- If auto-generated: use `{{ include "opennebula.fullname" . }}-ssh-generated`

Update both the volumeMounts section (around line 121) and the volumes section (around line 146).
  </action>
  <verify>helm template charts/opennebula --set onedeploy.enabled=true | grep -A 5 "ssh-keys"</verify>
  <done>Frontend mounts auto-generated SSH secret when onedeploy enabled</done>
</task>

<task type="auto">
  <name>Task 5: Update job-host-provisioner.yaml to use generated SSH secret</name>
  <files>charts/opennebula/templates/job-host-provisioner.yaml</files>
  <action>
Update the provisioner job to use the auto-generated secret when no manual keys provided.

Current logic (lines 67-73, 82-87):
```yaml
{{- if .Values.onedeploy.provisioner.ssh.existingSecret }}
secretName: {{ .Values.onedeploy.provisioner.ssh.existingSecret }}
{{- else }}
secretName: {{ include "opennebula.fullname" . }}-provisioner-ssh
{{- end }}
```

New logic should be:
```yaml
{{- if .Values.onedeploy.provisioner.ssh.existingSecret }}
secretName: {{ .Values.onedeploy.provisioner.ssh.existingSecret }}
{{- else if .Values.onedeploy.provisioner.ssh.privateKey }}
secretName: {{ include "opennebula.fullname" . }}-provisioner-ssh
{{- else }}
secretName: {{ include "opennebula.fullname" . }}-ssh-generated
{{- end }}
```

Apply this to both volume references (ssh-key and oneadmin-pubkey volumes).
  </action>
  <verify>helm template charts/opennebula --set onedeploy.enabled=true --set 'onedeploy.node.hosts.test.ansible_host=1.2.3.4' | grep "ssh-generated"</verify>
  <done>Provisioner uses auto-generated SSH secret when no manual keys provided</done>
</task>

</tasks>

<verification>
Run helm template with onedeploy enabled and verify:
1. Pre-install hook Job for ssh-keygen is rendered
2. No provisioner-ssh secret is rendered (it comes from the Job)
3. StatefulSet references ssh-generated secret
4. Provisioner Job references ssh-generated secret

Commands:
```bash
# Test auto-generate flow (no manual keys)
helm template test charts/opennebula --set onedeploy.enabled=true --set 'onedeploy.node.hosts.test.ansible_host=1.2.3.4' > /tmp/auto.yaml
grep -c "ssh-keygen" /tmp/auto.yaml  # Should find the keygen job
grep "ssh-generated" /tmp/auto.yaml  # Should find references

# Test manual key flow (should skip keygen)
helm template test charts/opennebula --set onedeploy.enabled=true --set 'onedeploy.node.hosts.test.ansible_host=1.2.3.4' --set onedeploy.provisioner.ssh.privateKey="dGVzdA==" > /tmp/manual.yaml
grep -c "ssh-keygen" /tmp/manual.yaml  # Should NOT find keygen job (or find it not rendered)
grep "provisioner-ssh" /tmp/manual.yaml  # Should find manual secret reference
```
</verification>

<success_criteria>
- helm template with onedeploy.enabled=true and no SSH keys produces ssh-keygen Job
- helm template with onedeploy.enabled=true and manual keys skips ssh-keygen Job
- Frontend and provisioner both reference the same auto-generated secret
- Existing manual SSH key configuration continues to work
- helm lint passes with no errors
</success_criteria>

<output>
After completion, verify with:
```bash
helm lint charts/opennebula
helm template test charts/opennebula --set onedeploy.enabled=true --set 'onedeploy.node.hosts.test.ansible_host=1.2.3.4'
```
</output>
