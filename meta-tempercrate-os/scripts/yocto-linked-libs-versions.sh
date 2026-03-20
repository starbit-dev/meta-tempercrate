#!/usr/bin/env bash
set -euo pipefail

# yocto-ldd-pv.sh
#
# Input: ldd output file (generated on target)
# Output: For each resolved library path -> Yocto package, recipe, PV
#
# Requirements:
#   - Run after sourcing the build environment:
#       source layers/openembedded-core/oe-init-build-env <builddir>
#   - oe-pkgdata-util and bitbake available in PATH

usage() {
  cat <<'EOF'
Usage:
  yocto-ldd-pv.sh --ldd <ldd_output_file>

Example:
  # On target:
  ldd /usr/bin/tempercrateboxd > /tmp/tempercrateboxd.ldd

  # Copy to host, then on host:
  cd /mnt/yocto/Distribution-Package
  source layers/openembedded-core/oe-init-build-env build-openstlinuxweston-stm32mp13-disco
  ./layers/meta-tempercrate/scripts/yocto-ldd-pv.sh --ldd /mnt/yocto/Distribution-Package/tempercratebox.ldd
EOF
}

LDD_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ldd) LDD_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

[[ -z "$LDD_FILE" ]] && { echo "ERROR: missing --ldd <file>"; usage; exit 1; }
[[ ! -f "$LDD_FILE" ]] && { echo "ERROR: file not found: $LDD_FILE"; exit 1; }

command -v oe-pkgdata-util >/dev/null 2>&1 || {
  echo "ERROR: oe-pkgdata-util not in PATH. Did you source oe-init-build-env?"
  exit 1
}
command -v bitbake >/dev/null 2>&1 || {
  echo "ERROR: bitbake not in PATH. Did you source oe-init-build-env?"
  exit 1
}

# Strip BitBake-style log lines that sometimes leak to stdout
strip_notes() { sed -E '/^(NOTE:|WARNING:|ERROR:|DEBUG:)/d'; }

# Parse resolved library paths from ldd output.
# Handles lines like:
#   libssl.so.3 => /usr/lib/libssl.so.3 (0x....)
#   /lib/ld-linux-armhf.so.3 => /usr/lib/ld-linux-armhf.so.3 (0x....)
mapfile -t LIBPATHS < <(
  awk '
    $0 ~ /^linux-vdso/ {next}
    $0 ~ /=> not found/ {next}
    $0 ~ /=> \// {for (i=1;i<=NF;i++) if ($i ~ /^\//) {print $i; break}; next}
    $1 ~ /^\// && $0 ~ /\(/ {print $1; next}
  ' "$LDD_FILE" \
  | sed 's/\r$//' \
  | sort -u
)

echo "Parsed libraries: ${#LIBPATHS[@]}"
if [[ ${#LIBPATHS[@]} -eq 0 ]]; then
  echo "ERROR: no library paths parsed from $LDD_FILE"
  echo "Hint: check file content: sed -n '1,20p <file>'"
  exit 1
fi

# --- Definitive PKGDATA autodetect ---
# ST layout example:
#   tmp-glibc/pkgdata/x86_64-ostl_sdk-linux/runtime-reverse   (host/SDK)
#   tmp-glibc/pkgdata/stm32mp13-disco/runtime-reverse         (target)
#
# We pick the FIRST runtime-reverse directory that is NOT the SDK host one.
PKGDATA_DIR=""
for base in "tmp-glibc/pkgdata" "tmp/pkgdata" tmp*/pkgdata; do
  [[ -d "$base" ]] || continue
  rr="$(find "$base" -maxdepth 3 -type d -name runtime-reverse 2>/dev/null \
        | grep -v 'x86_64-ostl_sdk-linux' \
        | head -n 1 || true)"
  if [[ -n "$rr" ]]; then
    PKGDATA_DIR="$(dirname "$rr")"
    break
  fi
done

if [[ -z "$PKGDATA_DIR" ]]; then
  echo "ERROR: Could not find target pkgdata runtime-reverse directory."
  echo "Tried: tmp-glibc/pkgdata, tmp/pkgdata, tmp*/pkgdata"
  echo "You can locate it manually with:"
  echo "  find tmp-glibc/pkgdata -maxdepth 3 -type d -name runtime-reverse"
  exit 1
fi

echo "Using PKGDATA_DIR: $PKGDATA_DIR"
echo

printf "%-40s | %-22s | %-22s | %s\n" "LIBRARY PATH" "YOCTO PKG" "YOCTO RECIPE" "PV"
printf -- "%-40s-+-%-22s-+-%-22s-+-%s\n" \
  "$(printf '%.0s-' {1..40})" "$(printf '%.0s-' {1..22})" "$(printf '%.0s-' {1..22})" "$(printf '%.0s-' {1..12})"

for p in "${LIBPATHS[@]}"; do
  pkg="-"
  recipe="-"
  pv="-"

  # find-path returns: "<pkgname>: <path>"
  line="$(oe-pkgdata-util -p "$PKGDATA_DIR" find-path "$p" 2>/dev/null | strip_notes | head -n 1 || true)"
  if [[ -n "$line" ]]; then
    pkg="${line%%:*}"

    recipe="$(oe-pkgdata-util -p "$PKGDATA_DIR" lookup-recipe "$pkg" 2>/dev/null | strip_notes | head -n 1 || true)"
    [[ -z "$recipe" ]] && recipe="-"

    if [[ "$recipe" != "-" ]]; then
      # bitbake -e may fail for some recipe names; never abort the script
      pv="$(
        (bitbake -e "$recipe" 2>/dev/null || true) \
          | strip_notes \
          | awk -F= '$1=="PV"{gsub(/"/,"",$2); print $2; exit}' || true
      )"
      [[ -z "$pv" ]] && pv="-"
    fi
  fi

  printf "%-40s | %-22s | %-22s | %s\n" "$p" "$pkg" "$recipe" "$pv"
done
