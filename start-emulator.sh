#!/usr/bin/env bash

set -euox pipefail

function create_virtual_device() {
  local avd_name=$1
  local system_image=$2
  local device=$3

  echo "创建虚拟设备: ${avd_name}，系统镜像: ${system_image}，设备: ${device}"
  echo "no" | avdmanager create avd -n "${avd_name}" -k "${system_image}" -d "${device}" --force
}

function start_virtual_device() {
  local avd_name=$1
  local port=$2

  echo "启动虚拟设备: ${avd_name}"
  emulator -avd "${avd_name}" -port ${port} -gpu swiftshader_indirect -accel on
}

function wait_for_device_ready() {
  local avd_name=$1
  local port=$2
  local timeout=${3:-300}

  echo "等待虚拟设备 ${avd_name} 启动..."
  adb -s emulator-${port} wait-for-device

  local count=0
  while [ "`adb -s emulator-${port} shell getprop sys.boot_completed | tr -d '\r' `" != "1" ] ; do
    sleep 2
    count=$((count + 2))
    echo "已等待 ${count} 秒..."

    if [ $count -ge $timeout ]; then
      echo "错误: 模拟器启动超时"
      exit 1
    fi
  done
}

create_virtual_device demo1 "system-images;android-36;google_apis;x86_64" "pixel"
start_virtual_device demo1 5554 &
wait_for_device_ready demo1 5554

create_virtual_device demo2 "system-images;android-36;google_apis;x86_64" "pixel"
start_virtual_device demo2 5556 &
wait_for_device_ready demo2 5556
