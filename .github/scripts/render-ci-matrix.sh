#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <suite> <system>" >&2
  exit 64
fi

suite="$1"
system="$2"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
catalog="$repo_root/.github/ci/smoke-tests.json"

jq -c --arg suite "$suite" --arg system "$system" '
  def in_suite:
    if $suite == "github-fast" then
      (.features.virtualization | not)
    elif $suite == "namespace-primary" then
      .features.virtualization
    elif $suite == "namespace-secondary" then
      (.features.secondaryArchRepresentative // false)
    elif $suite == "namespace-full" then
      true
    else
      error("unknown ci suite: " + $suite)
    end;
  . as $catalog
  | {
      include: [
        .tests[]
        | select(.supportedSystems | index($system))
        | select(in_suite)
        | {
            package: .package,
            shape: (.shapeBySystem[$system] // $catalog.defaults.shapeBySystem[$system])
          }
      ]
    }
' "$catalog"
