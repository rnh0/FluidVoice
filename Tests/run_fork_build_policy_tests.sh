#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
test -d "$task_developer_dir/Platforms/MacOSX.platform"
export DEVELOPER_DIR="$task_developer_dir"
task_test_dir=$(mktemp -d /tmp/fluidvoice-fork-policy.XXXXXX)
trap 'rm -rf "$task_test_dir"' EXIT
xcrun swiftc -parse-as-library -D FLUID_LOCAL_ONLY \
  Sources/Fluid/Services/ForkBuildPolicy.swift \
  Sources/Fluid/Services/LocalAPI/LocalAPIModels.swift \
  Sources/Fluid/Services/LocalAPI/LocalAPIAccessPolicy.swift \
  Tests/ForkBuildPolicyTests.swift -o "$task_test_dir/tests"
"$task_test_dir/tests"
