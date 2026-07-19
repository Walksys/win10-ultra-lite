# 🐳 Enterprise Windows 10 Lite VM inside Docker (KVM/QEMU)

A high-performance, dynamic **Windows 10 Lite Virtual Machine (VM)** running seamlessly inside a Docker container using QEMU/KVM virtualization. This image features automated storage initialization, dynamic hardware environment checks, an embedded **noVNC** web browser GUI, and native **RDP (Remote Desktop)** infrastructure forwarding.

## ⚡ Key Features

* 🌍 **VNC Web Interface:** Integrated `noVNC` and `websockify` layers to access the full Windows graphical desktop straight from any modern web browser.
* ⚙️ **Hardware Acceleration Support:** Native QEMU/KVM passthrough configuration that fully utilizes the host CPU performance (`-cpu host`) when KVM is present.
* 📦 **Automated Resource Scaling:** Smart internal scripts that automatically adjust memory distribution, CPU cores, and setup boot-order sequences (`ISO vs Virtual Disk`) depending on the runtime context.



## 🔐 **Quick Access Credentials**

* **Default Username**: Administrator / root
* **Default Password**: root
* **RDP Port**: 3389
* **Web VNC Port**: 6080

## 🚀 Usage & Deployment Profiles

Launch your virtual machine with custom hardware profiles directly from the command line. To ensure your Windows data and downloaded ISO cache are preserved, always map the persistent volumes (`windows_data` and `windows_iso`).

### 💻 Developer Standard Profile (8GB RAM, 4 CPU Cores, 100GB Disk)

Recommended for standard external VPS hosting or dedicated server setups:

```bash
docker run -d \
  --name walksys \
  --restart unless-stopped \
  --device /dev/kvm \
  -p 6080:6080 \
  -p 3389:3389 \
  -v $(pwd)/data:/data \
  -v $(pwd)/iso:/iso \
  -e MEM_SIZE=8G \
  -e CPU_CORES=4 \
  -e DISK_SIZE=100G \
  walksysdev/win10-ultra-lite
```

### ☁️ GitHub Codespaces High-Performance Profile (12GB RAM, 4 CPU Cores, 100GB Disk)

If you are deploying this container inside **GitHub Codespaces**, you can unlock massive bare-metal speed by taking advantage of Codespaces' native nested virtualization support. Follow these two simple steps:



#### Step 1: Compile the Image locally inside your Codespace

```bash
docker build -t walksysdev/win10-ultra-lite .
```

#### Step 2: Run the VM with Full Hardware Pass-through

```bash
docker run -d \
  --name walksys \
  --restart unless-stopped \
  --device /dev/kvm \
  -p 6080:6080 \
  -p 3389:3389 \
  -v $(pwd)/data:/data \
  -v $(pwd)/iso:/iso \
  -e MEM_SIZE=12G \
  -e CPU_CORES=4 \
  -e DISK_SIZE=100G \
  walksysdev/win10-ultra-lite
```

> 💡 **Why this profile?** GitHub Codespaces machines heavily support the `--device /dev/kvm` flag. By passing `RAM=12288` (12GB) and `CORES=4`, the Windows 10 Lite OS will boot instantly and operate with near-zero interface lag via VNC or RDP.

## 🌐 Network Routing & Access Links

| Connection Type | Target Address / URL | Transport Port | Description |
| --- | --- | --- | --- |
| 🌐 **Interactive Web GUI** | `http://localhost:6080` | `6080 (TCP)` | **Required for Setup**: Open this link in your browser to complete the Windows installation wizard. |
| 🔌 **Native Windows RDP** | `localhost:3389` | `3389 (TCP)` | **Best Performance**: Once Windows installation completes and RDP is active, connect via any RDP client. |

## 🛠️ Infrastructure Build Management

If you want to compile and build this virtualization image manually from the local Dockerfile environment:

### Manual Compilation Pipeline

```bash
docker build -t walksysdev/win10-ultra-lite .
```

> ❗ **Important Note for First-Time Boot:** During the very first launch, the script will automatically stream down the Windows 10 Lite ISO directly to your `windows_iso` volume and allocate a dynamic `50GB qcow2` disk instance inside `windows_data`. The installation wizard via noVNC can take 20-30 minutes to initialize fully depending on your host network and emulation state.



*Maintained with 💻 by [@walksysdev](https://hub.docker.com/r/walksysdev).*
