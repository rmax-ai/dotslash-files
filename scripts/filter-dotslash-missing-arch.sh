#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: filter-dotslash-missing-arch.sh [--os OS] [--arch ARCH] [path...]
Print .dotslash files that DO NOT contain a platform entry for the host OS/ARCH.
Examples:
  filter-dotslash-missing-arch.sh         # use host uname
  filter-dotslash-missing-arch.sh . bin   # limit search to given paths
  filter-dotslash-missing-arch.sh --arch amd64
EOF
  exit 2
}

os_arg=""
arch_arg=""
paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help) usage ;;
  --os)
    os_arg="$2"
    shift 2
    ;;
  --arch)
    arch_arg="$2"
    shift 2
    ;;
  --)
    shift
    paths+=("$@")
    break
    ;;
  -*)
    echo "Unknown option: $1" >&2
    usage
    ;;
  *)
    paths+=("$1")
    shift
    ;;
  esac
done

[ ${#paths[@]} -eq 0 ] && paths=(.)

# detect host if not set
if [[ -z "$os_arg" ]]; then
  uname_s=$(uname -s)
  case "$uname_s" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  *)
    echo "Unsupported OS: $uname_s" >&2
    exit 1
    ;;
  esac
else
  os=$os_arg
fi

if [[ -z "$arch_arg" ]]; then
  uname_m=$(uname -m)
  case "$uname_m" in
  arm64 | aarch64) arch_pat='(aarch64|arm64)' ;;
  x86_64 | amd64 | x86-64) arch_pat='(x86_64|amd64)' ;;
  *) arch_pat="$uname_m" ;;
  esac
else
  case "$arch_arg" in
  arm64 | aarch64) arch_pat='(aarch64|arm64)' ;;
  x86_64 | amd64) arch_pat='(x86_64|amd64)' ;;
  *) arch_pat="$arch_arg" ;;
  esac
fi

re="\"${os}-${arch_pat}\""

missing=0
while IFS= read -r -d '' f; do
  if ! grep -qE "$re" "$f"; then
    echo "$f"
    missing=1
  fi
done < <(find "${paths[@]}" -type f -name '*.dotslash' -print0)

exit $missing
