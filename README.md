# IP Swap Scripts

## Overview
These two Bash scripts automate **IP address swaps** between two servers:

- **Ubuntu/Debian (Netplan-based)** → `update_ip_ubuntu.sh`  
- **Debian (interfaces-based)** → `update_ip_debian.sh`

Each script updates the system’s IP address, applies the change, and **automatically reverts** to the original configuration after a specified interval if there's no manual intervention.
They are designed to be executed **in parallel** on two systems during IP swaps.

---
## Process Overview:
1. Copy the scripts to the relevant machines
2. Run the script on both machines and follow the prompts until 1 step before the changes are going to be applied.
3. Ensure that you hit enter on both servers at the same time.
4. Reload ssh connections from hosts
5. Login as root on both servers
6. Run command to kill ip revert processes

---

## Copy the scripts to the relevant machines.

```bash

sudo nano update_ip_debian.sh && sudo chmod +x update_ip_debian.sh

```

```bash
sudo nano update_ip_ubuntu.sh && sudo chmod +x update_ip_ubuntu.sh

```

---

## Run the scripts


| Argument                   | Description                                      | Example                                  |
|----------------------------|--------------------------------------------------|-----------------------------------------|
| `<Netplan config file>`    | Full path to the Netplan YAML configuration file to update. | `/etc/netplan/01-netcfg.yaml`           |
| `<New IP>`*                 | The IP address to assign to the host. | `192.168.1.120`                         |
| `<Sleep interval in seconds>`* | Time to wait before reverting to the original IP. (should be the same across two servers) | `300` (5 minutes)                        |


### Ubuntu (Netplan-Based Systems)
```bash

sudo ./update_ip_ubuntu.sh <Netplan config file> <New IP> <Sleep interval>

```

### Debian (simple networking config)
```bash

sudo ./update_ip_debian.sh <New IP> <Sleep interval>

```

---

### Working Examples:
> <img width="968" height="280" alt="image" src="https://github.com/user-attachments/assets/a71893c0-f463-4e4c-ab7f-42608a274279" />

If there's one IP, that IP will be selected by default:
> <img width="756" height="227" alt="image" src="https://github.com/user-attachments/assets/b2c3d8ce-1dcc-4e20-843f-75a19b9929c0" />

Otherwise, you have to select the IP you want to change:
> <img width="910" height="309" alt="image" src="https://github.com/user-attachments/assets/70af9eb8-b445-484e-a95f-0fdbe73c6334" />

Copy the command:
```bash

ps -f -C bash | grep 'sleep 500' | awk '{print $2}' | sudo xargs kill -9

```

##### Netplan on the ubuntu server will show some errors and warnings, these are expected:

> <img width="1154" height="424" alt="image" src="https://github.com/user-attachments/assets/363975a5-4582-4c71-8386-874c405f105a" />

This shows that the command being run, kills the process that will revert the ip, killing the process will not result in the IP being reverted.
> <img width="1471" height="750" alt="image" src="https://github.com/user-attachments/assets/1eb406fe-c5cc-46fb-ae7a-e317df482d3a" />
