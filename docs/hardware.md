# Hardware

← [README](../README.md)

The reference machine is a Raspberry Pi 4 Model B (8 GB). It's chosen for
its balance of power draw and I/O, though any 64-bit x86 machine works just
as well.

| Component | Specification | Purpose & Justification |
| --- | --- | --- |
| **Compute Node** | Raspberry Pi 4 Model B | The **8GB RAM** variant handles the memory-hungry apps (Immich's machine learning especially). |
| **Primary Storage** | 1TB SSD (SATA via USB 3.0) | Holds the OS, the apps and every file. Replaces the MicroSD card to avoid corruption. |
| **Boot Media** | USB MSD | Boots straight from the SSD (EEPROM `BOOT_ORDER=0xf41`), bypassing the SD card. |
| **Power** | USB-C Supply | A stable 5.1V/3A supply prevents SSD brownouts. |
| **Network** | Gigabit Ethernet | Wired to the router for streaming and large transfers. |

The Pi-specific preparation (USB boot, zram and swap) is in the
[How-to-Use Guide](../how-to-use.md#1-prepare-the-machine).

---

*powered by logic, coffee, and many sleepless nights*
