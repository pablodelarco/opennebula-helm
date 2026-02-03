---
phase: quick
plan: 001
type: execute
wave: 1
depends_on: []
files_modified:
  - docker/provisioner/roles/opennebula-register/tasks/main.yml
autonomous: true

must_haves:
  truths:
    - "SSH known_hosts is automatically populated for provisioned hypervisor hosts"
    - "OpenNebula frontend can SSH to hypervisors without manual intervention"
    - "Host monitoring works after provisioning completes"
  artifacts:
    - path: "docker/provisioner/roles/opennebula-register/tasks/main.yml"
      provides: "Automated ssh-keyscan integration"
      contains: "ssh-keyscan"
  key_links:
    - from: "provisioner job"
      to: "opennebula frontend"
      via: "oneadmin SSH key sharing + known_hosts population"
      pattern: "ssh-keyscan.*known_hosts"
---

<objective>
Automate the SSH known_hosts step currently done manually with:
```
kubectl exec opennebula-0 -c opennebula -- su - oneadmin -c \
  "ssh-keyscan -H 192.168.1.57 >> ~/.ssh/known_hosts"
```

Purpose: After the provisioner registers a host with OpenNebula, the frontend needs the host's SSH fingerprint in known_hosts to perform monitoring and VM operations. Currently this requires manual kubectl exec.

Output: Modified provisioner that populates known_hosts via the OpenNebula API (triggering ssh-keyscan on the frontend) or by having the provisioner communicate the host keys back.
</objective>

<execution_context>
@/home/pablo/.claude/get-shit-done/workflows/execute-plan.md
@/home/pablo/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
## Repository Branch Analysis

### main branch (latest: 1a0b0cd)
- Contains the base Helm chart (Phase 1-3 work)
- No host provisioning features
- Published to Helm repo as v0.2.1

### feature/host-provisioning branch (latest: 3a15016)
- 8 commits ahead of main with OneDeploy integration
- Provisioner Job: `job-host-provisioner.yaml` - runs as Helm post-install hook
- Provisioner Image: `docker/provisioner/` - Alpine-based Ansible container
- SSH key sharing: Provisioner and frontend share the same SSH key pair
- Ansible roles:
  - `opennebula-node`: Installs ONE packages on hypervisors, adds oneadmin pubkey
  - `opennebula-network`: Creates virtual networks via XML-RPC API
  - `opennebula-register`: Registers hosts via XML-RPC API, syncs remotes

### gh-pages branch (latest: f22993d)
- Helm repo index only
- Auto-updated by release-chart workflow

## Current Architecture

The provisioner successfully:
1. Waits for OpenNebula API readiness
2. Installs opennebula-node-kvm on hypervisors via Ansible
3. Adds oneadmin's public key to hypervisor authorized_keys
4. Registers hosts with OpenNebula via XML-RPC API
5. Syncs remotes and enables hosts

The problem: After registration, the OpenNebula frontend cannot SSH to the hypervisor because the hypervisor's SSH host key is not in oneadmin's known_hosts.

## Solution Approach

After host registration in `opennebula-register`, add a task to trigger ssh-keyscan on the frontend. Options:

**Option A: API-based (preferred)**
Use `one.host.sync` or a similar API call that triggers the frontend to establish SSH connection and learn the host key.

**Option B: Direct ssh-keyscan via kubectl**
The provisioner could exec into the frontend pod and run ssh-keyscan. Requires service account permissions.

**Option C: ConfigMap/Init approach**
Pre-populate known_hosts via ConfigMap from provisioner output. Complex lifecycle.

Best approach: Option A - leverage the fact that `one.host.sync` already exists and causes the frontend to SSH to the host. If host key checking is set to accept, this would auto-populate known_hosts.

Alternatively, modify the Docker entrypoint to set `StrictHostKeyChecking accept-new` in SSH config.

@docker/provisioner/roles/opennebula-register/tasks/main.yml
@docker/entrypoint.sh
@charts/opennebula/values.yaml
</context>

<tasks>

<task type="auto">
  <name>Task 1: Configure SSH StrictHostKeyChecking in Frontend</name>
  <files>docker/entrypoint.sh</files>
  <action>
Add SSH config for oneadmin that sets StrictHostKeyChecking to "accept-new". This allows new host keys to be automatically added to known_hosts on first connection while still verifying known hosts (safer than "no").

In the SSH Key Setup section of entrypoint.sh, after setting up the SSH keys:

