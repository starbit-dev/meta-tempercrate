#!/usr/bin/env bash
#
# rootfs-lddtree-versions.sh
#
# Offline dependency walker for a Yocto rootfs:
#   - Extracts DT_NEEDED using readelf (no ldd, no execution).
#   - Resolves libs inside the given rootfs.
#   - Recursively expands transitive dependencies (like lddtree).
#   - Prints: LIB_NAME<TAB>VERSION
#
# VERSION policy:
#   1) If dpkg database exists in rootfs, use the package Version (best match to installed runtime version).
#   2) Otherwise, fall back to numeric micro-version parsed from the real filename (*.so.X.Y.Z).
#   3) Otherwise, print "(NOT_FOUND)".
#

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  rootfs-lddtree-versions.sh --rootfs <rootfs_path> --bin <binary_path>

Examples:
  # Binary inside rootfs:
  ./rootfs-lddtree-versions.sh --rootfs /path/to/rootfs --bin /usr/bin/tempercrateboxd

  # Binary outside rootfs:
  ./rootfs-lddtree-versions.sh --rootfs /path/to/rootfs --bin /home/bruno/build/tempercrateboxd

Output (TSV):
  LIB_NAME    VERSION
EOF
}

ROOTFS=""
BIN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rootfs) ROOTFS="${2:-}"; shift 2;;
    --bin)    BIN="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

