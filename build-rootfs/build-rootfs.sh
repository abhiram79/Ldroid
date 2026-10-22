#!/bin/sh
# Build the LDroid Debian guest root filesystem.
#
# Runs inside the aarch64 builder stage of Dockerfile.rootfs, after
# debootstrap has installed the base Debian system and the static helpers
# have been copied into /work/rootfs/usr/local/bin.
set -eu
ROOTFS=/work/rootfs

: "${DEBIAN_VERSION:?DEBIAN_VERSION must be set (e.g. bookworm)}"
: "${DEBIAN_ARCH:?DEBIAN_ARCH must be set (e.g. arm64)}"

# ── Debian apt sources ───────────────────────────────────────────────────────
# The squashfs is the read-only lower layer; `apt` writes into the persistent
# overlay.  Only main is enabled: the image intentionally ships no container
# runtime, so contrib is not needed either.
cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb http://deb.debian.org/debian ${DEBIAN_VERSION} main
deb http://deb.debian.org/debian ${DEBIAN_VERSION}-updates main
deb http://security.debian.org/debian-security ${DEBIAN_VERSION}-security main
EOF

# ── Root account ─────────────────────────────────────────────────────────────
# LDroid ships a single root account.  The password is the documented default
# "ldroid"; it is stored as a SHA-512 hash with a random salt.
ROOT_HASH=$(openssl passwd -6 ldroid)
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"

# Debian's default root entry is locked/`*`; make sure the account cannot be
# expired in the persistent overlay on first login.
chroot "$ROOTFS" chage -E -1 -M 99999 root 2>/dev/null || true

# Root may log in on the two virtual consoles LDroid exposes:
# hvc0 (QEMU/AVF primary terminal) and ttyS0 (QEMU serial fallback).
cat > "$ROOTFS/etc/securetty" <<'EOF'
console
ttyAMA0
hvc0
ttyS0
pts/0
pts/1
pts/2
pts/3
EOF

# ── Strip docs/man/locale to shrink the squashfs ─────────────────────────────
rm -rf "$ROOTFS/usr/share/man" "$ROOTFS/usr/share/doc" \
       "$ROOTFS/usr/share/locale" "$ROOTFS/usr/share/info"

# Debian ships pulseaudio as a system service and socket.  LDroid starts
# pulseaudio itself (ldroid-pulseaudio.service), so those units are masked
# below and never started by the package defaults.

# ── LDroid service scripts ───────────────────────────────────────────────────
# Setup scripts live in /usr/local/lib/ldroid; daemons stay in /usr/local/bin.
# The systemd units below call the scripts directly.
mkdir -p "$ROOTFS/usr/local/lib/ldroid"
for f in ldroid-bootstrap ldroid-network ldroid-migrate ldroid-ready ldroid-xvnc; do
    cp "/work/files/usr/local/lib/ldroid/$f" "$ROOTFS/usr/local/lib/ldroid/$f"
    chmod 0755 "$ROOTFS/usr/local/lib/ldroid/$f"
done

