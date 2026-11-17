#!/bin/zsh
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")"
exec ./build_app.sh "$@"
