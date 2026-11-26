#!/usr/bin/env sh
set -eu

version=$(moonc -v)
printf '%s\n' "$version"
if ! printf '%s\n' "$version" | awk '
NR == 1 && $1 ~ /^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?([+][0-9A-Za-z.-]+)?$/ {
  version = $1
  sub(/^v/, "", version)
  split(version, parts, /[-+]/)
  split(parts[1], v, /[.]/)
  prerelease = substr(version, length(parts[1]) + 1, 1) == "-"
  supported = (v[1] > 0 || v[2] > 10 ||
    (v[2] == 10 && (v[3] > 16 || (v[3] == 16 && !prerelease))))
}
END { exit !supported }'
then
  printf '%s\n' 'MoonFriction requires moonc 0.10.16 or later.' >&2
  exit 1
fi
