#!/usr/bin/env bash

set -euox pipefail

function detect_os() {
  if [[ -n "${OSTYPE-}" ]]; then
    case "$OSTYPE" in
      darwin*) printf '%s\n' "mac"; return;;
      linux*)  printf '%s\n' "linux"; return;;
    esac
  fi

  uname_out="$(uname -s 2>/dev/null || true)"
  case "$uname_out" in
    Darwin) printf '%s\n' "mac";;
    Linux)  printf '%s\n' "linux";;
    *)      printf '%s\n' "unknown: %s" "$uname_out";;
  esac
}

function detect_android_arch() {
  local arch
  arch="$(uname -m 2>/dev/null || true)"
  case "$arch" in
    arm64|aarch64) printf '%s\n' "arm64-v8a";;
    x86_64|amd64)   printf '%s\n' "x86_64";;
    *)              printf 'unknown: %s\n' "$arch";;
  esac
}

function download_sdk_tools() {
  local url=$1
  local sdk_path=$2
  curl -sSfL -o commandlinetools.zip -C - ${url}

  unzip -oq commandlinetools.zip -d cmdline-tools-temp
  mkdir -p "${sdk_path}/cmdline-tools"
  rm -rf "${sdk_path}/cmdline-tools/latest"
  mv cmdline-tools-temp/cmdline-tools "${sdk_path}/cmdline-tools/latest"
  rm -rf commandlinetools.zip cmdline-tools-temp

  cat <<EOF >~/.android_env.sh
# Android SDK Command Line Tools
export ANDROID_SDK_ROOT="${sdk_path}"
EOF

  cat <<'EOF' >>~/.android_env.sh
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools:$PATH"
EOF
}

function download_sdk_tools_homebrew() {
  local sdk_path
  sdk_path="$(brew --prefix)/share/android-commandlinetools"

  brew install --cask android-commandlinetools

  cat <<EOF >~/.android_env.sh
# Android SDK Command Line Tools
export ANDROID_SDK_ROOT="${sdk_path}"
EOF

  cat <<'EOF' >>~/.android_env.sh
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools:$PATH"
EOF
}

function install_platform_tools() {
  local android_api_version=$1
  (
    export JAVA_OPTS="--enable-native-access=ALL-UNNAMED"
    source "${HOME}/.android_env.sh"
    yes | sdkmanager --licenses >/dev/null 2>&1 ||:
    sdkmanager "platform-tools" "emulator" "platforms;android-${android_api_version}"
  )
}

function install_android_image() {
  local android_api_version=$1
  local android_image_type=$2
  local android_arch
  android_arch="$(detect_android_arch)"
  (
    export JAVA_OPTS="--enable-native-access=ALL-UNNAMED"
    source "${HOME}/.android_env.sh"
    yes | sdkmanager --licenses >/dev/null 2>&1 ||:
    sdkmanager "system-images;android-${android_api_version};${android_image_type};${android_arch}"
  )
}

cmdline_os="$(detect_os)"
cmdline_version="${cmdline_version:-13114758}"
cmdline_tools_url="${cmdline_tools_url:-https://dl.google.com/android/repository/commandlinetools-${cmdline_os}-${cmdline_version}_latest.zip}"
sdk_tools_dir="${sdk_tools_dir:-/opt/android-sdk}"
android_api_version="${android_api_version:-36}"
android_image_type="${android_image_type:-google_apis}"

echo "Downloading Android SDK Command Line Tools for ${cmdline_os}..."

if [[ "${cmdline_os}" == "mac" && -x "$(command -v brew)" ]]; then
  download_sdk_tools_homebrew
else
  download_sdk_tools "${cmdline_tools_url}" "${sdk_tools_dir}"
fi

echo "Installing Android Platform Tools and SDKs..."
install_platform_tools "${android_api_version}"

echo "Installing Android System Image..."
install_android_image "${android_api_version}" "${android_image_type}"
