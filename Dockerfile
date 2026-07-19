# Use Debian Bookworm as the base image
FROM debian:bookworm

# Update system packages and install QEMU and required utilities
RUN apt-get update && apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    wget \
    bash \
    python3 \
    python3-pip \
    ca-certificates \
    net-tools \
    netcat-openbsd \
    dbus \
    socat \
    lsof \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Create basic directories for data, ISOs, drivers, and scripts
RUN mkdir -p /data /iso /drivers /scripts /var/run/dbus

# Install websockify package to run noVNC via web browser
RUN pip3 install --no-cache-dir websockify --break-system-packages

# Download the Windows 10 Lite ISO file from archive
RUN wget --progress=bar:force -O /iso/os.iso \
    "https://dn720803.ca.archive.org/0/items/windows-10-lite-edition-19h2-x64/Windows%2010%20Lite%20Edition%2019H2%20x64.iso"

# Download and extract noVNC tool
RUN wget -q "https://github.com/novnc/noVNC/archive/v1.4.0.tar.gz" && \
    tar -xzf v1.4.0.tar.gz && \
    mv noVNC-1.4.0 /novnc && \
    rm -f v1.4.0*

# Download VirtIO drivers for Windows performance optimization
RUN wget -q "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.285-1/virtio-win.iso" -O /drivers/virtio.iso

# Create the startup script with the new branding name (walksys)
RUN cat > /scripts/start.sh << 'ENDSCRIPT'
#!/bin/bash
set -uo pipefail

echo "========================================="
echo "  walksys - Windows VM"
echo "========================================="

RAM="${RAM:-4096}"
CPU="${CPU:-2}"
RDP="${RDP:-3389}"
DISK="${DISK:-60G}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
MONITOR_HOST="127.0.0.1"
MONITOR_PORT="7100"

cleanup() {
    echo "[*] Shutting down..."
    [[ -n "${QEMU_PID:-}" ]] && kill -0 "$QEMU_PID" 2>/dev/null && kill -TERM "$QEMU_PID" 2>/dev/null
}
trap cleanup EXIT INT TERM

mkdir -p /var/run/dbus
dbus-uuidgen --ensure 2>/dev/null || true
pgrep -x dbus-daemon >/dev/null || dbus-daemon --system --fork 2>/dev/null || true

if [ ! -f /data/disk.qcow2 ]; then
    echo "[*] Creating ${DISK} disk image..."
    qemu-img create -f qcow2 /data/disk.qcow2 ${DISK}
fi

DISK_SIZE=$(stat -c%s /data/disk.qcow2 2>/dev/null || echo 0)
if [ "$DISK_SIZE" -gt 3221225472 ]; then
    echo "[*] Existing installation detected. Booting from disk."
    INSTALLED=1
    DISK_BOOTINDEX=1
else
    echo "[*] No installation detected. Booting from CD."
    INSTALLED=0
    DISK_BOOTINDEX=2
fi

MAC="52:54:00:$(printf '%02x' $((RANDOM%256))):$(printf '%02x' $((RANDOM%256))):$(printf '%02x' $((RANDOM%256)))"

if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "[*] KVM acceleration enabled."
    KVM_FLAGS="-enable-kvm -cpu host,kvm=on"
    ACCEL="kvm"
else
    echo "[*] KVM not available. Using TCG emulation."
    KVM_FLAGS="-cpu qemu64"
    ACCEL="tcg"
fi

echo "[*] Config: RAM=${RAM}MB | CPUs=${CPU} | DISK=${DISK} | RDP=${RDP} | MAC=${MAC}"

if [ ! -f /iso/os.iso ]; then
    echo "[!] ERROR: /iso/os.iso not found!"
    exit 1
fi

echo "[*] Starting QEMU..."

QEMU_CMD=(
    qemu-system-x86_64
    -name Windows10,process=windows10
    -nodefaults
    -machine type=q35,accel=${ACCEL},usb=off,vmport=off
    ${KVM_FLAGS}
    -smp ${CPU},sockets=1,cores=${CPU},threads=1,maxcpus=${CPU}
    -m ${RAM}
    -rtc base=localtime,driftfix=slew
    -vga none
    -device virtio-vga
    -k en-us

    # VirtIO SCSI (Best performance)
    -device virtio-scsi-pci,id=scsi0
    -drive file=/data/disk.qcow2,format=qcow2,if=none,id=disk0,cache=none,aio=threads
    -device scsi-hd,drive=disk0,bus=scsi0.0,bootindex=${DISK_BOOTINDEX}

    # IDE Controller for ISOs
    -device ich9-ahci,id=ahci0
    -drive file=/drivers/virtio.iso,format=raw,if=none,id=cdrom1,media=cdrom,readonly=on
    -device ide-cd,bus=ahci0.0,drive=cdrom1

    # SMBIOS branding (walksys)
    -smbios type=0,vendor="walksys",version="v1.0"
    -smbios type=1,manufacturer="walksys Technologies",product="walksys Windows VM",version="1.0"
    -smbios type=2,manufacturer="walksys Technologies",product="walksys VM Platform"
    -smbios type=3,manufacturer="walksys Technologies",version="walksys Chassis"
)

