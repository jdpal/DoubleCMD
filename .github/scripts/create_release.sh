#!/bin/bash
set -euo pipefail

PACK_DIR=$PWD/my-explorer-release
NATIVE_DIR=$PWD/native/MyExplorer
DC_VER=$(cat "$NATIVE_DIR/VERSION")

mkdir -p "$PACK_DIR"

build_native_dmg()
{
  local cpu_target=$1
  local swift_arch=$2
  local build_pack_dir=/var/tmp/my-explorer-$DC_VER-$cpu_target
  local app_dir="$build_pack_dir/My Explorer.app"
  local dmg_path="$PACK_DIR/my-explorer-$DC_VER.native.$cpu_target.dmg"
  local create_dmg_option=

  if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    create_dmg_option=--skip-jenkins
  fi

  rm -rf "$build_pack_dir"
  rm -f "$dmg_path"
  mkdir -p "$build_pack_dir"
  cp -R install/darwin/dmg/. "$build_pack_dir/"

  ARCH="$swift_arch" \
  VERSION="$DC_VER" \
  APP_DIR="$app_dir" \
  "$NATIVE_DIR/Scripts/build_app.sh"

  test -x "$app_dir/Contents/MacOS/MyExplorer"
  codesign --verify --deep --strict --verbose=2 "$app_dir"

  local hdi_try=1
  while [ $hdi_try -le 5 ]; do
    echo "Try to create $cpu_target package $hdi_try ..."

    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      echo "Killing XProtect..."
      sudo pkill -9 XProtect >/dev/null || true
      echo "Waiting for XProtect process..."
      while pgrep XProtect; do sleep 3; done
    fi

    if install/darwin/create-dmg/create-dmg \
      $create_dmg_option \
      --volname "My Explorer" \
      --volicon "$build_pack_dir/.VolumeIcon.icns" \
      --background "$build_pack_dir/.background/bg.jpg" \
      --window-pos 200 200 \
      --window-size 680 366 \
      --text-size 16 \
      --icon-size 128 \
      --icon "My Explorer.app" 110 120 \
      --app-drop-link 360 120 \
      --icon "install.txt" 566 123 \
      --icon ".background" 100 500 \
      "$dmg_path" \
      "$build_pack_dir/"
    then
      break
    fi

    hdi_try=$((hdi_try+1))
    sleep 10
  done

  test -f "$dmg_path"
  rm -rf "$build_pack_dir"
}

build_native_dmg aarch64 arm64
build_native_dmg x86_64 x86_64

(
  cd "$PACK_DIR"
  shasum -a 256 my-explorer-$DC_VER.native.*.dmg > SHA256SUMS.txt
)