# ── systemd units ────────────────────────────────────────────────────────────
mkdir -p "$ROOTFS/etc/systemd/system"
cp /work/files/etc/systemd/system/*.service "$ROOTFS/etc/systemd/system/"
chmod 0644 "$ROOTFS/etc/systemd/system/"*.service

# ── /usr/local/bin helpers ───────────────────────────────────────────────────
mkdir -p "$ROOTFS/usr/local/bin"
for f in ldroid-resize ldroid-login ldroid-getty ldroid-docs; do
    cp "/work/files/usr/local/bin/$f" "$ROOTFS/usr/local/bin/$f"
    chmod 0755 "$ROOTFS/usr/local/bin/$f"
done

# ldroid-vsock-agent is COPY'd in from the helper-builder Docker stage.  Make
# sure it's executable (cross-arch COPY can lose the mode bit on some buildkit
# versions).
chmod +x "$ROOTFS/usr/local/bin/ldroid-vsock-agent" 2>/dev/null || true
# ldroid-hostd is also COPY'd from the helper-builder stage; same mode-bit
# guard.  The CLIs are argv[0]-dispatch symlinks onto the one multi-call binary.
chmod +x "$ROOTFS/usr/local/bin/ldroid-hostd" 2>/dev/null || true
# ldroid-overlay-normalize is COPY'd from the helper-builder stage.
chmod +x "$ROOTFS/usr/local/bin/ldroid-overlay-normalize" 2>/dev/null || true
ln -sf ldroid-hostd "$ROOTFS/usr/local/bin/ldroid-notify"
ln -sf ldroid-hostd "$ROOTFS/usr/local/bin/ldroid-forward"
ln -sf ldroid-hostd "$ROOTFS/usr/local/bin/ldroid-open"
ln -sf ldroid-hostd "$ROOTFS/usr/local/bin/ldroid-power"
ln -sf ldroid-hostd "$ROOTFS/usr/local/bin/ldroid-headless"
ln -sf ldroid-hostd "$ROOTFS/usr/local/bin/ldroid-server"
ln -sf ldroid-hostd "$ROOTFS/usr/local/bin/ldroid-phone-ip"
chmod +x "$ROOTFS/usr/local/bin/ldroid-"*

# vsock agent's initial forward table (read at ldroid-vsock startup).
mkdir -p "$ROOTFS/etc/ldroid"
cp /work/files/etc/ldroid/forwards.conf "$ROOTFS/etc/ldroid/forwards.conf"
chmod 0644 "$ROOTFS/etc/ldroid/forwards.conf"
# Migration scripts dir (seeded with its README; per-version <v>.sh added over
# time). Install every migration script so a new one needs no build edit.
mkdir -p "$ROOTFS/etc/ldroid/migrations"
cp /work/files/etc/ldroid/migrations/README "$ROOTFS/etc/ldroid/migrations/README"
for f in /work/files/etc/ldroid/migrations/*.sh; do
    [ -f "$f" ] || continue
    cp "$f" "$ROOTFS/etc/ldroid/migrations/"
    chmod 0755 "$ROOTFS/etc/ldroid/migrations/$(basename "$f")"
done
# System-version stamp: the migration anchor. Baked from the app versionCode at
# build time; compared against /mnt/persist/.ldroid/applied-version at boot.
printf '%s\n' "${SYSTEM_VERSION:-0}" > "$ROOTFS/etc/ldroid/system-version"
chmod 0644 "$ROOTFS/etc/ldroid/system-version"

# ── profile.d / docs ─────────────────────────────────────────────────────────
# /etc/profile.d/*.sh — sourced by Debian's /etc/profile in login shells.
mkdir -p "$ROOTFS/etc/profile.d"
cp /work/files/etc/profile.d/ldroid-color.sh "$ROOTFS/etc/profile.d/"
cp /work/files/etc/profile.d/ldroid-x11.sh   "$ROOTFS/etc/profile.d/"
chmod 0644 "$ROOTFS/etc/profile.d/ldroid-color.sh" "$ROOTFS/etc/profile.d/ldroid-x11.sh"

# Offline copy of the docs/guide site, staged into /work/docs-guide by
# build_rootfs() in build-all.sh (this must run after the "Strip docs" rm -rf
# above, or mksquashfs would ship nothing here). Served in-guest by
# ldroid-docs.
mkdir -p "$ROOTFS/usr/share/doc/ldroid"
cp /work/docs-guide/*.html /work/docs-guide/style.css "$ROOTFS/usr/share/doc/ldroid/"
chmod 0644 "$ROOTFS/usr/share/doc/ldroid/"*

# ── Host identity and locale ─────────────────────────────────────────────────
echo "ldroid" > "$ROOTFS/etc/hostname"
echo "127.0.0.1 localhost ldroid" > "$ROOTFS/etc/hosts"
echo "::1 localhost ip6-localhost" >> "$ROOTFS/etc/hosts"
printf 'LANG=C.UTF-8\n' > "$ROOTFS/etc/locale.conf"\nmkdir -p "$ROOTFS/etc/default"\nprintf 'LANG=C.UTF-8\n' > "$ROOTFS/etc/default/locale"

# Debian's glibc resolver; ldroid-network rewrites this at boot with the
# device-provided resolvers.  Keep a working fallback baked into the image.
rm -f "$ROOTFS/etc/resolv.conf"
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$ROOTFS/etc/resolv.conf"

# Login banner shown by agetty before the login prompt.
# \S=Debian release, \r=kernel, \m=arch, \l=tty
cat > "$ROOTFS/etc/issue" <<'EOF'
Welcome to LDroid (Debian \S)
Kernel \r on \m (\l)

  Default login:  root  /  ldroid
  Change root password:    passwd
  Create a regular user:   adduser <name>

EOF

# ── systemd enablement (host is aarch64, but we never boot it) ───────────────
mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants" \
         "$ROOTFS/etc/systemd/system/sockets.target.wants"

enable_ldroid_unit() {
    svc="$1"
    ln -sf "/etc/systemd/system/${svc}.service" \
        "$ROOTFS/etc/systemd/system/multi-user.target.wants/${svc}.service"
}

for svc in ldroid-migrate ldroid-bootstrap ldroid-network ldroid-resize \
           ldroid-vsock ldroid-downloads ldroid-hostd ldroid-xvnc \
           ldroid-pulseaudio ldroid-ready; do
    enable_ldroid_unit "$svc"
done

# Console getty instances.  The wrapper picks the tty named by ldroid.tty=;
# the other instance sleeps forever, exactly like the old console getty lines.
ln -sf /etc/systemd/system/ldroid-getty@.service \
    "$ROOTFS/etc/systemd/system/multi-user.target.wants/ldroid-getty@hvc0.service"
ln -sf /etc/systemd/system/ldroid-getty@.service \
    "$ROOTFS/etc/systemd/system/multi-user.target.wants/ldroid-getty@ttyS0.service"

# Enable stock Debian units we still use.  Everything else is left at the
# package default (or masked below).
enable_stock_unit() {
    name="$1"
    target="$2"
    unit_path=""
    for candidate in "$ROOTFS/etc/systemd/system/$name" "$ROOTFS/lib/systemd/system/$name" \
                     "$ROOTFS/usr/lib/systemd/system/$name"; do
        [ -e "$candidate" ] && { unit_path="$candidate"; break; }
    done
    [ -n "$unit_path" ] || return 0
    mkdir -p "$ROOTFS/etc/systemd/system/$target.wants"
    ln -sf "/lib/systemd/system/$name" "$ROOTFS/etc/systemd/system/$target.wants/$name"
}

enable_stock_unit dropbear.service multi-user.target
enable_stock_unit dbus.socket sockets.target
enable_stock_unit dbus.service multi-user.target

# LDroid owns the console gettys and starts X/pulseaudio itself.  Mask the
# Debian defaults so the systemd getty generator and the package units don't
# race us on the same devices/ports.
mask_unit() {
    ln -sf /dev/null "$ROOTFS/etc/systemd/system/$1"
}
for unit in getty@tty1.service getty@ttyAMA0.service getty@hvc0.service \
            serial-getty@ttyAMA0.service serial-getty@ttyS0.service serial-getty@hvc0.service \
            pulseaudio.service pulseaudio.socket systemd-firstboot.service; do
    mask_unit "$unit"
done

# Boot straight into multi-user; there is no display manager in the guest.
ln -sf /lib/systemd/system/multi-user.target "$ROOTFS/etc/systemd/system/default.target"

# Empty machine-id is generated on first boot and persisted in the overlay.
: > "$ROOTFS/etc/machine-id"

# Generate dropbear host keys at build time so SSH works on the very first
# boot (the package's chroot postinst cannot always do this under debootstrap).
mkdir -p "$ROOTFS/etc/dropbear"
if [ ! -s "$ROOTFS/etc/dropbear/dropbear_ed25519_host_key" ]; then
    chroot "$ROOTFS" dropbearkey -t ed25519 \
        -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1 || true
fi
if [ ! -s "$ROOTFS/etc/dropbear/dropbear_rsa_host_key" ]; then
    chroot "$ROOTFS" dropbearkey -t rsa -s 3072 \
        -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
fi

# ── Final cleanup ────────────────────────────────────────────────────────────
rm -rf "$ROOTFS/var/lib/apt/lists"/* "$ROOTFS/var/cache/apt"/* \
       "$ROOTFS/tmp"/* "$ROOTFS/var/tmp"/* "$ROOTFS/var/log"/*