if [ "$INSTALLED" -eq 0 ]; then
    QEMU_CMD+=(
        -drive file=/iso/os.iso,format=raw,if=none,id=cdrom0,media=cdrom,readonly=on
        -device ide-cd,bus=ahci0.1,drive=cdrom0,bootindex=1
    )
fi

# VNC with optional password
if [ -n "$VNC_PASSWORD" ]; then
    echo "[*] VNC Password Protection: ENABLED"
    QEMU_CMD+=(-display vnc=:0,password=on)
else
    QEMU_CMD+=(-display vnc=:0)
fi

QEMU_CMD+=(
    -netdev user,id=net0,hostfwd=tcp::${RDP}-:3389
    -device virtio-net-pci,netdev=net0,mac=${MAC}
    -device qemu-xhci,id=xhci0
    -device usb-tablet,bus=xhci0.0
    -device usb-kbd,bus=xhci0.0
    -device virtio-balloon-pci
    -device virtio-rng-pci
    -audiodev none,id=snd0
    -device ich9-intel-hda
    -device hda-duplex,audiodev=snd0
    -chardev file,id=serial0,path=/data/qemu-serial.log
    -serial chardev:serial0
    -monitor tcp:${MONITOR_HOST}:${MONITOR_PORT},server,nowait
    -boot menu=off
)

"${QEMU_CMD[@]}" &

QEMU_PID=$!

echo "[*] QEMU started (PID: $QEMU_PID)"

# Set VNC password if provided
if [ -n "$VNC_PASSWORD" ]; then
    echo "[*] Setting VNC password..."
    for i in {1..30}; do
        if nc -z "$MONITOR_HOST" "$MONITOR_PORT" 2>/dev/null; then
            printf 'set_password vnc "%s"\n' "$VNC_PASSWORD" | socat - TCP:"$MONITOR_HOST":"$MONITOR_PORT" >/dev/null 2>&1 && {
                echo "[*] VNC password set successfully."
                break
            }
        fi
        if ! kill -0 "$QEMU_PID" 2>/dev/null; then
            echo "[!] QEMU died before VNC password could be set!"
            wait "$QEMU_PID" || true
            exit 1
        fi
        sleep 1
    done
fi

echo "[*] Waiting for VNC server..."
VNC_READY=0
for i in {1..30}; do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        echo "[!] QEMU died before VNC became ready!"
        wait "$QEMU_PID" || true
        exit 1
    fi
    if nc -z localhost 5900 2>/dev/null; then
        VNC_READY=1
        echo "[*] VNC server is ready."
        break
    fi
    sleep 1
done

if [ "$VNC_READY" -ne 1 ]; then
    echo "[!] VNC failed to start within 30 seconds."
    kill "$QEMU_PID" 2>/dev/null || true
    exit 1
fi

echo "[*] Starting noVNC websockify on port 6080..."
cd /novnc
websockify --web=/novnc --cert=none 6080 localhost:5900 &
WEBSOCKIFY_PID=$!

echo ""
echo "========================================="
echo "  walksys Windows VM is RUNNING"
echo "  noVNC:   http://localhost:6080/vnc.html"
if [ -n "$VNC_PASSWORD" ]; then
    echo "  VNC Password: ENABLED"
fi
echo "  VNC:     localhost:5900"
echo "  RDP:     localhost:${RDP}"
echo "========================================="
echo ""

set +e
wait "$QEMU_PID"
EXIT_CODE=$?
set -e

echo "[*] QEMU exited with code ${EXIT_CODE}"
exit ${EXIT_CODE}
ENDSCRIPT

# Grant execution permissions to the startup script
RUN chmod +x /scripts/start.sh

# Expose ports: 3389 for RDP, 5900 for VNC, and 6080 for noVNC
EXPOSE 3389/tcp 5900/tcp 6080/tcp

# Define volumes to persist data and ISOs
VOLUME ["/data", "/iso"]

# Set default working directory
WORKDIR /data

# Use Tini as the entrypoint for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--"]

# Set default command to execute the script
CMD ["/scripts/start.sh"]
