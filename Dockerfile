FROM --platform=$BUILDPLATFORM rockylinux:9

ARG SDK_TOOLS_DIR="/opt/android-sdk"
ARG CMDLINE_VERSION="13114758"

ARG ANDROID_API_VERSION="36"
ARG ANDROID_IMAGE_TYPE="google_apis"

ENV ANDROID_EMULATOR_HOME="/home/android/.android"

RUN <<EOF
  set -eux

  # Basic update and EPEL
  dnf -y update
  dnf -y install epel-release dnf-plugins-core

  # Base runtime packages
  dnf -y install unzip tar which git java-17-openjdk-headless \
      ca-certificates \
      libXrandr libXcursor libXinerama libXcomposite libXdamage \
      mesa-libGL mesa-libEGL mesa-libgbm alsa-lib pulseaudio-libs libX11 \
      glibc-langpack-en xorg-x11-server-Xvfb python3 \
      openbox x11vnc tigervnc-server

  dnf clean all
  rm -rf /var/cache/dnf /var/tmp/*

  curl --silent --show-error --retry 5 https://bootstrap.pypa.io/get-pip.py | python3

  pip3 install --no-cache-dir websockify==0.11.0 supervisor==4.3.0
EOF

RUN <<EOF
  useradd -m -u 1000 android
  mkdir -p "${SDK_TOOLS_DIR}"
  chown android:android "${SDK_TOOLS_DIR}"
EOF

USER android
WORKDIR /home/android

RUN --mount=type=bind,rw,src=./setup.sh,dst=/setup.sh <<EOF
  export sdk_tools_dir="${SDK_TOOLS_DIR}"
  export cmdline_version="${CMDLINE_VERSION}"
  export android_api_version="${ANDROID_API_VERSION}"
  export android_image_type="${ANDROID_IMAGE_TYPE}"

  bash -x /setup.sh

EOF

EXPOSE 5554 5555 5037 5900 6080

ENTRYPOINT ["/usr/local/bin/start-emulator.sh"]
