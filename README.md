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
<img width="968" height="280" alt="1" src="https://github.com/user-attachments/assets/e6100093-2037-4627-a3b6-d26fd158d9c4" />

If there's one IP, that IP will be selected by default:
<img width="756" height="227" alt="2" src="https://github.com/user-attachments/assets/6e59648a-b86a-48e6-a79a-5a6320f45f02" />

Otherwise, you have to select the IP you want to change:
<img width="910" height="309" alt="3" src="https://github.com/user-attachments/assets/735d4687-1163-4adf-85b9-40e8fe2854ed" />

Copy the command:
```bash

ps -f -C bash | grep 'sleep 500' | awk '{print $2}' | sudo xargs kill -9

```

##### Netplan on the ubuntu server will show some errors and warnings, these are expected:

<img width="1154" height="424" alt="4" src="https://github.com/user-attachments/assets/a4a835b0-9cee-4bac-820d-c824a09af1f0" />

This shows that the command being run, kills the process that will revert the ip, killing the process will not result in the IP being reverted.
<img width="1471" height="750" alt="5" src="https://github.com/user-attachments/assets/afe8a02c-83ea-4d28-b9f9-488a3893da66" />
