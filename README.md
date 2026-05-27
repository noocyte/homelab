# Infrastructure as Code (IaC) & GitOps Cluster

This repository contains the automation playbooks to bootstrap our core Docker/Portainer engine (Layer 1) alongside the Docker Compose configurations for our functional applications (Layer 2).

---

## Layer 1: Host Bootstrapping (Ansible)

The `ansible/` directory handles configuring a fresh Linux host, installing Docker, and spinning up Portainer.

### 1. Prerequisites & Local Setup
Ensure you have `pipx` installed on your local machine to run Ansible isolated:
```bash
sudo apt install pipx -y && pipx ensurepath
pipx install --include-deps ansible
ansible-galaxy collection install community.docker
```

### 2. Managing Vault Secrets
Secrets are encrypted using AES-256 via Ansible Vault.

To edit existing secrets:

```Bash
ansible-vault edit ansible/group_vars/all/vault.yml
```
Automating the Vault Passphrase (Optional):
To avoid typing the vault password on every run, save your vault passphrase to a local file outside of the Git workspace and reference it inside ansible.cfg:

```Bash
echo "your-passphrase" > ~/.ansible_vault_pass
```

###3. Execution Runbook
To provision or run maintenance updates on the host engine, update your target machine IPs inside ansible/inventory.ini and execute:

```Bash
cd ansible
ansible-playbook bootstrap.yml
```