```bash
# Configure SSH to accept new host keys automatically
# This allows oned to connect to newly provisioned hypervisors
cat > /var/lib/one/.ssh/config << 'EOF'
Host *
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
EOF
chown oneadmin:oneadmin /var/lib/one/.ssh/config
chmod 600 /var/lib/one/.ssh/config
```

This is the standard approach for automated OpenNebula deployments where hosts are dynamically provisioned.
  </action>
  <verify>
Rebuild Docker image: `docker build -t pablodelarco/opennebula:test docker/`
Verify config exists: `docker run --rm pablodelarco/opennebula:test cat /var/lib/one/.ssh/config`
  </verify>
  <done>SSH config file created with StrictHostKeyChecking accept-new, owned by oneadmin with 600 permissions</done>
</task>

<task type="auto">
  <name>Task 2: Add Explicit ssh-keyscan in Provisioner After Registration</name>
  <files>docker/provisioner/roles/opennebula-register/tasks/main.yml</files>
  <action>
As a belt-and-suspenders approach, add an explicit task after host registration that performs ssh-keyscan and stores the result. This ensures known_hosts is populated even before the first oned connection attempt.

Add after the "Register hosts with OpenNebula" task:

```yaml
- name: Collect SSH host keys from registered hosts
  ansible.builtin.shell:
    cmd: |
      HOST_IP="{{ hostvars[item]['ansible_host'] }}"
      echo "Scanning SSH host key for ${HOST_IP}..."
      ssh-keyscan -H "${HOST_IP}" 2>/dev/null
    executable: /bin/bash
  loop: "{{ hosts_to_register }}"
  delegate_to: localhost
  register: host_keys_result

- name: Store host keys for frontend consumption
  ansible.builtin.copy:
    content: |
      {% for result in host_keys_result.results %}
      {{ result.stdout }}
      {% endfor %}
    dest: /tmp/known_hosts_additions
  delegate_to: localhost
  when: host_keys_result.results | length > 0
```

Note: The provisioner runs with ANSIBLE_HOST_KEY_CHECKING=False so it can SSH to hosts without known_hosts. The collected keys are for the frontend, not the provisioner.

The keys collected here could be used if we later implement a ConfigMap-based approach to pass them to the frontend. For now, the StrictHostKeyChecking accept-new in Task 1 is the primary solution.
  </action>
  <verify>
Rebuild provisioner image: `docker build -t pablodelarco/opennebula-provisioner:test docker/provisioner/`
Check that ssh-keyscan is available: `docker run --rm pablodelarco/opennebula-provisioner:test which ssh-keyscan`
  </verify>
  <done>Provisioner collects SSH host keys after registration; keys available for optional future ConfigMap integration</done>
</task>

<task type="auto">
  <name>Task 3: Document the Solution and Test End-to-End</name>
  <files>charts/opennebula/values.yaml</files>
  <action>
Add documentation in the values.yaml onedeploy section explaining that SSH known_hosts is automatically handled:

In the `onedeploy:` section comments, add:

```yaml
  ## --------------------------------------------------------
  ## SSH Host Key Handling (automatic)
  ## --------------------------------------------------------
  ## The OpenNebula frontend is configured with StrictHostKeyChecking=accept-new
  ## which automatically adds new hypervisor host keys to known_hosts on first
  ## connection. This eliminates the need for manual ssh-keyscan.
  ##
  ## For additional security, you can pre-populate known_hosts by providing
  ## the host keys in a ConfigMap (advanced use case, not required for most deployments).
```

This documents the solution for users and explains why no manual intervention is needed.
  </action>
  <verify>
Read the updated values.yaml and confirm documentation is clear and accurate.
  </verify>
  <done>Solution documented in values.yaml; users understand that SSH known_hosts is automatic</done>
</task>

</tasks>

<verification>
1. Docker image builds successfully with SSH config
2. Provisioner image has ssh-keyscan capability
3. Documentation is clear about automatic known_hosts handling
4. (Manual test when deploying): Hosts become MONITORED state without manual kubectl exec
</verification>

<success_criteria>
- Frontend Docker image includes SSH config with StrictHostKeyChecking accept-new
- Provisioner collects host SSH keys after registration
- values.yaml documents the automatic SSH known_hosts behavior
- The manual `kubectl exec ... ssh-keyscan` step is no longer required
</success_criteria>

<output>
After completion, create `.planning/quick/001-analyze-branches-test-helm-chart-automat/001-SUMMARY.md`
</output>
