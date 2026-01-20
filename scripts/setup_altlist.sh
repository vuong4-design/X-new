#!/usr/bin/env bash
set -euo pipefail

: "${THEOS:?THEOS must be set}"

TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
ALT_DIR="$TMP_DIR/AltList"

git clone --depth=1 https://github.com/opa334/AltList.git "$ALT_DIR"

HEADER_PATH="$(find "$ALT_DIR" -name ATLApplicationListMultiSelectionController.h -print -quit)"
if [[ -n "$HEADER_PATH" ]]; then
  HEADER_DIR="$(dirname "$HEADER_PATH")"
  mkdir -p "$THEOS/include/AltList"
  cp -R "$HEADER_DIR/"* "$THEOS/include/AltList/"
else
  echo "AltList headers not found" >&2
  exit 1
fi

DERIVED_DATA_PATH="$TMP_DIR/altlist_derived"
BUILD_CONFIGURATION="Release"

WORKSPACE_PATH="$(find "$ALT_DIR" -maxdepth 6 -name "*.xcworkspace" -print -quit)"
PROJECT_PATH="$(find "$ALT_DIR" -maxdepth 6 -name "*.xcodeproj" -print -quit)"

if [[ -n "$WORKSPACE_PATH" ]]; then
  xcodebuild \
    -workspace "$WORKSPACE_PATH" \
    -scheme "AltList" \
    -configuration "$BUILD_CONFIGURATION" \
    -sdk iphoneos \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_IDENTITY=""
elif [[ -n "$PROJECT_PATH" ]]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "AltList" \
    -configuration "$BUILD_CONFIGURATION" \
    -sdk iphoneos \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_IDENTITY=""
elif [[ -f "$ALT_DIR/Makefile" ]]; then
  if ! make -C "$ALT_DIR" framework; then
    echo "AltList Makefile has no 'framework' target; falling back to default build." >&2
    make -C "$ALT_DIR" SUBPROJECTS=
  fi
else
  echo "AltList Xcode project/workspace not found; cannot build framework." >&2
  echo "Searched for *.xcworkspace and *.xcodeproj within $ALT_DIR." >&2
  echo "Also looked for a Makefile at $ALT_DIR/Makefile." >&2
  exit 1
fi

SEARCH_PATHS=("$ALT_DIR")
if [[ -d "$DERIVED_DATA_PATH" ]]; then
  SEARCH_PATHS+=("$DERIVED_DATA_PATH")
fi

FRAMEWORK_PATH="$(find "${SEARCH_PATHS[@]}" -name AltList.framework -print -quit)"
if [[ -n "$FRAMEWORK_PATH" ]]; then
  mkdir -p "$THEOS/lib"
  DEST_FRAMEWORK="$THEOS/lib/AltList.framework"
  rm -rf "$DEST_FRAMEWORK"
  cp -R "$FRAMEWORK_PATH" "$DEST_FRAMEWORK"
  if [[ -d "$FRAMEWORK_PATH/Headers" ]]; then
    mkdir -p "$THEOS/include/AltList"
    cp -R "$FRAMEWORK_PATH/Headers/"* "$THEOS/include/AltList/"
  fi
else
  echo "AltList.framework not found in build output." >&2
  exit 1
fi
