#!/bin/sh
set -eu
ROOTFS=/work/rootfs

# ALPINE_VERSION comes from the Dockerfile ENV (full release like 3.24.1).
# Strip the patch component to get the major branch (e.g. 3.24) used in repo URLs.
: "${ALPINE_VERSION:?ALPINE_VERSION must be set (e.g. 3.24.1)}"
ALPINE_BRANCH="${ALPINE_VERSION%.*}"

mkdir -p "$ROOTFS/etc/apk"
cat > "$ROOTFS/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/community
EOF

apk -X "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/main" \
    -X "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/community" \
    -U --allow-untrusted --root "$ROOTFS" --initdb add \
    alpine-base \
    openrc \
    busybox-openrc \
    busybox-extras \
    bash \
    podman \
    docker docker-openrc docker-cli-compose \
    lxc lxc-templates lxc-download lxc-openrc lxc-bridge \
    crun \
    fuse-overlayfs \
    iptables \
    ip6tables \
    nftables \
    bridge-utils \
    iproute2 \
    dropbear dropbear-openrc \
    openssh-sftp-server \
    curl \
    ca-certificates \
    shadow shadow-uidmap \
    slirp4netns \
    aardvark-dns netavark \
    libcap-utils \
    doas sudo \
    gcompat \
    gzip \
    xz \
    tigervnc \
    pulseaudio \
    pulseaudio-utils \
    font-misc-misc \
    font-cursor-misc \
    ttf-dejavu

# Apply file capabilities to newuidmap/newgidmap. apk's package install often
# does this, but we set them explicitly so the squashfs ships with the
# correct security.capability xattr (preserved by mksquashfs without -no-xattrs).
if command -v setcap >/dev/null 2>&1; then
    setcap cap_setuid+ep "$ROOTFS/usr/bin/newuidmap"
    setcap cap_setgid+ep "$ROOTFS/usr/bin/newgidmap"
fi

# Ensure doas and sudo are setuid-root. apk usually does this, but on
# overlay-mounted build hosts it can silently fail.
chmod u+s "$ROOTFS/usr/bin/doas"  2>/dev/null || true
chmod u+s "$ROOTFS/usr/bin/sudo"  2>/dev/null || true

# doas: members of the `wheel` group can become root after entering their
# password (cached for ~5 min). Standard *BSD/Alpine convention.
mkdir -p "$ROOTFS/etc/doas.d"
echo "permit persist :wheel" > "$ROOTFS/etc/doas.d/doas.conf"
chmod 0400 "$ROOTFS/etc/doas.d/doas.conf"

# sudo: equivalent rule for users who prefer sudo over doas.
mkdir -p "$ROOTFS/etc/sudoers.d"
echo "%wheel ALL=(ALL) ALL" > "$ROOTFS/etc/sudoers.d/wheel"
chmod 0440 "$ROOTFS/etc/sudoers.d/wheel"

# Set root password to "ldroid" (pre-hashed with openssl).
# We can't run chpasswd inside the aarch64 rootfs from an x86_64 host,
# so write the SHA-512 hash directly into /etc/shadow.
# No fixed -salt: openssl generates a random salt so the stored hash differs
# per build (the password stays the documented default "ldroid").
ROOT_HASH=$(openssl passwd -6 ldroid)
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"

# Strip docs/man/locale to shrink squashfs
rm -rf "$ROOTFS/usr/share/man" "$ROOTFS/usr/share/doc" \
       "$ROOTFS/usr/share/locale" "$ROOTFS/usr/share/info"

# Remove the stock pulseaudio OpenRC service. Ldroid starts pulseaudio
# directly from ldroid-x11 (start-stop-daemon), never as a service; left in
# place its depend() pulls in a non-existent "udev" service, so OpenRC logs
# "Service 'pulseaudio' needs non existent service 'udev'" on every boot.
rm -f "$ROOTFS/etc/init.d/pulseaudio"

# Pre-create podman storage dirs (saves first-boot mkdir)
mkdir -p "$ROOTFS/var/lib/containers/storage" \
         "$ROOTFS/run/containers/storage" \
         "$ROOTFS/run/libpod" \
         "$ROOTFS/run/crun"

# Copy custom service files into the rootfs
cp /work/files/etc/init.d/ldroid-bootstrap "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/ldroid-network   "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/ldroid-resize    "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/ldroid-ready     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/ldroid-x11       "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/ldroid-vsock     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/ldroid-hostd     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/ldroid-downloads "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/ldroid-migrate   "$ROOTFS/etc/init.d/"
chmod +x "$ROOTFS/etc/init.d/ldroid-"*

