#!/usr/bin/env bash
#
# check_fip_signed.sh
#
# Verify that the public keys embedded in TF-A key certificates inside the
# runtime signed FIP match the local OEM private keys stored in the
# tempercrate-secure-boot repository.
#
# Verified certificates:
#   - trusted-key-cert.bin
#       * Trusted World Key
#       * Non-Trusted World Key
#   - tos-fw-key-cert.bin
#       * TOS FW Key
#   - nt-fw-key-cert.bin
#       * NT FW Key
#
# This script does NOT verify certificate signatures.
# It verifies that the expected public keys are actually embedded in the
# certificate extensions.
#
# Usage:
#   cd /mnt/yocto/Home2/home2-workdir/build/tempercratelinux-stm32mp13-tempercrate-dev
#   ../../layers/meta-tempercrate/meta-tempercrate-os/scripts/check_fip_signed.sh
#
# Optional environment:
#   DEBUG_CHECK_FIP=1   Enable debug logging (default: 1)
#   DEBUG_CHECK_FIP=0   Disable debug logging
#   SECURE_BOOT_CONFIG_PATH=/custom/path/to/tempercrate-secure-boot
#                       Optional advanced override
#

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
CHECK_DIR="/tmp/checkfip"
DEBUG_ENABLED="${DEBUG_CHECK_FIP:-1}"

info()  { printf '[INFO] %s\n' "$*"; }
debug() { [[ "${DEBUG_ENABLED}" == "1" ]] && printf '[DEBUG] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
err()   { printf '[ERR ] %s\n' "$*" >&2; }
die()   { err "$*"; exit 1; }

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME

Run this script from a Yocto build directory.

Examples:
  cd /mnt/yocto/Home2/home2-workdir/build/tempercratelinux-stm32mp13-tempercrate-dev
  ../../layers/meta-tempercrate/meta-tempercrate-os/scripts/check_fip_signed.sh

Optional environment:
  DEBUG_CHECK_FIP=1   Enable debug logging (default: 1)
  DEBUG_CHECK_FIP=0   Disable debug logging

Advanced override:
  SECURE_BOOT_CONFIG_PATH=/custom/path/to/tempercrate-secure-boot
EOF
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1"
}

