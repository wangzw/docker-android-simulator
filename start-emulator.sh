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
AVD_MEMORY="${AVD_MEMORY:-4096}"
EMULATOR_EXTRA_ARGS="${EMULATOR_EXTRA_ARGS:-}"
SKIP_SDK_UPDATE="${SKIP_SDK_UPDATE:-1}"

# gRPC control (explicit opt-in for unprotected gRPC)
# Set EMULATOR_GRPC=1 when running in a trusted environment to enable -grpc flag.
EMULATOR_GRPC="${EMULATOR_GRPC:-0}"

# VNC related
VNC_ENABLE="${VNC_ENABLE:-0}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
VNC_WIDTH="${VNC_WIDTH:-1280}"
VNC_HEIGHT="${VNC_HEIGHT:-720}"

echo "[entrypoint] AVD_NAME=${AVD_NAME}, ANDROID_API=${ANDROID_API}, IMAGE_TYPE=${IMAGE_TYPE}, IMAGE_ARCH=${IMAGE_ARCH}, AVD_MEMORY=${AVD_MEMORY}"
echo "[entrypoint] EMULATOR_EXTRA_ARGS='${EMULATOR_EXTRA_ARGS}' SKIP_SDK_UPDATE=${SKIP_SDK_UPDATE} VNC_ENABLE=${VNC_ENABLE} EMULATOR_GRPC=${EMULATOR_GRPC}"

# Ensure SDK dirs exist (do not change SDK permissions at runtime)
mkdir -p "${ANDROID_SDK_ROOT}/.android" "${ANDROID_SDK_ROOT}/platforms" "${ANDROID_SDK_ROOT}/system-images" || true

# Ensure repositories.cfg exists under the SDK root to avoid warnings from sdkmanager
: > "${ANDROID_SDK_ROOT}/.android/repositories.cfg" || true

# Start adb server early (best-effort)
if command -v adb >/dev/null 2>&1; then
  adb start-server || true
fi

SDKMANAGER="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"

# If requested, install platform & system image at container start
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
  echo "[entrypoint] Installing ${PLATFORM} ${SYSTEM_IMAGE} (this may take several minutes)..."
  "${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" "${PLATFORM}" "${SYSTEM_IMAGE}"
fi

# Detect installed ABI if not explicitly provided (robust parsing)
if [ -z "${IMAGE_ARCH}" ]; then
  echo "[entrypoint] IMAGE_ARCH not set, attempting to detect installed ABI..."
  INSTALLED=$("${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" --list_installed 2>/dev/null || true)

  ABI=""
  # Walk through lines that mention system-images and android-<API>, try to extract a clean ABI token.
  # We split tokens on common delimiters: ';' '/' '|' and whitespace, then pick the first token that matches a known ABI pattern.
  while IFS= read -r line; do
    case "${line}" in
      *system-images*android-"${ANDROID_API}"*) ;;
      *) continue ;;
    esac

    # Replace delimiters with newlines, iterate tokens
    tokens=$(printf "%s\n" "${line}" | sed 's/[;\/|]/\n/g')
    while IFS= read -r token; do
      # trim token
      token_trim=$(printf "%s" "${token}" | awk '{$1=$1; print}')
      case "${token_trim}" in
        arm64-v8a|x86_64|x86|armeabi-v7a)
          ABI="${token_trim}"
          break 2
          ;;
      esac
    done <<< "${tokens}"
  done <<< "${INSTALLED}"

  if [ -n "${ABI}" ]; then
    IMAGE_ARCH="${ABI}"
    echo "[entrypoint] Detected installed ABI: ${IMAGE_ARCH}"
  else
    echo "[entrypoint] No installed ABI found for API ${ANDROID_API}, defaulting to arm64-v8a"
    IMAGE_ARCH="arm64-v8a"
  fi
fi

SYSTEM_IMAGE_KEY="system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH}"

# Create AVD if it doesn't exist
AVD_DIR="${ANDROID_SDK_ROOT}/.android/avd/${AVD_NAME}.avd"
if [ -d "${AVD_DIR}" ]; then
  echo "[entrypoint] AVD '${AVD_NAME}' already exists."
else
  echo "[entrypoint] Creating AVD '${AVD_NAME}' using ${SYSTEM_IMAGE_KEY}..."
  export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
  # send "no" to optional prompts (SD card creation etc.)
  echo "no" | avdmanager create avd -n "${AVD_NAME}" -k "${SYSTEM_IMAGE_KEY}" --force
fi

# VNC setup: start Xvfb + window manager + x11vnc + noVNC (websockify) if requested
if [ "${VNC_ENABLE}" = "1" ]; then
  echo "[vnc] Enabling VNC/noVNC..."
  Xvfb :0 -screen 0 "${VNC_WIDTH}x${VNC_HEIGHT}x24" -nolisten tcp >/dev/null 2>&1 &
  export DISPLAY=":0"
  # start window manager (openbox)
  if command -v openbox >/dev/null 2>&1; then
    openbox >/dev/null 2>&1 &
  else
    echo "[vnc] openbox not found; VNC may not function correctly." >&2
  fi

  # Prepare VNC password if provided
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
  echo "[vnc] VNC disabled (VNC_ENABLE != 1). Emulator will run headless by default."
fi

# If EMULATOR_GRPC=1 or user explicitly put -grpc in EMULATOR_EXTRA_ARGS, enable grpc.
# NOTE: enabling -grpc opens an unprotected gRPC port (security risk). Only set EMULATOR_GRPC=1 in trusted environments.
if [ "${EMULATOR_GRPC}" = "1" ] || printf "%s" "${EMULATOR_EXTRA_ARGS}" | grep -Eq '(^|[[:space:]])-grpc\b'; then
  # append -grpc only if not already present
  if ! printf "%s" "${EMULATOR_EXTRA_ARGS}" | grep -Eq '(^|[[:space:]])-grpc\b'; then
    EMULATOR_EXTRA_ARGS="${EMULATOR_EXTRA_ARGS} -grpc"
  fi
  echo "[grpc] gRPC enabled (open/unprotected). Ensure this container is in a trusted network."
else
  # do not add -no-grpc by force; respect explicit -no-grpc if user provided it.
  echo "[grpc] gRPC not explicitly enabled; emulator will run without opening an unprotected gRPC port."
fi

# Build emulator args
if [ "${VNC_ENABLE}" = "1" ]; then
  COMMON_ARGS="-no-audio -gpu swiftshader_indirect -accel off -memory ${AVD_MEMORY} -no-snapshot -partition-size 200"
else
  COMMON_ARGS="-no-window -no-audio -gpu swiftshader_indirect -accel off -memory ${AVD_MEMORY} -no-snapshot -partition-size 200"
fi

FULL_ARGS="${COMMON_ARGS} ${EMULATOR_EXTRA_ARGS}"

echo "[entrypoint] Launching emulator '${AVD_NAME}' with args: ${FULL_ARGS}"
exec "${ANDROID_SDK_ROOT}/emulator/emulator" -avd "${AVD_NAME}" ${FULL_ARGS}