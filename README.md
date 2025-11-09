```markdown
# android-emulator-multiarch

This repo builds a Rocky Linux 9 Docker image for running a headless Android emulator.
It supports automatically selecting and pre-baking the correct system image ABI for the target build platform
(x86_64 vs arm64) at image build time.

What is included
- Dockerfile: multi-arch-aware, pre-bakes API 33 + google_apis system image (x86_64 or arm64-v8a depending on build target)
- start-emulator.sh: entrypoint to create/run AVDs and start emulator in headless software-rendering mode
- .github/workflows/build-and-push.yml: GitHub Actions workflow to build/push per-arch images and create a multi-arch manifest
- docker-compose.yml: example run configuration
- .dockerignore

Quick build (local)
- Build for current architecture (example for arm64 on Apple Silicon):
  docker build --platform linux/arm64 -t android-emulator:arm64 --build-arg CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip" .

- Build multi-arch and push (requires buildx + registry login):
  docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/OWNER/REPO:latest --push .

Run (example)
- Run with defaults (pre-baked demo AVD, API 33):
  docker run --rm -it -p 5555:5555 -p 5037:5037 ghcr.io/OWNER/REPO:latest

- Run with custom memory and AVD name:
  docker run --rm -it -p 5555:5555 -p 5037:5037 \
    -e AVD_NAME="ci_avd" -e AVD_MEMORY="4096" \
    ghcr.io/OWNER/REPO:latest

Environment variables
- AVD_NAME: name for the AVD (default: demo)
- ANDROID_API: API level (default: 33)
- IMAGE_TYPE: system image type (default: google_apis)
- IMAGE_ARCH: ABI (default auto-detected from image built into container)
- AVD_MEMORY: memory in MB for the emulator (default: 2048)
- EMULATOR_EXTRA_ARGS: additional args passed to emulator
- SKIP_SDK_UPDATE: default 1 (image pre-baked). Set to "0" to allow sdkmanager installs at startup.

Notes & caveats
- Image size is large because it includes Android system image and emulator.
- Default runs use SwiftShader (software rendering) and -accel off for max compatibility.
- To enable hardware accel on Linux hosts with /dev/kvm, mount /dev/kvm and adjust EMULATOR_EXTRA_ARGS to include "-accel on -gpu host".
- For the arm build job in Actions we use a runner labeled 'ubuntu-24.04-arm'. If GitHub-hosted runner for that label is not available for your account/region, register a self-hosted arm64 runner and add the label 'ubuntu-24.04-arm'.
```