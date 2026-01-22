# sovereign-homelab

> **Mission Statement:** To engineer a comprehensive, self-sovereign digital infrastructure architected on first principles, reclaiming data ownership through physically isolated hardware, encrypted mesh networking, and auditable Infrastructure as Code (IaC), thereby eliminating reliance on rent-seeking centralized SaaS providers.

![Status](https://img.shields.io/badge/Status-Active-success)
![Containerization](https://img.shields.io/badge/Containerization-Docker-blue)
![Network](https://img.shields.io/badge/Network-Tailscale-black)
![OS](https://img.shields.io/badge/OS-Debian-red)
![Security](https://img.shields.io/badge/Security-SSL-brightgreen)
![Architecture](https://img.shields.io/badge/Architecture-ARM64-orange)

## Table of Contents
1. [Architectural Overview & Philosophy](#architectural-overview--philosophy)
2. [Network Topology & Security Model](#network-topology--security-model)
3. [Hardware Infrastructure](#hardware-infrastructure--provisioning)
4. [The Stack: Gateway & Authentication](#the-stack-gateway--authentication)
5. [The Stack: Observability & Maintenance](#the-stack-observability--maintenance)
6. [The Stack: Media & Streaming](#the-stack-media--streaming)
7. [The Stack: Knowledge & Productivity](#the-stack-knowledge--productivity)
8. [The Stack: Finance & Analytics](#the-stack-finance--analytics)
9. [The Stack: Storage & Synchronization](#the-stack-storage--synchronization)
10. [Technical Implementation & Storage Strategy](#technical-implementation--storage-strategy)
11. [Deployment Strategy (IaC)](#deployment-strategy-infrastructure-as-code)
12. [Backup & Disaster Recovery](#backup-redundancy--disaster-recovery)

---

## Architectural Overview & Philosophy

The `sovereign-homelab` repository represents a radical departure from the prevailing model of digital consumption, which relies heavily on centralized, rent-seeking Cloud Service Providers (CSPs). In the current digital epoch, termed by some analysts as the age of "technofeudalism," users typically lease access to their own data—photos, documents, financial records—paying with privacy and monthly subscriptions. This project inverts that dynamic, establishing a "First Principles" architecture where the user retains absolute authority over the data lifecycle, compute resources, and access control lists (ACLs).

### The Imperative of Data Sovereignty
The primary driver for this architecture is Digital Sovereignty. Commercial cloud providers operate on models predicated on data surveillance, vendor lock-in, and the commodification of user behavior. By self-hosting critical infrastructure, we reclaim the "Digital Self."
* Photos stored in **Immich** are files on a locally owned solid-state drive, not training data for a third-party generative adversarial network.
* Notes in **Memos** and **Docmost** remain private cognitive artifacts rather than vectors for targeted advertising.

### Security via Isolation (The Zero Trust Model)
Traditional homelab architectures often rely on perimeter security models, exposing ports (80/443) to the public internet. This project rejects that model in favor of Zero Trust Networking.

1.  **No Public Ingress:** The edge router forwards no ports. The public IP address of the home network serves strictly as an egress point.
2.  **Mesh VPN:** The architecture leverages a Hub-and-Spoke VPN model powered by Tailscale. This creates a virtual overlay network where devices must cryptographically authenticate via a coordination server before they can even perceive the existence of the host node.
3.  **Internal Routing:** Services are addressed via a local DNS zone (`spaceadler.local`), resolving only within the context of the encrypted mesh.

### Infrastructure as Code (IaC)
The operational state of the system is defined declaratively. The `docker-compose.yml` files act as the single source of truth for the entire deployment. Rebuilding the server is not a manual process of installing binaries and editing config files, but an automated orchestration of container deployment.

---

## Network Topology & Security Model

The network topology is designed to prioritize rigorous security without sacrificing the ease of use typically associated with local area networks. The Tailscale daemon runs on the Host Node (Raspberry Pi), advertising the device to the encrypted mesh.

### Mermaid Topology Diagram

```mermaid
graph TD
    %% --- STYLING DEFINITIONS ---
    classDef client fill:#ffeba1,stroke:#fbc02d,stroke-width:2px,color:#000;
    classDef vpn fill:#212121,stroke:#000,stroke-width:2px,color:#fff;
    classDef dns fill:#b3e5fc,stroke:#0288d1,stroke-width:2px,color:#000;
    classDef proxy fill:#e1bee7,stroke:#7b1fa2,stroke-width:2px,color:#000;
    classDef cluster fill:#ffffff,stroke:#cfd8dc,stroke-width:2px,stroke-dasharray: 5 5;
    classDef service fill:#f5f5f5,stroke:#9e9e9e,stroke-width:1px,color:#000;

    %% --- NODES ---
    
    User[Client Device<br/>(Phone / Laptop)]:::client
    
    subgraph Network [" 🔒 Secure Mesh Network "]
        TS[Tailscale Interface<br/>100.x.y.z]:::vpn
    end

    subgraph Host [" ⚡ Raspberry Pi 4 Host "]
        
        %% GATEKEEPERS
        subgraph Gatekeepers [" Gatekeepers "]
            PiHole[Pi-Hole<br/>DNS Resolver]:::dns
            Nginx[Nginx<br/>Reverse Proxy]:::proxy
        end

        %% CLUSTER: AI & INTELLIGENCE
        subgraph C_AI [" 🧠 AI & Intelligence "]
            Ollama[Ollama<br/>LLM Backend]:::service
            OpenWeb[OpenWebUI<br/>Chatbot]:::service
        end

        %% CLUSTER: MEDIA
        subgraph C_Media [" 🍿 Media & Streaming "]
            Immich[Immich<br/>Photos]:::service
            Navi[Navidrome<br/>Music]:::service
            Strem[Stremio<br/>Video]:::service
            Kav[Kavita<br/>Books]:::service
            Wiki[Kiwix<br/>Offline Wiki]:::service
        end

        %% CLUSTER: BRAIN
        subgraph C_Brain [" 📝 Knowledge & Productivity "]
            Doc[Docmost<br/>Wiki]:::service
            Memo[Memos<br/>Notes]:::service
            Vik[Vikunja<br/>Tasks]:::service
            Kara[Karakeep<br/>Bookmarks]:::service
            Rad[Radicale<br/>Calendar]:::service
            Glance[Glance<br/>Dashboard]:::service
        end

        %% CLUSTER: FINANCE
        subgraph C_Fin [" 💰 Finance "]
            Ghost[Ghostfolio<br/>Stocks]:::service
            Maybe[Maybe<br/>Budget]:::service
        end

        %% CLUSTER: OPS
        subgraph C_Ops [" 🛠️ Ops & Storage "]
            Vault[Vaultwarden<br/>Passwords]:::service
            File[FileBrowser<br/>Files]:::service
            Sync[Syncthing<br/>Backups]:::service
            Port[Portainer<br/>Docker UI]:::service
            Kuma[Uptime Kuma<br/>Status]:::service
            Beszel[Beszel<br/>Metrics]:::service
            DL[Downloader<br/>JDownloader/QB]:::service
        end
    end

    %% --- CONNECTIONS ---

    %% 1. CONNECTION
    User ==>|1. Connects to Mesh| TS

    %% 2. DNS RESOLUTION (Dotted)
    TS -.->|2. DNS Query<br/>'service.local'| PiHole
    PiHole -.->|3. Resolves to<br/>100.x.y.z| TS

    %% 3. TRAFFIC ROUTING (Thick)
    TS ==>|4. HTTPS Request<br/>Host: service.local| Nginx

    %% 4. PROXY DISPATCH (AI)
    Nginx -->|proxy_pass| OpenWeb
    OpenWeb -.->|API :11434| Ollama

    %% 5. PROXY DISPATCH (MEDIA)
    Nginx -->|:2283| Immich
    Nginx -->|:4533| Navi
    Nginx -->|:8080| Strem
    Nginx -->|:5000| Kav
    Nginx -->|:8080| Wiki

    %% 6. PROXY DISPATCH (BRAIN)
    Nginx -->|:3000| Doc
    Nginx -->|:5230| Memo
    Nginx -->|:3456| Vik
    Nginx -->|:3000| Kara
    Nginx -->|:5232| Rad
    Nginx -->|:8080| Glance

    %% 7. PROXY DISPATCH (FINANCE)
    Nginx -->|:3000| Ghost
    Nginx -->|:3000| Maybe

    %% 8. PROXY DISPATCH (OPS)
    Nginx -->|:80| Vault
    Nginx -->|:8080| File
    Nginx -->|:8384| Sync
    Nginx -->|:9000| Port
    Nginx -->|:3001| Kuma
    Nginx -->|:8090| Beszel
    Nginx -->|:5800| DL

```

### Traffic Flow Analysis & Packet Lifecycle

1. **Resolution:** The client device requests `docmost.spaceadler.local`.
2. **Routing:** **Pi-hole** receives the query via the VPN and resolves it to the Tailscale IP (e.g., `100.x.y.z`).
3. **Transport:** Tailscale encrypts the packet (WireGuard) and punches a NAT hole to reach the Raspberry Pi directly.
4. **Ingress/Proxying:** **Nginx** inspects the HTTP Host header and proxies the request to the specific internal Docker container IP.

---

## Hardware Infrastructure & Provisioning

The physical foundation is chosen for a specific balance of energy efficiency (low OPEX) and I/O throughput.

| Component | Specification | Purpose & Justification |
| --- | --- | --- |
| **Compute Node** | Raspberry Pi 4 Model B | **8GB RAM** variant is a strict requirement to support memory-intensive microservices (Ollama, Immich). |
| **Primary Storage** | 1TB SSD (SATA via USB 3.0) | Hosts the OS (Debian), Docker volumes, and media assets. Replaces the MicroSD card to mitigate corruption risk. |
| **Boot Media** | USB MSD | The system boots directly from the SSD (EEPROM config `BOOT_ORDER=0xf41`), bypassing the SD card interface. |
| **Power** | Official USB-C Supply | Ensuring stable voltage (5.1V/3A) to prevent SSD brownouts. |

---

## The Stack: Gateway & Authentication

This layer handles ingress, DNS resolution, and secure connectivity.

| Service | Function | Configuration |
| --- | --- | --- |
| **Tailscale** | Mesh VPN | Enforces the perimeter. Configured with ACLs to strictly limit access to trusted devices only. |
| **Nginx** | Reverse Proxy | Maps internal Docker ports to user-friendly subdomains. Handles SSL termination. |
| **Pi-hole** | DNS & Ad Blocking | Authoritative DNS for `.local` domain. Blocks telemetry network-wide. |
| **Ollama** | Local LLM Backend | Runs models like `llama3` locally. Exposes API on port 11434 for AI apps. |
| **OpenWebUI** | Chat Interface | ChatGPT-like frontend interacting with local Ollama. Accessible via `chat.spaceadler.local`. |

---

## The Stack: Observability & Maintenance

"You cannot manage what you cannot measure."

| Service | Function | Configuration |
| --- | --- | --- |
| **Beszel** | Lightweight Monitoring | Low-resource hub-and-agent monitor for Docker stats and CPU temps. |
| **Uptime Kuma** | Status Page | Pings internal services every 60s. Alerts via Ntfy/Telegram on failure. |
| **Cup** | Image Updater | Scans for new image digests. Allows review of changelogs before updating. |
| **Portainer** | Orchestration | GUI for managing Docker stacks and viewing container logs. |
| **OpenSpeedTest** | Bandwidth Testing | Verifies internal LAN throughput and WiFi bottlenecks. |

---

## The Stack: Media & Streaming

The "Entertainment Center." Replaces Spotify, Netflix, and Kindle.

| Service | Function | Configuration |
| --- | --- | --- |
| **Immich** | Photos | Google Photos alternative. Uses machine learning for facial recognition. |
| **Navidrome** | Music | Subsonic API streamer. Transcodes FLAC to Opus for mobile bandwidth efficiency. |
| **Stremio** | Video Hub | Server component managing addons and stream resolution. |
| **Kavita** | E-books | Specialized for Manga (CBZ) and Epubs with progress sync. |
| **Kiwix** | Offline Knowledge | Hosts ZIM files (Wikipedia, StackOverflow) for offline access. |

---

## The Stack: Knowledge & Productivity

The "Second Brain." Replaces Notion, Todoist, and Google Calendar.

| Service | Function | Configuration |
| --- | --- | --- |
| **Docmost** | Documentation | Real-time collaborative wiki with "Spaces" and code block support. |
| **Memos** | Thought Stream | Privacy-first micro-blogging tool for capturing fleeting ideas. |
| **Vikunja** | Task Management | To-do list with Kanban boards and Gantt charts. |
| **Karakeep** | Web Archiving | Bookmarks URLs, caches content, and uses AI to auto-tag/summarize. |
| **Radicale** | CalDAV/CardDAV | Syncs calendars and contacts across devices. |
| **Glance** | Startpage | Dashboard aggregating RSS, calendar events, and service status. |

---

## The Stack: Finance & Analytics

The "CFO" of the homelab.

| Service | Function | Configuration |
| --- | --- | --- |
| **Ghostfolio** | Wealth Management | Tracks net worth across assets (Stocks, Crypto) privacy-first. |
| **Maybe** | Personal Finance | Budgeting and expense tracker (Self-hosted fork). |

---

## The Stack: Storage & Synchronization

The "Logistics" layer.

| Service | Function | Configuration |
| --- | --- | --- |
| **FileBrowser** | Web Interface | Web-based file manager for uploads/downloads to the SSD. |
| **Syncthing** | Synchronization | Decentralized sync between Pi, PC, and Mobile (BEP protocol). |
| **QBittorrent** | P2P Client | Manages downloads via VPN for ISOs/Media. |
| **JDownloader** | DDL Client | Headless container for direct download links. |
| **Vaultwarden** | Password Manager | Rust implementation of Bitwarden. Stores credentials locally. |

---

## Technical Implementation & Storage Strategy

### Storage Strategy: The Directory-as-Volume Pattern

Instead of opaque Docker volumes, services bind-mount specific host directories located on the 1TB SSD. This ensures data remains accessible as standard files.

```text
/mnt/ssd/storage
├── Downloads/      # Ingress for JDownloader/QBittorrent
├── Gallery/        # Immich storage (Originals + Thumbs)
├── Media/
│   ├── Books/      # Target for Kavita
│   ├── Music/      # Target for Navidrome
│   └── Resources/  # Kiwix ZIM files
├── Personal/
│   ├── Code/       # Git Repos
│   └── Documents/  # General file storage

```

### Networking Strategy

* **Tailscale ACLs:** Ingress restricted to devices tagged `tag:trusted`.
* **DNS Rewriting:** Pi-hole Wildcard A Record: `*.spaceadler.local -> 100.x.y.z`.
* **Reverse Proxy:** Nginx listens on 80/443 and routes via Server Blocks (`proxy_pass http://container_name:port`).

---

## Deployment Strategy (Infrastructure as Code)

The deployment utilizes Docker Compose for modularity. Below is an example snippet showing the isolation of the Productivity Stack.

```yaml
version: '3.8'

services:
  docmost:
    image: docmost/docmost:latest
    container_name: docmost
    restart: unless-stopped
    depends_on:
      - docmost-db
      - docmost-redis
    environment:
      APP_URL: "[http://docs.spaceadler.local](http://docs.spaceadler.local)"
      DATABASE_URL: "postgresql://docmost:password@docmost-db:5432/docmost"
    networks:
      - internal_net

  docmost-db:
    image: postgres:16-alpine
    restart: unless-stopped
    volumes:
      - ./data/db:/var/lib/postgresql/data
    networks:
      - internal_net

networks:
  internal_net:
    driver: bridge

```

---

## Backup, Redundancy, & Disaster Recovery

The system employs a rigorous **3-2-1 Backup Strategy**.

1. **Layer 1: Local Sync (Hot Storage)**
* **Tool:** Syncthing.
* **Mechanism:** Real-time sync of `/storage` and `docker-compose` configs to a local Windows Workstation.


2. **Layer 2: Cloud Encryption (Cold Storage)**
* **Tool:** Filen (Zero-Knowledge).
* **Mechanism:** The Windows workstation automatically encrypts and uploads the Syncthing target folder to the cloud.


3. **Layer 3: Disaster Recovery**
* **RTO:** < 1 Hour.
* **Process:** Flash OS -> Install Docker -> Pull Backup from Filen -> `docker-compose up -d`.



---

*powered by logic, coffee, and sleepless nights*
