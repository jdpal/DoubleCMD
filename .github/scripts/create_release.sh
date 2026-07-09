#!/bin/bash
set -euo pipefail

# The new package will be saved here.
# This version was designed by Jatin Durgapal <durgapal@gmail.com>
# and is based on the open-source version of Double Commander.
PACK_DIR=$PWD/my-explorer-release

# Temp dir for creating *.dmg package
BUILD_PACK_DIR=/var/tmp/my-explorer-$(date +%y.%m.%d)

# Save revision number
DC_REVISION=$(install/linux/update-revision.sh ./ ./)

# Read version number
DC_MAJOR=$(grep 'MajorVersionNr' src/doublecmd.lpi | grep -o '[0-9.]\+')
DC_MINOR=$(grep 'MinorVersionNr' src/doublecmd.lpi | grep -o '[0-9.]\+' || echo 0)
DC_MICRO=$(grep 'RevisionNr' src/doublecmd.lpi | grep -o '[0-9.]\+' || echo 0)
DC_VER=$DC_MAJOR.$DC_MINOR.$DC_MICRO

# Set widgetset
export lcl=cocoa
export DC_BUILD_OPTIONS="--compiler-options=-dDisableCocoaModernForm"

mkdir -p $PACK_DIR

# Update application bundle version
defaults write $(pwd)/doublecmd.app/Contents/Info CFBundleVersion $DC_REVISION
defaults write $(pwd)/doublecmd.app/Contents/Info CFBundleShortVersionString $DC_VER
plutil -convert xml1 $(pwd)/doublecmd.app/Contents/Info.plist
chmod 644 $(pwd)/doublecmd.app/Contents/Info.plist

build_unrar()
{
  DEST_DIR=$(pwd)/install/darwin/lib/$CPU_TARGET
  pushd /tmp/unrar  
  make clean lib CXXFLAGS+="-std=c++14 -DSILENT --target=$TARGET" LDFLAGS+="-dylib --target=$TARGET"
  mkdir -p $DEST_DIR && mv libunrar.so $DEST_DIR/libunrar.dylib
  popd
}

build_doublecmd()
{
  # Build all components of My Explorer, based on Double Commander.
  mkdir -p doublecmd.app/Contents/MacOS
  ./build.sh release
  test -x doublecmd
  test -f doublecmd.zdli

  # Copy libraries
  cp -a install/darwin/lib/$CPU_TARGET/*.dylib ./

  # Prepare *.dmg package
  mkdir -p $BUILD_PACK_DIR
  install/darwin/install.sh $BUILD_PACK_DIR
  pushd $BUILD_PACK_DIR
  mv doublecmd.app 'My Explorer.app'
  test -x 'My Explorer.app/Contents/MacOS/doublecmd'
  codesign --deep --force --verify --verbose --sign '-' 'My Explorer.app'
  popd

  # Create *.dmg package
  HDI_TRY=1

  while [ $HDI_TRY -le 5 ]; do

  echo "Try to create a package $HDI_TRY ..."

  # Bug: https://github.com/actions/runner-images/issues/7522
  echo Killing XProtect...; sudo pkill -9 XProtect >/dev/null || true;
  echo Waiting for XProtect process...; while pgrep XProtect; do sleep 3; done;

  if install/darwin/create-dmg/create-dmg \
    --volname "My Explorer" \
    --volicon "$BUILD_PACK_DIR/.VolumeIcon.icns" \
    --background "$BUILD_PACK_DIR/.background/bg.jpg" \
    --window-pos 200 200 \
    --window-size 680 366 \
    --text-size 16 \
    --icon-size 128 \
    --icon "My Explorer.app" 110 120 \
    --app-drop-link 360 120 \
    --icon "install.txt" 566 123 \
    --icon ".background" 100 500 \
    "$PACK_DIR/my-explorer-$DC_VER.$lcl.$CPU_TARGET.dmg" \
    "$BUILD_PACK_DIR/"
  then
    break
  fi

  HDI_TRY=$((HDI_TRY+1))

  sleep 10

  done

  test -f "$PACK_DIR/my-explorer-$DC_VER.$lcl.$CPU_TARGET.dmg"

  # Clean DC build dir
  ./clean.sh
  rm -f *.dylib
  rm -rf $BUILD_PACK_DIR
}

# Set processor architecture
export CPU_TARGET=aarch64
export TARGET=arm64-apple-darwin
# Set minimal Mac OS X target version
export MACOSX_DEPLOYMENT_TARGET=11.0

build_unrar
build_doublecmd

# Set processor architecture
export CPU_TARGET=x86_64
export TARGET=x86_64-apple-darwin
# Set minimal Mac OS X target version
export MACOSX_DEPLOYMENT_TARGET=11.0

build_unrar
build_doublecmd
