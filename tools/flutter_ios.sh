#!/bin/sh

set -eu

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <flutter arguments>" >&2
  echo "Example: $0 build ios --simulator --debug" >&2
  exit 64
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
temporary_root=${TMPDIR:-/private/tmp}
external_build_dir="$temporary_root/cithub_flutter_build"
isolated_config_dir=$(mktemp -d "$temporary_root/cithub-flutter-config.XXXXXX")

cleanup() {
  rm -rf -- "$isolated_config_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$external_build_dir"
relative_build_dir=$(
  /usr/bin/python3 -c \
    'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
    "$external_build_dir" \
    "$project_dir"
)

cd "$project_dir"
XDG_CONFIG_HOME="$isolated_config_dir" \
  flutter config --build-dir="$relative_build_dir" >/dev/null

flutter_status=0
XDG_CONFIG_HOME="$isolated_config_dir" flutter "$@" || flutter_status=$?

# Integration tests temporarily point Generated.xcconfig at a disposable
# listener.dart. Restore the normal application target for the next Xcode run.
if [ "$1" = "test" ]; then
  config_status=0
  XDG_CONFIG_HOME="$isolated_config_dir" \
    flutter build ios --config-only --simulator --debug >/dev/null || \
    config_status=$?
  if [ "$flutter_status" -eq 0 ]; then
    flutter_status=$config_status
  fi
fi

exit "$flutter_status"
