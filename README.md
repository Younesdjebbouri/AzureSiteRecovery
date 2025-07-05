# AzureSiteRecovery

This repository contains a set of PowerShell scripts used to configure and operate Azure Site Recovery (ASR) between two Azure zones. The scripts help automate the initial configuration, registration of virtual machines, network adjustments and the failover/failback process.

## Prerequisites

- Azure PowerShell modules installed (`Az` module).
- Access to a Recovery Services Vault and the virtual machines you want to replicate.

## Scripts overview

| Script | Purpose |
| ------ | ------- |
| `ASR_init.ps1` | Create the ASR fabric, protection containers and replication policy. Run once before enabling replication. |
| `ASR_add_vm.ps1` | Enable protection for a virtual machine. |
| `ASR_post_add_vm.ps1` | Wait for the first replication to complete and then configure disks and networking for the VM. |
| `ASR_get_vms_config.ps1` | Display the configuration of all VMs within a protection container. |
| `ASR_get_disks_config.ps1` | Helper used to build disk replication configuration objects. |
| `ASR_get_vm_advanced_networking.ps1` | Show the advanced network replication settings for a VM. |
| `ASR_set_disks_config.ps1` | Update the replication settings for disks of a VM. |
| `ASR_set_vm_advanced_networking.ps1` | Configure network settings used during failover and test failover. |
| `ASR_set_capacity_reservation.ps1` | Attach the replicated VM to a Capacity Reservation Group. |
| `ASR_set_scaleset.ps1` | Specify the target Virtual Machine Scale Set for failover. |
| `ASR_Offline_FailoverTransfertASG.ps1` | Apply ASG configuration to replicated NICs using previously exported JSON files. |
| `ASR_Online_FailoverTransfertASGs.ps1` | Copy ASG settings from the source VM to the replicated VM when both are running. |
| `ASR_One_NIC_ASGs_Transfert.ps1` | Utility to copy ASGs from one NIC to another. |
| `ASR_reprotect.ps1` | Re-enable replication back to the primary zone after a failover. |
| `ASR_Procedure_Bascule.ps1` | Example script orchestrating a failover or a failback. |
| `ASR_set_vms-tags.ps1` | Helper to update VM tags when switching zones. |
| `config/Get_Vms_ASR_LB_Settings.ps1` | Export NIC configuration (ASGs and load balancer pools) to JSON. |

## Typical execution order

1. **Initial setup** – run `ASR_init.ps1` once to create the ASR fabric, replication policy and protection containers.
2. **Register VMs** – execute `ASR_add_vm.ps1` for every VM that must be protected. When the initial replication is done, call `ASR_post_add_vm.ps1` to apply disk and network settings.
3. **Verify configuration** – use `ASR_get_vms_config.ps1` and `config/Get_Vms_ASR_LB_Settings.ps1` to check the current replication state and export network information if needed.
4. **Failover** – to perform a planned failover you can use `ASR_Procedure_Bascule.ps1` or the online/offline transfer scripts depending on your scenario.
5. **Reprotection** – after failing over to the secondary zone, run `ASR_reprotect.ps1` to start replication back to the original zone.
6. **Optional tweaks** – scripts such as `ASR_set_capacity_reservation.ps1`, `ASR_set_scaleset.ps1` or `ASR_set_vms-tags.ps1` can be used to adjust the configuration.

Each script contains parameter examples in comments. They are intended to be executed from Azure Cloud Shell or any PowerShell session where the `Az` modules are available.