# Copy /usr/local/bin scripts (resize daemon + login wrapper + getty selector)
mkdir -p "$ROOTFS/usr/local/bin"
cp /work/files/usr/local/bin/ldroid-resize "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/ldroid-login  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/ldroid-getty  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/ldroid-backup "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/ldroid-docs   "$ROOTFS/usr/local/bin/"
# ldroid-vsock-agent is COPY'd in from the vsock-builder Docker stage. Make
# sure it's executable (cross-arch COPY can lose the mode bit on some buildkit
# versions).
chmod +x "$ROOTFS/usr/local/bin/ldroid-vsock-agent" 2>/dev/null || true
# ldroid-hostd is also COPY'd from the vsock-builder stage; same mode-bit guard.
# The CLIs are argv[0]-dispatch symlinks onto the one multi-call binary.
chmod +x "$ROOTFS/usr/local/bin/ldroid-hostd" 2>/dev/null || true
# ldroid-overlay-normalize is COPY'd from the vsock-builder stage; mode-bit guard.
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
# Migration scripts dir (seeded with its README; per-version <v>.sh added over time).
mkdir -p "$ROOTFS/etc/ldroid/migrations"
cp /work/files/etc/ldroid/migrations/README "$ROOTFS/etc/ldroid/migrations/README"
# Install every migration script so a new one needs no build-script edit.
for f in /work/files/etc/ldroid/migrations/*.sh; do
    [ -f "$f" ] || continue
    cp "$f" "$ROOTFS/etc/ldroid/migrations/"
    chmod 0755 "$ROOTFS/etc/ldroid/migrations/$(basename "$f")"
done
# System-version stamp: the migration anchor. Baked from the app versionCode at
# build time; compared against /mnt/persist/.ldroid/applied-version at boot.
printf '%s\n' "${SYSTEM_VERSION:-0}" > "$ROOTFS/etc/ldroid/system-version"
chmod 0644 "$ROOTFS/etc/ldroid/system-version"
cp /work/files/etc/inittab "$ROOTFS/etc/inittab"
cp /work/files/etc/rc.conf "$ROOTFS/etc/rc.conf"

# /etc/profile.d/*.sh — sourced by Alpine's /etc/profile in login shells.
# ldroid-color.sh: COLORTERM=truecolor (24-bit color). ldroid-x11.sh:
# DISPLAY / PULSE_SERVER for the in-app GUI viewer. Copy by explicit name so
# a renamed/removed asset fails the build (set -e) instead of silently
# shipping a squashfs without these exports.
mkdir -p "$ROOTFS/etc/profile.d"
cp /work/files/etc/profile.d/ldroid-color.sh "$ROOTFS/etc/profile.d/"
cp /work/files/etc/profile.d/ldroid-x11.sh   "$ROOTFS/etc/profile.d/"
chmod 0644 "$ROOTFS/etc/profile.d/ldroid-color.sh" "$ROOTFS/etc/profile.d/ldroid-x11.sh"

# /etc/containers/storage.conf — pin Podman to the in-kernel overlay driver.
# Without this file, Podman auto-detects fuse-overlayfs (still apk-installed
# as a fallback) and uses it, which is slower than native overlay.
mkdir -p "$ROOTFS/etc/containers"
cp /work/files/etc/containers/storage.conf "$ROOTFS/etc/containers/storage.conf"
chmod 0644 "$ROOTFS/etc/containers/storage.conf"

# Offline copy of the docs/guide site, staged into /work/docs-guide by
# build_rootfs() in build-all.sh (this must run after the "Strip docs" rm -rf
# above, or mksquashfs would ship nothing here). Served in-guest by
# ldroid-docs.
mkdir -p "$ROOTFS/usr/share/doc/ldroid"
cp /work/docs-guide/*.html /work/docs-guide/style.css "$ROOTFS/usr/share/doc/ldroid/"
chmod 0644 "$ROOTFS/usr/share/doc/ldroid/"*

# Hostname (read by ldroid-bootstrap via `hostname -F /etc/hostname`)
echo "ldroid" > "$ROOTFS/etc/hostname"
echo "127.0.0.1 localhost ldroid" > "$ROOTFS/etc/hosts"
echo "::1 localhost ip6-localhost" >> "$ROOTFS/etc/hosts"

# Login banner shown by getty before the login prompt.
# \S=Alpine release, \r=kernel, \m=arch, \l=tty
cat > "$ROOTFS/etc/issue" <<'EOF'
Welcome to Ldroid (Alpine \S)
Kernel \r on \m (\l)

  Default login:  root  /  ldroid
  Change root password:    passwd
  Create a regular user:   adduser -G wheel <name>
                           (wheel group → can run doas/sudo)

EOF

# Set runlevels via direct symlinks (host is x86_64, can't chroot into aarch64 rootfs to run rc-update).
# rc-update is just `ln -s /etc/init.d/X /etc/runlevels/<level>/X` under the hood.
mkdir -p "$ROOTFS/etc/runlevels/default" "$ROOTFS/etc/runlevels/boot"
# Guard each link: a dangling symlink (e.g. dnsmasq.lxcbr0, which lxc-bridge
# may ship only as dnsmasq config and not an init script) makes OpenRC log
# an error every boot and stalls ldroid-ready's `after *` on a phantom.
for svc in ldroid-migrate ldroid-bootstrap ldroid-network ldroid-resize dropbear docker lxc dnsmasq.lxcbr0 ldroid-x11 ldroid-vsock ldroid-downloads ldroid-hostd ldroid-ready; do
    if [ -e "$ROOTFS/etc/init.d/$svc" ]; then
        ln -sf "/etc/init.d/$svc" "$ROOTFS/etc/runlevels/default/$svc"
    else
        echo "WARN: init script /etc/init.d/$svc missing, skipping runlevel symlink"
    fi
done

# Disable services we don't need (initramfs already handles them, or they're noise in the VM)
for svc in hwclock swclock urandom networking sysctl bootmisc syslog; do
    rm -f "$ROOTFS/etc/runlevels/boot/$svc" "$ROOTFS/etc/runlevels/default/$svc"
done
