FROM --platform=$BUILDPLATFORM rockylinux:9

# Build args
ARG CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip"
ARG SDK_TOOLS_DIR="/opt/android-sdk"
ARG DEFAULT_AVD_NAME="demo"
ARG ANDROID_API="33"
ARG IMAGE_TYPE="google_apis"

ENV ANDROID_SDK_ROOT=${SDK_TOOLS_DIR} \
    ANDROID_HOME=${SDK_TOOLS_DIR} \
    ANDROID_SDK_HOME=${SDK_TOOLS_DIR} \
    PATH=${SDK_TOOLS_DIR}/cmdline-tools/latest/bin:${SDK_TOOLS_DIR}/platform-tools:${SDK_TOOLS_DIR}/emulator:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Install runtime packages and Java
RUN dnf -y update && \
    dnf -y install wget unzip tar which git java-11-openjdk-headless \
        libXrandr libXcursor libXinerama libXcomposite libXdamage \
        mesa-libGL mesa-libEGL mesa-libgbm alsa-lib libX11 \
        glibc-langpack-en && \
    dnf clean all && rm -rf /var/cache/dnf

# Download commandline tools
RUN mkdir -p ${SDK_TOOLS_DIR} && \
    cd /tmp && \
    wget -O commandlinetools.zip "${CMDLINE_TOOLS_URL}" && \
    unzip -q commandlinetools.zip -d /tmp/cmdline-tools-temp && \
    mkdir -p ${SDK_TOOLS_DIR}/cmdline-tools && \
    mv /tmp/cmdline-tools-temp/cmdline-tools ${SDK_TOOLS_DIR}/cmdline-tools/latest && \
    rm -rf /tmp/commandlinetools.zip /tmp/cmdline-tools-temp

# Use TARGETPLATFORM to pick ABI (x86_64 for amd64, arm64-v8a for arm64)
# Then install platform-tools, emulator, and pre-bake Android API and system-image for that ABI.
ARG TARGETPLATFORM
RUN set -eux; \
    case "${TARGETPLATFORM:-}" in \
      "linux/arm64"|"linux/arm64/v8"|"linux/arm64/v8l"|"linux/arm64/v8a") IMAGE_ARCH="arm64-v8a" ;; \
      *) IMAGE_ARCH="x86_64" ;; \
    esac; \
    echo "Target platform: ${TARGETPLATFORM:-unknown} -> using system image ABI: ${IMAGE_ARCH}"; \
    yes | sdkmanager --sdk_root=${SDK_TOOLS_DIR} --licenses >/dev/null || true; \
    sdkmanager --sdk_root=${SDK_TOOLS_DIR} "platform-tools" "emulator" "platforms;android-${ANDROID_API}" "system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH}"

# Create default AVD (demo) matching the chosen ABI
ARG DEFAULT_AVD_NAME
RUN mkdir -p ${SDK_TOOLS_DIR}/.android && \
    case "${TARGETPLATFORM:-}" in \
      "linux/arm64"*) IMAGE_ARCH_SEL="arm64-v8a" ;; \
      *) IMAGE_ARCH_SEL="x86_64" ;; \
    esac && \
    # export ANDROID_SDK_ROOT so avdmanager uses the right SDK path, then create AVD in same shell
    export ANDROID_SDK_ROOT=${SDK_TOOLS_DIR} && \
    echo "Creating AVD with ABI=${IMAGE_ARCH_SEL}" && \
    echo "no" | avdmanager create avd -n "${DEFAULT_AVD_NAME}" -k "system-images;android-${ANDROID_API};${IMAGE_TYPE};${IMAGE_ARCH_SEL}" --force || true

# Create non-root user and set ownership
RUN useradd -m -u 1000 android && \
    chown -R android:android ${SDK_TOOLS_DIR} /home/android

USER android
WORKDIR /home/android

# Copy entrypoint
COPY start-emulator.sh /usr/local/bin/start-emulator.sh
RUN chmod +x /usr/local/bin/start-emulator.sh

# Expose emulator / adb ports
EXPOSE 5554 5555 5037

# Defaults (can be overridden at runtime)
ENV AVD_NAME="demo" \
    ANDROID_API="33" \
    IMAGE_TYPE="google_apis" \
    IMAGE_ARCH="" \
    AVD_MEMORY="2048" \
    EMULATOR_EXTRA_ARGS="" \
    SKIP_SDK_UPDATE="1"

ENTRYPOINT ["/usr/local/bin/start-emulator.sh"]