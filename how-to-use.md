# How to Use This Skeleton Repo

This repository is designed as a clone-and-play starter kit for your self-sovereign homelab. Follow these instructions to get your services up and running.

## Prelude: Philosophy & Evolution
Keep in mind that this skeleton is not necessarily the "best" way to build a homelab. It is simply the way that works best for me. This architecture originally started as a simple storage container for my documents for an entire year before evolving into a wider, more comprehensive ecosystem of containers, `dev` repositories, and staged workflows. Features like the `~/homelab/dev` structure and the tight integration with Gitea and Agentic AIs are relatively new additions. Because of this organic growth, the architecture remains highly malleable. Expect further updates, refinements, and expansions to this repository as the homelab continues to evolve!

## Prelude: Hardware & Performance
While the architecture documentation focuses on the Raspberry Pi 4B, this specific hardware setup is entirely optional. Any standard x86-64 workstation will work beautifully, especially considering how well the stack performs on an ARM-based Pi. 

To give you an idea of the performance footprint on a Raspberry Pi 4B (8GB):
- **CPU Utilization**: Averages around 20% on idle, scaling up to ~60% during heavy `syncthing` file operations.
- **Memory**: Idles at roughly 6GB of RAM usage.
- **Swap**: Utilizes around 8GB of SSD-backed swap space to handle memory spikes gracefully.

---

## 1. Filling in the Containers
Inside the `homelab/containers/` directory, you will find empty folders for every service documented in the architecture. To bring a service online, you must create and fill in your own `docker-compose.yml` file within its respective folder, configuring it to match your specific environment.

> [!TIP]
> **Coming Soon**: A general, fully plug-and-play homelab setup will be uploaded to this repository in the future. It will include pre-configured compose files and a master script to automatically `docker compose up` the entire stack (or allow you to turn them on individually and test).

## 2. Managing Backups
At the root of the repository, you'll find `zz-script_backup.sh`. You can use this script to perform automated, live Layer 1 backups of all your active containers. Ensure you modify the script with your specific username before executing it.

## 3. Extending with Custom Scripts
Rather than relying exclusively on the provided `zz` backup script, you can create a dedicated `scripts/` folder next to your `storage/` directory to house all your custom automation tasks. If you need inspiration, check out the [spaceadler/scripts](https://github.com/spaceadler/scripts) repository!

## 4. The Gitea Workflow & Agentic AIs
Once your `Gitea` container is up and running, you can create your own private Git repositories. Clone these repositories into the `/homelab/dev/` folder and sync them across your devices via Syncthing. 

This workflow is especially powerful if you use Agentic AIs. You can store your agent dotfiles, rules, and customization settings here (for example, configuring your Antigravity agent!) and have them seamlessly persist and sync across your entire homelab ecosystem.

## 5. Staging in the Mailbox
The `mailbox/` folder is designed to act like a physical inbox on a desk. When you are in a hurry and have files or folders that you don't have time to properly sort yet, drop them into the mailbox. This prevents you from cluttering up your meticulously organized `storage` arrays with unsorted data. You can come back later, think it over, and move them to their permanent homes.

## 6. Storage Notes
The `/homelab/storage/Notes` folder was originally designed as the bind mount target for **Flatnotes**. However, the storage architecture is flexible. You can easily repurpose this directory as a vault for a self-hosted **Obsidian** setup instead of using Anytype, depending on your preferred second-brain workflow.
