#!/usr/bin/env bash
set -euo pipefail

# Canonical SDK root
ANDROID_SDK_ROOT="/opt/android-sdk"
export ANDROID_SDK_ROOT
export PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/emulator:${PATH}"

# Runtime variables (can be overridden by docker run -e ...)
AVD_NAME="${AVD_NAME:-demo}"
ANDROID_API="${ANDROID_API:-36}"
IMAGE_TYPE="${IMAGE_TYPE:-google_apis}"
IMAGE_ARCH="${IMAGE_ARCH:-}"    # if empty, detect or default
AVD_MEMORY="${AVD_MEMORY:-2048}"
EMULATOR_EXTRA_ARGS="${EMULATOR_EXTRA_ARGS:-}"
SKIP_SDK_UPDATE="${SKIP_SDK_UPDATE:-1}"

# VNC related
VNC_ENABLE="${VNC_ENABLE:-0}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
VNC_WIDTH="${VNC_WIDTH:-1280}"
VNC_HEIGHT="${VNC_HEIGHT:-720}"

echo "[entrypoint] AVD_NAME=${AVD_NAME}, ANDROID_API=${ANDROID_API}, IMAGE_TYPE=${IMAGE_TYPE}, IMAGE_ARCH=${IMAGE_ARCH}, AVD_MEMORY=${AVD_MEMORY}"
echo "[entrypoint] EMULATOR_EXTRA_ARGS='${EMULATOR_EXTRA_ARGS}' SKIP_SDK_UPDATE=${SKIP_SDK_UPDATE} VNC_ENABLE=${VNC_ENABLE}"

# Ensure SDK dirs exist and are writable
mkdir -p "${ANDROID_SDK_ROOT}/.android" "${ANDROID_SDK_ROOT}/platforms" "${ANDROID_SDK_ROOT}/system-images"
chmod -R u+rw "${ANDROID_SDK_ROOT}" || true

# Ensure repositories.cfg exists to avoid sdkmanager warnings
mkdir -p /root/.android || true
: > /root/.android/repositories.cfg || true

# Start adb server early (best-effort)
if command -v adb >/dev/null 2>&1; then
  adb start-server || true
fi

SDKMANAGER="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"

# Optionally install platform & system image at runtime (controlled by SKIP_SDK_UPDATE)
if [ "${SKIP_SDK_UPDATE}" != "1" ]; then
  echo "[entrypoint] Ensuring required SDK components are installed at runtime..."
  yes | "${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null || true
  if [ -z "${IMAGE_ARCH}" ]; then
    uname_m=$(uname -m || echo "")
    case "${uname_m}" in
      aarch64|arm64) IMAGE_ARCH="arm64-v8a" ;;
      *) IMAGE_ARCH="x86_64" ;;
    esac
  fi
  SYSTEM_IMAGE="system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH}"
  PLATFORM="platforms;android-${ANDROID_API}"
  echo "[entrypoint] Installing ${PLATFORM} ${SYSTEM_IMAGE}..."
  "${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" "${PLATFORM}" "${SYSTEM_IMAGE}"
fi

# Detect installed ABI if not explicitly provided
if [ -z "${IMAGE_ARCH}" ]; then
  echo "[entrypoint] IMAGE_ARCH not set, attempting to detect installed ABI..."
  INSTALLED=$("${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" --list_installed 2>/dev/null || true)
  ABI=$(printf "%s\n" "${INSTALLED}" | awk -F';' '/system-images;android-'"${ANDROID_API}"'/ {print $4; exit}')
  if [ -n "${ABI}" ]; then
    IMAGE_ARCH="${ABI}"
    echo "[entrypoint] Detected installed ABI: ${IMAGE_ARCH}"
  else
    echo "[entrypoint] No installed ABI found for API ${ANDROID_API}, defaulting to arm64-v8a"
    IMAGE_ARCH="arm64-v8a"
  fi
fi

SYSTEM_IMAGE_KEY="system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH}"

# Create AVD if missing
AVD_DIR="${ANDROID_SDK_ROOT}/.android/avd/${AVD_NAME}.avd"
if [ -d "${AVD_DIR}" ]; then
  echo "[entrypoint] AVD '${AVD_NAME}' already exists."
else
  echo "[entrypoint] Creating AVD '${AVD_NAME}' using ${SYSTEM_IMAGE_KEY}..."
  export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
  echo "no" | avdmanager create avd -n "${AVD_NAME}" -k "${SYSTEM_IMAGE_KEY}" --force
fi

# VNC setup: Xvfb + openbox + x11vnc + noVNC (websockify)
if [ "${VNC_ENABLE}" = "1" ]; then
  echo "[vnc] Enabling VNC/noVNC..."
  Xvfb :0 -screen 0 "${VNC_WIDTH}x${VNC_HEIGHT}x24" -nolisten tcp >/dev/null 2>&1 &
  export DISPLAY=":0"
  openbox >/dev/null 2>&1 &

  # VNC password file if available
  if [ -n "${VNC_PASSWORD}" ]; then
    mkdir -p /tmp/.vnc
    if command -v vncpasswd >/dev/null 2>&1; then
      echo "${VNC_PASSWORD}" | vncpasswd -f > /tmp/.vnc/passwd || true
      chmod 600 /tmp/.vnc/passwd || true
      VNC_AUTH_ARGS="-rfbauth /tmp/.vnc/passwd"
    else
      echo "[vnc] vncpasswd not found; continuing without password (insecure)" >&2
      VNC_AUTH_ARGS=""
    fi
  else
    VNC_AUTH_ARGS=""
  fi

  if command -v x11vnc >/dev/null 2>&1; then
    x11vnc -display :0 -forever -shared -rfbport 5900 ${VNC_AUTH_ARGS} >/dev/null 2>&1 &
  else
    echo "[vnc] x11vnc not available; install x11vnc/tigervnc on image for VNC support." >&2
  fi

  if [ -d /opt/noVNC ]; then
    if command -v websockify >/dev/null 2>&1; then
      websockify --web=/opt/noVNC 6080 localhost:5900 >/dev/null 2>&1 &
    elif [ -x /opt/noVNC/utils/websockify/run ]; then
      /opt/noVNC/utils/websockify/run 6080 localhost:5900 >/dev/null 2>&1 &
    else
      echo "[vnc] noVNC/websockify not runnable; check /opt/noVNC" >&2
    fi
  fi
else
  echo "[vnc] VNC disabled (VNC_ENABLE != 1). Emulator will run headless."
fi

# Build emulator args (GUI if VNC enabled; headless otherwise)
if [ "${VNC_ENABLE}" = "1" ]; then
  COMMON_ARGS="-no-audio -gpu swiftshader_indirect -accel off -memory ${AVD_MEMORY} -no-snapshot -partition-size 200"
else
  COMMON_ARGS="-no-window -no-audio -gpu swiftshader_indirect -accel off -memory ${AVD_MEMORY} -no-snapshot -partition-size 200"
fi

FULL_ARGS="${COMMON_ARGS} ${EMULATOR_EXTRA_ARGS}"

echo "[entrypoint] Launching emulator '${AVD_NAME}' with args: ${FULL_ARGS}"
exec "${ANDROID_SDK_ROOT}/emulator/emulator" -avd "${AVD_NAME}" ${FULL_ARGS}
