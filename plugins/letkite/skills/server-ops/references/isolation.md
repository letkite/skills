# One server, isolated guests

The server becomes a host that runs nothing but a hypervisor and a firewall. Each app (and each part of an app that faces the internet) gets a guest of its own: a KVM virtual machine, or a system container where the server has no KVM. All of it is managed with [Incus](https://linuxcontainers.org/incus/). Commands are for Ubuntu 24.04 and 26.04 hosts, run as root (`elevate`).

Tested:
- **VM path**: on an Ubuntu 26.04 host, three VMs.
- **Container path**: on a fresh Ubuntu 24.04 server with Incus 6.0, end to end: outbound access, the signal check, port isolation between two guests, a published port reached from outside, an unpublished one closed, and snapshot and restore.

## Why, even for one app

Put this to the person in a few sentences. It is the layout security reviews expect, and it costs little on a server with spare cores and memory:

- **Containment.** A compromised app owns its guest, not the server. It cannot read another app's secrets, its keys or its data, and it cannot touch the firewall or the host's access.
- **Internet-facing code gets its own kernel.** A VM separates kernels. A kernel or driver bug triggered from outside stays inside one guest.
- **A minimal host.** Nothing on the host listens to the internet, and nothing the apps run is installed there, so the most privileged machine has the smallest attack surface.
- **Least privilege per workload.** Each guest has its own accounts, its own LetKite node and its own ceiling. Access to one app never implies access to another, and the audit log shows which workload did what.
- **Network segmentation.** Guests cannot reach each other unless a rule says so. Each can have its own outbound address, for example one allow-listed by a partner.
- **Resource limits.** Each guest gets a fixed share of CPU, memory and disk, so a runaway or attacked app cannot starve the others or the host.
- **Recovery and change control.** Snapshot a guest before a risky change and roll back in seconds. Rebuild or move a guest to another server without touching the rest.
- **Room to grow.** A second app or a staging copy is one more guest, with no re-architecture.

Skip it only when the server is too small. As a rule of thumb, a VM wants at least 1 core and 1 GiB beyond what its app needs, and the host keeps about 1 GiB for itself.

## 1. Can this server run VMs?

```
systemd-detect-virt              # "none" on bare metal; "kvm" etc. when the server is itself a VM
ls -l /dev/kvm                   # present: KVM works here (on a cloud VM this means nested virtualization is on)
grep -cwE 'vmx|svm' /proc/cpuinfo
```

- **`/dev/kvm` present**: use VMs for every guest. This is the recommendation.
- **No `/dev/kvm`**: many cloud VMs have no nested virtualization. Use system containers. They share the host's kernel, so the isolation is weaker, but they still have separate users, files, network and limits. Run the signal check under step 4 first.

## 2. Install Incus

```
apt-get update
apt-get install -y --no-install-recommends incus dnsmasq-base squashfs-tools xz-utils uidmap attr btrfs-progs
# for VMs (Ubuntu 26.04 split qemu-img, the SPICE module and mkisofs into packages of their own):
apt-get install -y --no-install-recommends qemu-system-x86 qemu-utils qemu-system-modules-spice ovmf genisoimage
grep -q '^root:' /etc/subuid || echo 'root:1000000:1000000000' >> /etc/subuid
grep -q '^root:' /etc/subgid || echo 'root:1000000:1000000000' >> /etc/subgid
systemctl enable --now incus.socket
incus storage create default btrfs size=200GiB       # a sparse file on the host's disk; guest disk sizes are enforced
incus network create incusbr0 ipv4.address=10.123.0.1/24 ipv4.nat=true ipv6.address=none
incus profile device add default root disk pool=default path=/
incus profile device add default eth0 nic network=incusbr0 name=eth0
```

- `ipv4.nat=true`: guests reach the internet through the host's main address.
- Pick a private range that the server's own networks do not use.

## 3. Create a guest

A VM with a fixed address. On first boot, cloud-init installs the SSH server and the person's key, if they want SSH at all:

```
incus init images:ubuntu/24.04/cloud web-1 --vm \
  -c limits.cpu=2 -c limits.memory=4GiB -c boot.autostart=true \
  -c cloud-init.user-data="$(cat <<'EOF'
#cloud-config
package_update: true
packages: [curl]
EOF
)"
incus config device override web-1 root size=40GiB
incus config device override web-1 eth0 ipv4.address=10.123.0.10 \
  security.mac_filtering=true security.ipv4_filtering=true security.port_isolation=true
incus config device add web-1 cloud-init disk source=cloud-init:config   # VMs only: without it cloud-init sees no user-data
incus start web-1
incus exec web-1 -- cloud-init status --wait
```

- The `cloud-init` disk is what hands the user-data to a VM. Without it cloud-init falls back to a default datasource and silently does nothing. A container needs no such disk.
- `security.mac_filtering` and `ipv4_filtering`: a guest cannot pretend to be another address.
- `security.port_isolation`: guests on the bridge cannot reach each other at all, only the host and the internet.
- **For a container**, leave out `--vm` and the `cloud-init` disk, and add `-c security.privileged=false -c security.idmap.isolated=true`.

## 4. Check the guest works

```
incus exec web-1 -- curl -s -o /dev/null -w '%{http_code}\n' https://example.com    # outbound works
incus exec web-1 -- sh -c 'sleep 30 & p=$!; kill $p && wait $p; echo signal rc=$?'  # expect 143
```

The signal check matters for **containers on newer hosts**. On an Ubuntu 26.04 host, AppArmor stacking can deny signals between processes inside a container. The symptom is that rsync and `timeout` hang, and services do not stop. If `signal rc` is not 143, use VMs on this host.

## 5. Publish ports

Only the ports the app needs, from the host's public address to one guest:

```
incus network forward create incusbr0 <host public IP>
incus network forward port add incusbr0 <host public IP> tcp 80,443 10.123.0.10
incus network forward show incusbr0 <host public IP>
```

- **Each guest its own public address**: buy an additional IP from the provider and add it to the host's interface as a /32, in netplan under `addresses:`. Then create the forward on that address instead. Outbound traffic from the guest still leaves from the host's main address unless a SNAT rule says otherwise. Ask the person whether that matters, for example for a partner's allow-list.
- **The host's own firewall** stays closed: [accounts-firewall.md](accounts-firewall.md) with no public ports. Forwarded traffic is accepted by Incus's rules. ufw's default forward policy may drop it, so check with a request from outside. If it is dropped, set `DEFAULT_FORWARD_POLICY="ACCEPT"` in `/etc/default/ufw`, run `ufw reload`, and keep guest isolation to `security.port_isolation`.

## 6. Connect each guest to LetKite

Each guest is its own node, with its own ceiling and its own account to run as. The person runs the installer inside the guest, through the provider's console of the host:

```
incus exec web-1 -- bash
curl -fsSL https://get.letkite.com/install.sh | sh -s -- enroll --user deploy --name web-1
```

Then they approve the code as in [connect-node.md](connect-node.md). Everything in [deploy-app.md](deploy-app.md) then happens inside the guest.

The host itself:
- **Either** stays out of LetKite (the person manages it from the provider's console);
- **or** is a node of its own with `elevate` on only while guests are being added, and with no AI connection reaching it day to day.

## 7. Day to day

| Task | Command (on the host) |
|---|---|
| list guests | `incus list` |
| snapshot before a risky change | `incus snapshot create web-1 before-upgrade` |
| roll back | `incus snapshot restore web-1 before-upgrade` |
| more CPU or memory | `incus config set web-1 limits.cpu=4 limits.memory=8GiB` (a VM picks up memory at its next restart) |
| bigger disk | `incus config device set web-1 root size=80GiB` (grow only) |
| console when the network is broken | `incus console web-1` (VM) or `incus exec web-1 -- bash` |
| back up a whole guest | `incus export web-1 /var/backups/web-1.tar.gz` |