[[ -z "$ROOTFS" || -z "$BIN" ]] && { usage; exit 1; }
[[ ! -d "$ROOTFS" ]] && { echo "ERROR: rootfs not found: $ROOTFS" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1' in PATH" >&2; exit 1; }; }
need_cmd readelf
need_cmd awk
need_cmd sed
need_cmd grep
need_cmd sort
need_cmd find
need_cmd head
need_cmd basename
need_cmd dirname
need_cmd readlink

# Resolve BIN path (rootfs-relative if applicable)
BIN_REAL="$BIN"
if [[ "$BIN" = /* && -f "$ROOTFS$BIN" ]]; then
  BIN_REAL="$ROOTFS$BIN"
fi
[[ ! -f "$BIN_REAL" ]] && { echo "ERROR: binary not found: $BIN (resolved: $BIN_REAL)" >&2; exit 1; }

# Detect dpkg DB
DPKG_STATUS="$ROOTFS/var/lib/dpkg/status"
DPKG_INFO_DIR="$ROOTFS/var/lib/dpkg/info"
HAVE_DPKG_DB=0
if [[ -f "$DPKG_STATUS" && -d "$DPKG_INFO_DIR" ]]; then
  HAVE_DPKG_DB=1
fi

# Extract RUNPATH/RPATH from a given ELF (file path in host FS)
extract_paths() {
  local elf="$1"
  local tag="$2"
  readelf -d "$elf" 2>/dev/null \
    | awk -v tag="$tag" '
      $0 ~ "\\("tag"\\)" {
        match($0, /\[(.*)\]/, a);
        if (a[1] != "") print a[1];
      }' \
    | head -n1
}

# Extract DT_NEEDED list from a given ELF (file path in host FS)
needed_from_elf() {
  local elf="$1"
  readelf -d "$elf" 2>/dev/null \
    | awk '/\(NEEDED\)/{gsub(/\[|\]/,"",$NF); print $NF}' \
    | sort -u
}

# Expand $ORIGIN only when the ELF is inside rootfs
expand_origin() {
  local raw="$1"
  local origin_dir="$2"   # rootfs-relative, e.g. /usr/bin
  if [[ -z "$origin_dir" ]]; then
    [[ "$raw" == *"ORIGIN"* ]] && return
    echo "$raw"
    return
  fi
  raw="${raw//\$ORIGIN/$origin_dir}"
  raw="${raw//\$\{ORIGIN\}/$origin_dir}"
  echo "$raw"
}

# Resolve a lib name to an absolute host path inside rootfs (ROOTFS + dir + lib)
resolve_lib_with_paths() {
  local lib="$1"
  shift
  local -a dirs=("$@")
  local d p
  for d in "${dirs[@]}"; do
    p="$ROOTFS$d/$lib"
    [[ -e "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

# Resolve symlink chain to real file inside rootfs
real_file() {
  local p="$1"
  [[ -L "$p" ]] && readlink -f "$p" 2>/dev/null || echo "$p"
}

# Extract numeric micro-version from filename
microver_from_filename() {
  local f
  f="$(basename "$1")"
  sed -n 's/.*\.so\.\([0-9]\+\(\.[0-9]\+\)*\)$/\1/p' <<<"$f"
}

# Find dpkg package owning a file (by scanning *.list)
dpkg_pkg_for_file() {
  local abs="$1"                 # absolute host path: $ROOTFS/usr/lib/...
  local rel="${abs#"$ROOTFS"}"   # rootfs path: /usr/lib/...
  local hit
  hit="$(grep -R --fixed-string -- "$rel" "$DPKG_INFO_DIR"/*.list 2>/dev/null | head -n1 || true)"
  [[ -z "$hit" ]] && return
  echo "$(basename "${hit%%:*}" .list)"
}

# Get dpkg Version for a package
dpkg_ver_for_pkg() {
  local pkg="$1"
  [[ -z "$pkg" ]] && return
  awk -v pkg="$pkg" '
    $1=="Package:"{p=$2}
    $1=="Version:" && p==pkg {print $2; exit}
  ' "$DPKG_STATUS" 2>/dev/null
}

# Get a "best" version for a resolved library file
best_version_for_file() {
  local abs="$1"  # absolute host path inside rootfs
  if [[ $HAVE_DPKG_DB -eq 1 ]]; then
    local pkg ver
    pkg="$(dpkg_pkg_for_file "$abs" || true)"
    ver="$(dpkg_ver_for_pkg "$pkg" || true)"
    [[ -n "$ver" ]] && { echo "$ver"; return; }
  fi
  local micro
  micro="$(microver_from_filename "$abs" || true)"
  [[ -n "$micro" ]] && { echo "$micro"; return; }
  echo "(NOT_FOUND)"
}

# Standard library search dirs (base)
DEFAULT_DIRS=(
  "/lib"
  "/usr/lib"
  "/usr/local/lib"
  "/lib/arm-linux-gnueabi"
  "/usr/lib/arm-linux-gnueabi"
  "/lib/arm-linux-gnueabihf"
  "/usr/lib/arm-linux-gnueabihf"
)

# Auto-detect lib dirs inside rootfs (multiarch variants)
mapfile -t AUTO_DIRS < <(
  find "$ROOTFS/usr/lib" "$ROOTFS/lib" -maxdepth 3 -type d 2>/dev/null \
    | sed "s|^$ROOTFS||" \
    | sort -u
)

# BFS over dependency graph
declare -A VISITED=()      # libname -> 1
declare -A VERSION_MAP=()  # libname -> version

# Queue (simple array indices)
QUEUE=()

# Seed with initial NEEDED libs from the main binary
while IFS= read -r lib; do
  [[ -n "$lib" ]] && QUEUE+=("$lib")
done < <(needed_from_elf "$BIN_REAL")

# Prepare origin_dir for $ORIGIN expansion (only if binary is inside rootfs)
ORIGIN_DIR=""
if [[ "$BIN_REAL" != "$BIN" ]]; then
  ORIGIN_DIR="$(dirname "$BIN")"  # rootfs-relative
fi

# Precompute main binary RUNPATH/RPATH dirs
RUNPATH_MAIN="$(extract_paths "$BIN_REAL" RUNPATH || true)"
RPATH_MAIN="$(extract_paths "$BIN_REAL" RPATH || true)"

build_search_dirs_for_elf() {
  local elf="$1"
  local origin_dir="$2"
  local runpath rpath
  runpath="$(extract_paths "$elf" RUNPATH || true)"
  rpath="$(extract_paths "$elf" RPATH || true)"

  local -a dirs=()

  # Use ELF-specific RUNPATH/RPATH first
  for raw in "$runpath" "$rpath"; do
    [[ -z "$raw" ]] && continue
    IFS=':' read -r -a arr <<<"$raw"
    for d in "${arr[@]}"; do
      d="$(expand_origin "$d" "$origin_dir" || true)"
      [[ -n "${d:-}" ]] && dirs+=("$d")
    done
  done

  # Then fall back to main binary RUNPATH/RPATH (common case)
  for raw in "$RUNPATH_MAIN" "$RPATH_MAIN"; do
    [[ -z "$raw" ]] && continue
    IFS=':' read -r -a arr <<<"$raw"
    for d in "${arr[@]}"; do
      d="$(expand_origin "$d" "$origin_dir" || true)"
      [[ -n "${d:-}" ]] && dirs+=("$d")
    done
  done

  # Finally defaults + autodirs
  dirs+=("${DEFAULT_DIRS[@]}")
  dirs+=("${AUTO_DIRS[@]}")

  # Deduplicate preserving order
  printf "%s\n" "${dirs[@]}" | awk '!seen[$0]++'
}

# Walk dependencies
i=0
while [[ $i -lt ${#QUEUE[@]} ]]; do
  lib="${QUEUE[$i]}"
  i=$((i + 1))

  # Skip already processed libs
  [[ -n "${VISITED[$lib]:-}" ]] && continue
  VISITED["$lib"]=1

  # Build search dirs for current context
  mapfile -t SEARCH_DIRS < <(build_search_dirs_for_elf "$BIN_REAL" "$ORIGIN_DIR")

  # Resolve library file in rootfs
  if abs="$(resolve_lib_with_paths "$lib" "${SEARCH_DIRS[@]}" 2>/dev/null)"; then
    real="$(real_file "$abs")"
    VERSION_MAP["$lib"]="$(best_version_for_file "$real")"

    # Recurse: extract this library's own dependencies
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      [[ -n "${VISITED[$dep]:-}" ]] && continue
      QUEUE+=("$dep")
    done < <(needed_from_elf "$real" || true)
  else
    VERSION_MAP["$lib"]="(NOT_FOUND)"
  fi
done

# Print results sorted by library name (stable and easy to diff)
printf "LIB_NAME\tVERSION\n"
for k in "${!VERSION_MAP[@]}"; do
  printf "%s\t%s\n" "$k" "${VERSION_MAP[$k]}"
done | sort
