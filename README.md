# docker-android-simulator — 使用说明

这是一个可直接运行的 Android Emulator 容器镜像，便于在本地或 CI 环境中启动模拟器进行调试、UI 测试或自动化任务。

快速开始（本地单机测试）
1. 构建镜像（在 amd64 主机上测试）：
   docker build --platform linux/amd64 -t wangzw/android-emulator:local .

2. 运行（默认 headless，使用预置 AVD 名称 demo）：
   docker run --rm -it \
   -e AVD_NAME="demo" \
   -e ANDROID_API="36" \
   wangzw/android-emulator:local

3. 在容器内使用 adb（示例）：
   docker exec -it <container> adb devices

GUI（VNC / noVNC）访问
- 启动容器并映射端口到宿主机：
  docker run --rm -it \
  -p 5900:5900 \
  -p 6080:6080 \
  -e VNC_ENABLE=1 \
  -e VNC_PASSWORD="changeme" \
  wangzw/android-emulator:local

- 访问方式：
    - 使用 VNC 客户端连接：host:5900，输入 VNC_PASSWORD（如设置）。
    - 使用浏览器访问 noVNC：http://localhost:6080/ 。

ADB 从宿主机连接
- 如果容器暴露并映射了 ADB/仿真器端口，可以直接从宿主机连接：
  adb connect <container-ip>:5555
- 也可以进入容器执行 adb 命令：
  docker exec -it <container> /bin/bash
  adb devices

持久化与卷
- 持久化 AVD、应用或用户数据：
  docker run -v /path/on/host/avd:/opt/android-sdk/.android/avd ...
- 将特定目录挂载到容器以保留数据或加速构建输出。

性能与硬件加速
- 默认使用软件渲染，适用于没有 KVM 的环境。
- 在支持 KVM 的 Linux 主机上，可以映射 /dev/kvm 提升性能：
  docker run --device /dev/kvm ...  并通过 EMULATOR_EXTRA_ARGS 传递合适的参数（例如 -accel on -gpu host）。

常用环境变量（运行时）
- AVD_NAME — 要启动的 AVD 名称（默认 demo）
- ANDROID_API — Android API 级别（默认 36）
- IMAGE_TYPE — 系统镜像类型（例如 google_apis）
- IMAGE_ARCH — 目标 ABI（例如 arm64-v8a、x86_64），留空则自动选择
- AVD_MEMORY — 分配给模拟器的内存（MB）
- EMULATOR_EXTRA_ARGS — 额外传给 emulator 的参数
- SKIP_SDK_UPDATE — 若设置为 0，容器启动时会尝试下载/安装缺失的 SDK 组件
- VNC_ENABLE — 设置为 1 启用 VNC/noVNC（可选）
- VNC_PASSWORD — VNC 密码（可选）

CI / 自动化建议
- 为 CI 场景优先使用 headless 模式并预先在镜像中安装所需 SDK 组件，以提高稳定性与启动速度。
- 多架构构建建议使用 docker buildx；在使用 QEMU 模拟时注意网络/TLS 行为可能与本地不同，必要时在对应平台的 runner 上执行构建或安装大型组件。

故障排查（常见问题）
- 模拟器无法启动或屏幕黑屏：检查容器日志、确认 emulator 命令行参数与 DISPLAY（GUI 模式）或 -no-window（headless）。
- ADB 无法连接：确认 adb 服务在容器中运行并且端口已映射，或直接在容器内执行 adb devices 进行验证。
- 下载或依赖相关错误：检查构建/运行环境的网络与代理设置，必要时在容器内运行相应命令查看详细错误信息。

示例：以 VNC 模式运行并连接
docker run --rm -it -p 5900:5900 -p 6080:6080 \
-e VNC_ENABLE=1 -e VNC_PASSWORD="secret" wangzw/android-emulator:local

更多帮助
- 若需要针对具体环境（CI、GPU 加速、持久化策略等）获得建议，请说明你的运行环境和目标，我会提供更具体的配置示例。

License
- 请根据项目需要补充或更新许可证信息.