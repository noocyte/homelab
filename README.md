# Infrastructure as Code (IaC) & GitOps Cluster

This repository contains the automation playbooks to provision a virtual machine on a physical Proxmox node (Layer 0), bootstrap our core Docker/Portainer engine inside it (Layer 1), and layout the structure for application stacks managed via GitOps (Layer 2).

---

## Layer 0: Proxmox Virtual Machine Provisioning

The 'ansible/create_vm.yml' playbook communicates with your physical Proxmox node's API, imports a lightweight Cloud-Init operating system image, and spins up a dedicated virtual machine.

### 1. Host Prerequisite (Download the Cloud Image)
Because Proxmox requires Cloud-Init disk images ('.qcow2') to be imported at the block level, you must download the official Debian 12 cloud image directly onto your physical Proxmox hardware first.

SSH into your Proxmox server (or open the Shell via the Proxmox Web UI) and run:

    mkdir -p /var/lib/vz/snippets
    wget -O /var/lib/vz/snippets/debian-12.qcow2 https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2

### 2. Local Control Node Setup
Before running the Proxmox automation, ensure your local development machine has the required Proxmox API Python packages injected into your Ansible environment:

    pipx inject ansible requests proxmoxer
    ansible-galaxy collection install community.proxmox

### 3. Execution Runbook
To build and start the VM, execute the playbook while safely passing your Proxmox root password into your terminal environment memory (keeping it entirely out of Git):

    cd ansible
    export PVE_PASSWORD="YourActualProxmoxRootPasswordHere"
    ansible-playbook create_vm.yml

---

## Layer 1: Host Bootstrapping (Docker & Portainer)

Once your VM is spun up and attached to your local network, 'ansible/bootstrap.yml' handles configuring the operating system, freeing up network ports (like port 53 for Pi-hole), and installing Portainer.

### 1. Update Your Target Inventory
Open 'ansible/inventory.ini' and update the IP address to match the network IP allocated to your brand-new VM:

    [my_docker_servers]
    192.168.1.50 ansible_user=debian

*(Note: Official Debian Cloud images utilize 'debian' as the default administrative user profile instead of 'root').*

### 2. Execution Runbook
Run the bootstrap script to lay down Docker and spin up Portainer:

    ansible-playbook bootstrap.yml

Once completed, navigate to 'https://<YOUR-VM-IP>:9443' to access Portainer.

---

## Layer 2: Application Stacks (Portainer GitOps)

With Portainer running, all apps inside the 'compose/' directory are managed strictly via Portainer's GitOps engine. Do NOT deploy these files manually over SSH.

### 1. Pi-hole Standalone
* Compose File: 'compose/pihole/docker-compose.yml'
* Portainer Configuration: Point Portainer to this repository, track your branch, and specify the compose path. 
* Environment Variables: Define 'PIHOLE_ADMIN_PASSWORD' and 'HOST_IP' securely inside the Portainer Stack UI during initialization.