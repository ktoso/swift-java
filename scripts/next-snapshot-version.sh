#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift.org project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of Swift.org project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

# Prints the next development snapshot version, derived from the most recent
# release tag, e.g. "0.6.0" becomes "0.6.1-SNAPSHOT". Used by publish-snapshot.yml.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

LATEST_TAG="$(git -C "$REPO_ROOT" describe --tags --abbrev=0)"

if [[ ! "$LATEST_TAG" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "error: latest tag '$LATEST_TAG' is not in X.Y.Z format" >&2
  exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

echo "${MAJOR}.${MINOR}.$((PATCH + 1))-SNAPSHOT"
