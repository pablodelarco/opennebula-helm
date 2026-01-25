# OpenNebula Host Provisioner
# Lightweight Alpine-based image with Ansible for provisioning hypervisor nodes
#
# This image is used by the Helm chart to automatically:
# - Install OpenNebula node packages on hypervisor hosts
# - Configure SSH keys for front-end communication
# - Set up virtual networks and datastores
# - Register hosts with the OpenNebula front-end

FROM alpine:3.20

LABEL org.opencontainers.image.title="OpenNebula Host Provisioner"
LABEL org.opencontainers.image.description="Ansible-based provisioner for OpenNebula hypervisor nodes"
LABEL org.opencontainers.image.source="https://github.com/pablodelarco/opennebula-helm"

# Install Ansible and dependencies
RUN apk add --no-cache \
    ansible-core \
    openssh-client \
    python3 \
    py3-pip \
    py3-jmespath \
    py3-netaddr \
    bash \
    curl \
    jq \
    && rm -rf /var/cache/apk/*

# Install required Ansible collections
RUN ansible-galaxy collection install \
    community.general \
    ansible.posix

# Create working directory
WORKDIR /ansible

# Copy playbooks and roles
COPY playbook.yml /ansible/
COPY roles/ /ansible/roles/
COPY scripts/ /ansible/scripts/

# Make scripts executable
RUN chmod +x /ansible/scripts/*.sh

# Default entrypoint runs the provisioner script
ENTRYPOINT ["/ansible/scripts/provision.sh"]