detect_secure_boot_repo() {
    local build_dir build_root candidate

    build_dir="$(pwd)"
    build_root="$(cd "${build_dir}/../.." && pwd)"
    candidate="${build_root}/tempercrate-secure-boot"

    if [[ -d "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return 0
    fi

    return 1
}

[[ $# -eq 0 ]] || { usage; exit 1; }

require_tool fiptool
require_tool openssl
require_tool find
require_tool awk
require_tool sed
require_tool sha256sum
require_tool cmp

if [[ -z "${SECURE_BOOT_CONFIG_PATH:-}" ]]; then
    if SECURE_BOOT_CONFIG_PATH="$(detect_secure_boot_repo)"; then
        export SECURE_BOOT_CONFIG_PATH
        info "Auto-detected SECURE_BOOT_CONFIG_PATH=${SECURE_BOOT_CONFIG_PATH}"
    else
        die "Unable to auto-detect tempercrate-secure-boot repository from current build directory"
    fi
else
    info "Using SECURE_BOOT_CONFIG_PATH override: ${SECURE_BOOT_CONFIG_PATH}"
fi

[[ -d "${SECURE_BOOT_CONFIG_PATH}" ]] || die "SECURE_BOOT_CONFIG_PATH does not exist: ${SECURE_BOOT_CONFIG_PATH}"

CONF_FILE="${SECURE_BOOT_CONFIG_PATH}/config/tempercrate-secureboot.conf"
[[ -f "${CONF_FILE}" ]] || die "Secure boot configuration file not found: ${CONF_FILE}"

# shellcheck disable=SC1090
source "${CONF_FILE}"

: "${TEMPERCRATE_SB_KEY_SUBDIR:?Missing TEMPERCRATE_SB_KEY_SUBDIR}"
: "${TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE:?Missing TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE}"
: "${TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE:?Missing TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE}"
: "${TEMPERCRATE_SB_TOS_FW_KEY_FILE:?Missing TEMPERCRATE_SB_TOS_FW_KEY_FILE}"
: "${TEMPERCRATE_SB_NT_FW_KEY_FILE:?Missing TEMPERCRATE_SB_NT_FW_KEY_FILE}"
: "${TEMPERCRATE_SB_SIGN_KEY_PASS:?Missing TEMPERCRATE_SB_SIGN_KEY_PASS}"

KEY_BASE_DIR="${SECURE_BOOT_CONFIG_PATH}/keys/${TEMPERCRATE_SB_KEY_SUBDIR}"

TRUSTED_WORLD_KEY="${KEY_BASE_DIR}/${TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE}"
NON_TRUSTED_WORLD_KEY="${KEY_BASE_DIR}/${TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE}"
TOS_FW_KEY="${KEY_BASE_DIR}/${TEMPERCRATE_SB_TOS_FW_KEY_FILE}"
NT_FW_KEY="${KEY_BASE_DIR}/${TEMPERCRATE_SB_NT_FW_KEY_FILE}"

for key_file in \
    "${TRUSTED_WORLD_KEY}" \
    "${NON_TRUSTED_WORLD_KEY}" \
    "${TOS_FW_KEY}" \
    "${NT_FW_KEY}"
do
    [[ -f "${key_file}" ]] || die "Key file not found: ${key_file}"
done

BUILD_DIR="$(pwd)"
DEPLOY_DIR="${BUILD_DIR}/tmp-glibc/deploy/images"
[[ -d "${DEPLOY_DIR}" ]] || die "Yocto deploy directory not found: ${DEPLOY_DIR}"

mapfile -t FIP_CANDIDATES < <(
    find "${DEPLOY_DIR}" -type f -path "*/fip/*-sdcard_Signed.bin" | sort
)

case "${#FIP_CANDIDATES[@]}" in
    0)
        die "No runtime FIP found under ${DEPLOY_DIR}"
        ;;
    1)
        FIP_FILE="${FIP_CANDIDATES[0]}"
        ;;
    *)
        printf '%s\n' "${FIP_CANDIDATES[@]}" >&2
        die "Multiple runtime FIP candidates found"
        ;;
esac

info "Using runtime FIP: ${FIP_FILE}"

info "Preparing working directory: ${CHECK_DIR}"
rm -rf "${CHECK_DIR}"
mkdir -p "${CHECK_DIR}/extracted"

info "FIP content summary"
(
    cd "${CHECK_DIR}"
    fiptool info "${FIP_FILE}"
)

info "Unpacking FIP into ${CHECK_DIR}"
(
    cd "${CHECK_DIR}"
    fiptool unpack "${FIP_FILE}"
)

debug "Unpacked files:"
find "${CHECK_DIR}" -maxdepth 1 -type f -printf '  %f\n' | sort

TRUSTED_KEY_CERT="${CHECK_DIR}/trusted-key-cert.bin"
TOS_FW_KEY_CERT="${CHECK_DIR}/tos-fw-key-cert.bin"
NT_FW_KEY_CERT="${CHECK_DIR}/nt-fw-key-cert.bin"

for cert in \
    "${TRUSTED_KEY_CERT}" \
    "${TOS_FW_KEY_CERT}" \
    "${NT_FW_KEY_CERT}"
do
    [[ -f "${cert}" ]] || die "Missing unpacked certificate: ${cert}"
done

priv_to_pub_der() {
    local priv="$1"
    local out_der="$2"

    openssl pkey \
        -in "${priv}" \
        -passin "pass:${TEMPERCRATE_SB_SIGN_KEY_PASS}" \
        -pubout \
        -outform DER \
        -out "${out_der}" >/dev/null 2>&1
}

file_sha256() {
    sha256sum "$1" | awk '{print $1}'
}

extract_tf_a_extensions() {
    local cert="$1"
    local out_dir="$2"

    mkdir -p "${out_dir}"
    rm -f "${out_dir}"/*

    openssl asn1parse -inform DER -in "${cert}" -i | awk '
        /1\.3\.6\.1\.4\.1\.4128\.2100\./ {
            oid=$NF
            sub(/^:/, "", oid)
            found=1
            next
        }
        found && /prim: *OCTET STRING/ {
            split($1, a, ":")
            print oid "|" a[1]
            found=0
        }
    ' | while IFS='|' read -r oid offset; do
        [[ -n "${oid}" && -n "${offset}" ]] || continue
        local_name="$(printf '%s' "${oid}" | tr '.' '_')"
        openssl asn1parse -inform DER -in "${cert}" -strparse "${offset}" \
            -out "${out_dir}/${local_name}.der" -noout >/dev/null
        printf '%s|%s\n' "${oid}" "${out_dir}/${local_name}.der"
    done
}

check_key_in_cert() {
    local cert="$1"
    local expected_der="$2"
    local expected_key_path="$3"
    local extract_dir="$4"

    local cert_name
    local matched_oid=""
    local matched_sha=""
    local found_any=0

    cert_name="$(basename "${cert}")"

    info "Checking certificate: ${cert_name}"
    debug "Expected key file   : ${expected_key_path}"
    debug "Expected key sha256 : $(file_sha256 "${expected_der}")"

    while IFS='|' read -r oid derfile; do
        [[ -n "${oid}" && -n "${derfile}" ]] || continue
        found_any=1

        if cmp -s "${derfile}" "${expected_der}"; then
            matched_oid="${oid}"
            matched_sha="$(file_sha256 "${derfile}")"
            break
        fi
    done < <(extract_tf_a_extensions "${cert}" "${extract_dir}")

    if [[ "${found_any}" -eq 0 ]]; then
        err "${cert_name} does not contain any TF-A proprietary key extension"
        echo
        return 1
    fi

    if [[ -n "${matched_oid}" ]]; then
        debug "Matched OID         : ${matched_oid}"
        debug "Matched key sha256  : ${matched_sha}"
        info "${cert_name} contains the expected key (${expected_key_path})"
        echo
        return 0
    fi

    err "${cert_name} does NOT contain the expected key (${expected_key_path})"
    echo
    return 1
}

EXPECTED_TW="${CHECK_DIR}/trusted_world_expected.der"
EXPECTED_NTW="${CHECK_DIR}/non_trusted_world_expected.der"
EXPECTED_TOS="${CHECK_DIR}/tos_fw_expected.der"
EXPECTED_NTFW="${CHECK_DIR}/nt_fw_expected.der"

priv_to_pub_der "${TRUSTED_WORLD_KEY}"     "${EXPECTED_TW}"
priv_to_pub_der "${NON_TRUSTED_WORLD_KEY}" "${EXPECTED_NTW}"
priv_to_pub_der "${TOS_FW_KEY}"            "${EXPECTED_TOS}"
priv_to_pub_der "${NT_FW_KEY}"             "${EXPECTED_NTFW}"

debug "Expected local public keys:"
debug "  TRUSTED_WORLD_KEY     sha256=$(file_sha256 "${EXPECTED_TW}") file=${TRUSTED_WORLD_KEY}"
debug "  NON_TRUSTED_WORLD_KEY sha256=$(file_sha256 "${EXPECTED_NTW}") file=${NON_TRUSTED_WORLD_KEY}"
debug "  TOS_FW_KEY            sha256=$(file_sha256 "${EXPECTED_TOS}") file=${TOS_FW_KEY}"
debug "  NT_FW_KEY             sha256=$(file_sha256 "${EXPECTED_NTFW}") file=${NT_FW_KEY}"

FAIL=0

check_key_in_cert \
    "${TRUSTED_KEY_CERT}" \
    "${EXPECTED_TW}" \
    "${TRUSTED_WORLD_KEY}" \
    "${CHECK_DIR}/extracted/trusted_key_cert" || FAIL=1

check_key_in_cert \
    "${TRUSTED_KEY_CERT}" \
    "${EXPECTED_NTW}" \
    "${NON_TRUSTED_WORLD_KEY}" \
    "${CHECK_DIR}/extracted/trusted_key_cert" || FAIL=1

check_key_in_cert \
    "${TOS_FW_KEY_CERT}" \
    "${EXPECTED_TOS}" \
    "${TOS_FW_KEY}" \
    "${CHECK_DIR}/extracted/tos_fw_key_cert" || FAIL=1

check_key_in_cert \
    "${NT_FW_KEY_CERT}" \
    "${EXPECTED_NTFW}" \
    "${NT_FW_KEY}" \
    "${CHECK_DIR}/extracted/nt_fw_key_cert" || FAIL=1

echo "============================================================"
if [[ "${FAIL}" -eq 0 ]]; then
    info "TF-A Chain of Trust embedded key verification SUCCESSFUL"
    echo "============================================================"
    exit 0
else
    err "TF-A Chain of Trust embedded key verification FAILED"
    echo "============================================================"
    exit 2
fi