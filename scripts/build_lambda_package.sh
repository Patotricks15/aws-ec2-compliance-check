#!/usr/bin/env bash
set -euo pipefail

project_dir="$1"
function_name="$2"
build_dir="$project_dir/.build/$function_name"

# boto3 ships with the Lambda Python runtime, so no extra deps to vendor here.
rm -rf "$build_dir"
mkdir -p "$build_dir"
cp "$project_dir/src/lambda/$function_name/handler.py" "$build_dir/handler.py"
