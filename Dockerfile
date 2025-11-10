FROM --platform=$BUILDPLATFORM rockylinux:9

# Build args (defaults)
ARG CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
ARG SDK_TOOLS_DIR="/opt/android-sdk"
ARG TARGETPLATFORM

# Single canonical SDK location
ENV ANDROID_SDK_ROOT=${SDK_TOOLS_DIR}

# PATH (one ENV per line)
ENV PATH=${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/emulator:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Runtime defaults (one ENV per line)
ENV AVD_NAME="demo"
ENV ANDROID_API="36"
ENV IMAGE_TYPE="google_apis"
ENV IMAGE_ARCH=""
ENV AVD_MEMORY="4096"
ENV EMULATOR_EXTRA_ARGS=""
ENV SKIP_SDK_UPDATE="1"
ENV VNC_ENABLE="0"
ENV VNC_PASSWORD=""

# Install runtime packages and Java 17, plus required VNC/noVNC dependencies.
# VNC support is mandatory: dnf errors will surface if packages cannot be installed.
RUN <<'INSTALL_DEPS'
set -eux

# Basic update and EPEL
dnf -y update
dnf -y install epel-release dnf-plugins-core

# Base runtime packages and JDK17 (do not install curl here)
dnf -y install unzip tar which git java-17-openjdk-headless \
    ca-certificates \
    libXrandr libXcursor libXinerama libXcomposite libXdamage \
    mesa-libGL mesa-libEGL mesa-libgbm alsa-lib pulseaudio-libs libX11 \
    glibc-langpack-en xorg-x11-server-Xvfb python3 python3-pip

# Install openbox (WM) and VNC server (required). Let dnf surface its own errors if installation fails.
dnf -y install openbox x11vnc tigervnc-server

# Install websockify (noVNC backend) via pip; allow pip errors to surface.
pip3 install --no-cache-dir websockify==0.11.0

# Mark image as VNC-capable for runtime checks
mkdir -p /etc/android-emulator
echo "1" > /etc/android-emulator/vnc_supported
echo "openbox" > /etc/android-emulator/vnc_wm
echo "x11vnc,tigervnc-server" > /etc/android-emulator/vnc_server

# Clean caches
dnf clean all
rm -rf /var/cache/dnf /var/tmp/*
INSTALL_DEPS

# Download Android commandline tools and place into SDK tree.
# Require curl to be present in base image; allow curl's own error output if missing or download fails.
RUN <<'FETCH_CMDLINE'
set -eux
command -v curl >/dev/null 2>&1 || { echo "[build][error] curl not found in base image; required to download Android commandline tools."; exit 1; }
mkdir -p "${ANDROID_SDK_ROOT}"
cd /tmp
curl -fsSL -o commandlinetools.zip "${CMDLINE_TOOLS_URL}"
unzip -q commandlinetools.zip -d /tmp/cmdline-tools-temp
mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
mv /tmp/cmdline-tools-temp/cmdline-tools "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
rm -rf /tmp/commandlinetools.zip /tmp/cmdline-tools-temp
FETCH_CMDLINE

# Clone noVNC frontend and websockify (let git errors surface)
RUN <<'CLONE_NOVNC'
set -eux
git clone --depth 1 https://github.com/novnc/noVNC.git /opt/noVNC
git clone --depth 1 https://github.com/novnc/websockify /opt/noVNC/utils/websockify
CLONE_NOVNC

# Install SDK components for the build target (platform-tools, emulator, platform, system-image).
RUN <<'INSTALL_SDK'
set -eux
case "${TARGETPLATFORM:-}" in
  "linux/arm64"|"linux/arm64/v8"|"linux/arm64/v8l"|"linux/arm64/v8a")
    IMAGE_ARCH="arm64-v8a"
    ;;
  *)
    IMAGE_ARCH="x86_64"
    ;;
esac
echo "Target: ${TARGETPLATFORM:-unknown} -> ABI: ${IMAGE_ARCH}"
SDKMANAGER="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
[ -x "${SDKMANAGER}" ]
mkdir -p /root/.android
: > /root/.android/repositories.cfg
# Accept licenses and update metadata; allow sdkmanager errors to surface
yes | "${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null || true
"${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" --update
"${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" "platform-tools" "emulator" "platforms;android-${ANDROID_API}" "system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH}"
INSTALL_SDK

# Create default AVD (demo) for the chosen ABI. export ANDROID_SDK_ROOT in same shell so avdmanager picks it up.
RUN <<'CREATE_AVD'
set -eux
mkdir -p "${ANDROID_SDK_ROOT}/.android"
case "${TARGETPLATFORM:-}" in
  "linux/arm64"*)
    IMAGE_ARCH_SEL="arm64-v8a"
    ;;
  *)
    IMAGE_ARCH_SEL="x86_64"
    ;;
esac
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
echo "Creating AVD 'demo' (ABI=${IMAGE_ARCH_SEL})"
echo "no" | avdmanager create avd -n "demo" -k "system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH_SEL}" --force
CREATE_AVD

# Create non-root user and set ownership of SDK, set writable permissions for SDK and create android HOME .android
RUN <<'SETUP_USER'
set -eux
useradd -m -u 1000 android || true

# Ensure SDK ownership and writable permissions
chown -R android:android "${ANDROID_SDK_ROOT}" /home/android || true
chmod -R u+rw "${ANDROID_SDK_ROOT}" || true

# Create android user .android dir and a placeholder emu-update-last-check.ini to avoid runtime warnings
mkdir -p /home/android/.android
touch /home/android/.android/emu-update-last-check.ini
chown -R android:android /home/android/.android || true
SETUP_USER

# Copy entrypoint and make executable
COPY start-emulator.sh /usr/local/bin/start-emulator.sh
RUN chmod +x /usr/local/bin/start-emulator.sh

USER android
WORKDIR /home/android

# Expose emulator / adb / VNC ports
EXPOSE 5554 5555 5037 5900 6080

ENTRYPOINT ["/usr/local/bin/start-emulator.sh"]