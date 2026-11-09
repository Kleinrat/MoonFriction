#!/usr/bin/env sh
set -eu

version=$(moonc -v)
printf '%s\n' "$version"
if ! printf '%s\n' "$version" | awk '
NR == 1 && $1 ~ /^v?[0-9]+\.[0-9]+\.[0-9]+([+].*)?$/ {
  sub(/^v/, "", $1)
  split($1, v, /[.+]/)
  supported = (v[1] > 0 || v[2] > 10 || (v[2] == 10 && v[3] >= 16))
}
END { exit !supported }'
then
  printf '%s\n' 'MoonFriction requires moonc 0.10.16 or later.' >&2
  exit 1
fi
