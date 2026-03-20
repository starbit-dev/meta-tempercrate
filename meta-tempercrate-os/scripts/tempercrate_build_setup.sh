#!/usr/bin/env bash

# This script must be sourced:
#   source layers/meta-tempercrate/meta-tempercrate-os/scripts/tempercrate_build_setup.sh
# or:
#   source layers/meta-tempercrate/meta-tempercrate-os/scripts/tempercrate_build_setup.sh stm32mp13-tempercrate-prod

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: this script must be sourced, not executed."
    echo "Use:"
    echo "  source ${0}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

POKY_INIT="${WORKDIR}/layers/openembedded-core/oe-init-build-env"
TEMPLATECONF_DIR="${WORKDIR}/layers/meta-tempercrate/meta-tempercrate-os/conf/templates/tempercrate"
SECUREBOOT_CFG_SCRIPT="${WORKDIR}/layers/meta-tempercrate/meta-tempercrate-os/scripts/tempercrate_secureboot_cfg.sh"

BUILD_ROOT_DIR="${WORKDIR}/build"
DOWNLOAD_DIR="${WORKDIR}/downloads"
SSTATE_DIR="${WORKDIR}/sstate-cache"

DEV_MACHINE="stm32mp13-tempercrate-dev"
PROD_MACHINE="stm32mp13-tempercrate-prod"

DEV_BUILD_DIR="${BUILD_ROOT_DIR}/tempercratelinux-${DEV_MACHINE}"
PROD_BUILD_DIR="${BUILD_ROOT_DIR}/tempercratelinux-${PROD_MACHINE}"

SELECTED_MACHINE="${1:-${DEV_MACHINE}}"

case "${SELECTED_MACHINE}" in
    "${DEV_MACHINE}")
        SELECTED_BUILD_DIR="${DEV_BUILD_DIR}"
        ;;
    "${PROD_MACHINE}")
        SELECTED_BUILD_DIR="${PROD_BUILD_DIR}"
        ;;
    *)
        echo "ERROR: unsupported machine '${SELECTED_MACHINE}'"
        echo "Supported machines:"
        echo "  - ${DEV_MACHINE}"
        echo "  - ${PROD_MACHINE}"
        return 1
        ;;
esac

if [ ! -f "${POKY_INIT}" ]; then
    echo "ERROR: oe-init-build-env not found: ${POKY_INIT}"
    return 1
fi

if [ ! -d "${TEMPLATECONF_DIR}" ]; then
    echo "ERROR: template conf directory not found: ${TEMPLATECONF_DIR}"
    return 1
fi

if [ ! -f "${SECUREBOOT_CFG_SCRIPT}" ]; then
    echo "ERROR: Secure Boot config script not found: ${SECUREBOOT_CFG_SCRIPT}"
    return 1
fi

mkdir -p "${BUILD_ROOT_DIR}" || return 1
mkdir -p "${DOWNLOAD_DIR}" || return 1
mkdir -p "${SSTATE_DIR}" || return 1

echo "==================================="
echo "===== TemperCrate Yocto Build Setup ======"
echo "==================================="
echo "Script dir         : ${SCRIPT_DIR}"
echo "Workdir            : ${WORKDIR}"
echo "Build root dir     : ${BUILD_ROOT_DIR}"
echo "Download directory : ${DOWNLOAD_DIR}"
echo "Sstate cache       : ${SSTATE_DIR}"
echo "Template conf      : ${TEMPLATECONF_DIR}"
echo "SecureBoot script  : ${SECUREBOOT_CFG_SCRIPT}"
echo "Dev build dir      : ${DEV_BUILD_DIR}"
echo "Prod build dir     : ${PROD_BUILD_DIR}"
echo "Selected machine   : ${SELECTED_MACHINE}"
echo "Selected build dir : ${SELECTED_BUILD_DIR}"

create_build_dir() {
    local machine="$1"
    local build_dir="$2"
    local helper

    echo
    echo "Preparing build directory for ${machine}: ${build_dir}"

    mkdir -p "${build_dir}" || return 1

    helper="$(mktemp)" || return 1

    cat > "${helper}" <<EOF
#!/usr/bin/env bash
set -e
export TEMPLATECONF="${TEMPLATECONF_DIR}"
source "${POKY_INIT}" "${build_dir}" > /dev/null

if [ ! -f "${build_dir}/conf/local.conf" ]; then
    echo "ERROR: local.conf was not created in ${build_dir}/conf"
    exit 1
fi

if [ ! -f "${build_dir}/conf/bblayers.conf" ]; then
    echo "ERROR: bblayers.conf was not created in ${build_dir}/conf"
    exit 1
fi

if grep -q '^MACHINE ??=' "${build_dir}/conf/local.conf"; then
    sed -i 's/^MACHINE ??=.*/MACHINE ??= "${machine}"/' "${build_dir}/conf/local.conf"
else
    echo 'MACHINE ??= "${machine}"' >> "${build_dir}/conf/local.conf"
fi
EOF

    chmod +x "${helper}" || return 1
    bash "${helper}" || {
        rm -f "${helper}"
        return 1
    }
    rm -f "${helper}" || return 1

    echo "Build directory ready for ${machine}"
}

create_build_dir "${DEV_MACHINE}" "${DEV_BUILD_DIR}" || return 1
create_build_dir "${PROD_MACHINE}" "${PROD_BUILD_DIR}" || return 1

echo
echo "Activating selected build environment: ${SELECTED_MACHINE}"

export TEMPLATECONF="${TEMPLATECONF_DIR}"

# oe-init-build-env is not compatible with 'set -u'
__TEMPERCRATE_RESTORE_NOUNSET=0
if [[ $- == *u* ]]; then
    __TEMPERCRATE_RESTORE_NOUNSET=1
    set +u
fi

# shellcheck disable=SC1090
source "${POKY_INIT}" "${SELECTED_BUILD_DIR}"

if [ "${__TEMPERCRATE_RESTORE_NOUNSET}" -eq 1 ]; then
    set -u
fi
unset __TEMPERCRATE_RESTORE_NOUNSET

echo
echo "Loading TemperCrate Secure Boot configuration..."

# shellcheck disable=SC1090
source "${SECUREBOOT_CFG_SCRIPT}" || return 1

echo
echo "==================================="
echo "Environment ready."
echo
echo "Current machine : ${SELECTED_MACHINE}"
echo "Build directory : ${SELECTED_BUILD_DIR}"
echo "Downloads       : ${DOWNLOAD_DIR}"
echo "Sstate cache    : ${SSTATE_DIR}"
echo

if [ "${TEMPERCRATE_SB_ENABLE:-0}" = "1" ]; then
    echo "Secure Boot     : ENABLED"
    echo "SB config path  : ${SECURE_BOOT_CONFIG_PATH}"
else
    echo "Secure Boot     : DISABLED"
fi

echo
echo "To build the image run:"
echo "  bitbake tempercrate-image-core"
echo
echo "To switch to the production board run:"
echo "  source layers/meta-tempercrate/meta-tempercrate-os/scripts/tempercrate_build_setup.sh ${PROD_MACHINE}"
echo
echo "Then build with:"
echo "  bitbake tempercrate-image-core"
echo "==================================="
echo