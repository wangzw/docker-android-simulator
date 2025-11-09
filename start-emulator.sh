#!/usr/bin/env bash
# start-emulator.sh
# Entrypoint that starts the headless Android emulator.
# Respects environment variables to override AVD name, API, ABI and memory.

set -euo pipefail

ANDROID_SDK_ROOT="/opt/android-sdk"
export ANDROID_SDK_ROOT
export ANDROID_SDK_HOME="${ANDROID_SDK_ROOT}"
export PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/emulator:${PATH}"

AVD_NAME="${AVD_NAME:-demo}"
ANDROID_API="${ANDROID_API:-33}"
IMAGE_TYPE="${IMAGE_TYPE:-google_apis}"
IMAGE_ARCH="${IMAGE_ARCH:-}"    # if empty, script will try to infer from installed system images
AVD_MEMORY="${AVD_MEMORY:-2048}"
EMULATOR_EXTRA_ARGS="${EMULATOR_EXTRA_ARGS:-}"
SKIP_SDK_UPDATE="${SKIP_SDK_UPDATE:-1}"

echo "[entrypoint] AVD_NAME=${AVD_NAME}, ANDROID_API=${ANDROID_API}, IMAGE_TYPE=${IMAGE_TYPE}, IMAGE_ARCH=${IMAGE_ARCH}, AVD_MEMORY=${AVD_MEMORY}"
echo "[entrypoint] EMULATOR_EXTRA_ARGS='${EMULATOR_EXTRA_ARGS}' SKIP_SDK_UPDATE=${SKIP_SDK_UPDATE}"

# Ensure writable dirs
mkdir -p "${ANDROID_SDK_ROOT}/.android"
chmod -R u+rw "${ANDROID_SDK_ROOT}"

# Start adb server
adb start-server || true

# If requested, ensure platform & system image installed
if [ "${SKIP_SDK_UPDATE}" != "1" ]; then
  echo "[entrypoint] Ensuring SDK components are installed..."
  yes | sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null || true
  SYSTEM_IMAGE="system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH}"
  PLATFORM="platforms;android-${ANDROID_API}"
  echo "[entrypoint] Installing ${PLATFORM} ${SYSTEM_IMAGE}..."
  sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" "${PLATFORM}" "${SYSTEM_IMAGE}"
else
  echo "[entrypoint] SKIP_SDK_UPDATE=1, skipping sdkmanager install (image pre-baked or provided)."
fi

# If IMAGE_ARCH not provided, try to detect an installed system-image ABI for requested API
if [ -z "${IMAGE_ARCH}" ]; then
  echo "[entrypoint] IMAGE_ARCH not set, attempting to detect installed ABI..."
  # list installed system-images and grep for matching API
  INSTALLED=$(sdkmanager --list_installed --sdk_root="${ANDROID_SDK_ROOT}" 2>/dev/null || true)
  ABI=$(printf "%s\n" "${INSTALLED}" | awk -F';' '/system-images;android-'"${ANDROID_API}"'/ {print $4; exit}')
  if [ -n "${ABI}" ]; then
    IMAGE_ARCH="${ABI}"
    echo "[entrypoint] Detected installed ABI: ${IMAGE_ARCH}"
  else
    echo "[entrypoint] Could not detect ABI for API ${ANDROID_API}; defaulting to arm64-v8a if available"
    IMAGE_ARCH="arm64-v8a"
  fi
fi

SYSTEM_IMAGE_KEY="system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH}"

# Create AVD if missing
AVD_DIR="${ANDROID_SDK_ROOT}/.android/avd/${AVD_NAME}.avd"
if [ -d "${AVD_DIR}" ]; then
  echo "[entrypoint] AVD '${AVD_NAME}' already exists."
else
  echo "[entrypoint] Creating AVD '${AVD_NAME}' with key ${SYSTEM_IMAGE_KEY}..."
  echo "no" | avdmanager --sdk_root="${ANDROID_SDK_ROOT}" create avd -n "${AVD_NAME}" -k "${SYSTEM_IMAGE_KEY}" --force
fi

# Compose emulator args (software rendering for portability)
COMMON_ARGS="-no-window -no-audio -gpu swiftshader_indirect -accel off -memory ${AVD_MEMORY} -no-snapshot -partition-size 200"
FULL_ARGS="${COMMON_ARGS} ${EMULATOR_EXTRA_ARGS}"

echo "[entrypoint] Launching emulator '${AVD_NAME}' with args: ${FULL_ARGS}"

# Exec emulator as PID 1
exec "${ANDROID_SDK_ROOT}/emulator/emulator" -avd "${AVD_NAME}" ${FULL_ARGS}