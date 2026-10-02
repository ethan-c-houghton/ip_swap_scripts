# IP Swap Scripts

## Overview
Two Bash scripts that swap a server's IPv4 address with a **timed automatic rollback**:

- **Ubuntu (Netplan)** → `ip_swap_ubuntu.sh`
- **Debian (`/etc/network/interfaces`)** → `ip_swap_debian.sh`

They are built for moving an IP from an old server to its replacement over SSH, when the connection runs over the very address being changed. Run them **in parallel** on both servers.

Each script:

1. Lists the machine's IPv4 addresses and asks which one to replace.
2. Backs up the network config.
3. Starts a background timer **before** changing anything, so the way back exists even if the SSH session drops.
4. Replaces the old IP with the new one (whole addresses only, so `10.0.0.1` never touches `10.0.0.15`) and applies it.
5. Runs a one-off health check: the new address must be on an interface and the default gateway must answer a ping (retried for about 30 seconds). If the apply fails or the check fails, the backup is restored straight away.
6. Unless the change is kept, the timer restores the backup when it runs out.

---

## Process overview
1. Copy the scripts to the relevant machines.
2. Run the script on both machines with the **same interval**, and follow the prompts up to the final "Press Enter" step.
3. Press Enter on both servers at the same time.
4. Reconnect over SSH on the new addresses.
5. Keep the change on both servers (see below).

If you can't reconnect, do nothing: when the timer runs out, both servers put their original config back on their own.

---

## Copy the scripts to the relevant machines

```bash
sudo nano ip_swap_ubuntu.sh && sudo chmod +x ip_swap_ubuntu.sh
```

```bash
sudo nano ip_swap_debian.sh && sudo chmod +x ip_swap_debian.sh
```

---

## Run the scripts

| Argument | Description | Example |
|----------|-------------|---------|
| `<Netplan config file>` | Ubuntu only. Full path to the Netplan YAML file to update. | `/etc/netplan/01-netcfg.yaml` |
| `<New IP>` | The IPv4 address to assign to the host. | `192.168.1.120` |
| `<Seconds before revert>` | How long to wait before restoring the original config. Use the same value on both servers. | `300` (5 minutes) |

### Ubuntu (Netplan)
```bash
sudo ./ip_swap_ubuntu.sh <Netplan config file> <New IP> <Seconds before revert>
```

### Debian (interfaces file)
```bash
sudo ./ip_swap_debian.sh <New IP> <Seconds before revert>
```

---

## Keep the change

Once you've reconnected on the new address, cancel the timer:

```bash
sudo kill $(cat /run/ip_swap_revert.pid)
```

The script prints this command before and after the swap.

---

## Files

| Path | What it holds |
|------|---------------|
| `/root/ip_swap/<config name>.<timestamp>.bak` | The config as it was before the swap, one per run |
| `/root/ip_swap/ip_swap.log` | Every swap, health check, revert and cancellation |
| `/run/ip_swap_revert.pid` | The pending revert's process ID; gone once it is cancelled or has run |

A script refuses to start while a revert from an earlier run is still pending, so a second run can't overwrite the backup the revert needs.

---

## Example runs

Output from the Ubuntu script, run in a test environment. The Debian script prints the same, with `/etc/network/interfaces` as the file.

If there's one IP, that IP is selected by default:

```console
$ sudo ./ip_swap_ubuntu.sh /etc/netplan/01-netcfg.yaml 192.168.1.120 300
Only one IP detected: 192.168.1.20
Are you sure you want to replace 192.168.1.20 with 192.168.1.120? (y/n): y

About to replace 192.168.1.20 with 192.168.1.120 in /etc/netplan/01-netcfg.yaml.
It reverts on its own after 300 seconds. To keep the change, reconnect on 192.168.1.120 and run:

    sudo kill $(cat /run/ip_swap_revert.pid)

Press Enter to proceed, or Ctrl+C to abort...
Swapping 192.168.1.20 -> 192.168.1.120 in /etc/netplan/01-netcfg.yaml (backup: /root/ip_swap/01-netcfg.yaml.20261002-154150.bak)
Automatic revert armed for 300 seconds (PID 4928)
Health check passed: 192.168.1.120 is up and the gateway 192.168.1.1 answers
IP swap applied: 192.168.1.20 -> 192.168.1.120
Reverts automatically in 300 seconds unless you keep the change:

    sudo kill $(cat /run/ip_swap_revert.pid)

Log: /root/ip_swap/ip_swap.log
```

Otherwise, you pick the IP you want to change:

```console
$ sudo ./ip_swap_ubuntu.sh /etc/netplan/01-netcfg.yaml 192.168.1.121 300
Available IP addresses on this machine:
1) 192.168.1.20
2) 192.168.1.21
#? 2
You selected: 192.168.1.21
Are you sure you want to replace 192.168.1.21 with 192.168.1.121? (y/n): y

About to replace 192.168.1.21 with 192.168.1.121 in /etc/netplan/01-netcfg.yaml.
```

##### Netplan on the Ubuntu server may show some errors and warnings; these are expected:

<img width="1154" height="424" alt="4" src="https://github.com/user-attachments/assets/a4a835b0-9cee-4bac-820d-c824a09af1f0" />
