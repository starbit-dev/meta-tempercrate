#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script must be sourced, not executed."
    echo "Use:"
    echo "  source ${0}"
    exit 1
fi

_tempercrate_sb_warn() {
    echo "WARNING: [tempercrate-secureboot] $*" >&2
}

_tempercrate_sb_err() {
    echo "ERROR: [tempercrate-secureboot] $*" >&2
}

_tempercrate_sb_info() {
    echo "[tempercrate-secureboot] $*"
}

_tempercrate_sb_require_file() {
    local file="$1"
    [[ -f "$file" ]] || {
        _tempercrate_sb_err "Required file not found: $file"
        return 1
    }
}

_tempercrate_sb_require_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || {
        _tempercrate_sb_err "Required directory not found: $dir"
        return 1
    }
}

_tempercrate_sb_add_passthrough_var() {
    local var_name="$1"

    case " ${BB_ENV_PASSTHROUGH_ADDITIONS:-} " in
        *" ${var_name} "*) ;;
        *)
            BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} ${var_name}"
            ;;
    esac
}

_tempercrate_sb_reset_env() {
    unset TEMPERCRATE_SB_ENABLE
    unset TEMPERCRATE_SB_VERBOSE_TFA
    unset TEMPERCRATE_SB_KEY_SUBDIR
    unset TEMPERCRATE_SB_KEY_DIR

    unset TEMPERCRATE_SB_SIGN_TOOL
    unset TEMPERCRATE_SB_SIGN_KEY_PASS
    unset TEMPERCRATE_SB_SIGN_KEY_FILE
    unset TEMPERCRATE_SB_SIGN_KEY

    unset TEMPERCRATE_SB_ROOT_KEY_FILE
    unset TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE
    unset TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE
    unset TEMPERCRATE_SB_TOS_FW_KEY_FILE
    unset TEMPERCRATE_SB_NT_FW_KEY_FILE
    unset TEMPERCRATE_SB_SOC_FW_KEY_FILE
    unset TEMPERCRATE_SB_SCP_FW_KEY_FILE

    unset TEMPERCRATE_SB_ROOT_KEY
    unset TEMPERCRATE_SB_TRUSTED_WORLD_KEY
    unset TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY
    unset TEMPERCRATE_SB_TOS_FW_KEY
    unset TEMPERCRATE_SB_NT_FW_KEY
    unset TEMPERCRATE_SB_SOC_FW_KEY
    unset TEMPERCRATE_SB_SCP_FW_KEY

    unset SIGN_ENABLE
    unset SIGN_TOOL
    unset SIGN_KEY
    unset SIGN_KEY_PASS
    unset TRUSTED_BOARD_BOOT
    unset GENERATE_COT
}

_tempercrate_sb_require_nonempty() {
    local var_name="$1"
    local var_value="$2"
    local cfg_file="$3"

    [[ -n "${var_value}" ]] || {
        _tempercrate_sb_err "${var_name} is not set in ${cfg_file}"
        return 1
    }
}

_tempercrate_sb_detect_default_config_path() {
    local script_dir workdir candidate

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    workdir="$(cd "${script_dir}/../../../.." && pwd)"
    candidate="${workdir}/tempercrate-secure-boot"

    if [[ -d "${candidate}" ]]; then
        echo "${candidate}"
        return 0
    fi

    return 1
}

_tempercrate_sb_reset_env

# Priority:
# 1. SECURE_BOOT_CONFIG_PATH already exported by caller (advanced override)
# 2. auto-detect from current workspace layout: <home2-workdir>/tempercrate-secure-boot
if [[ -z "${SECURE_BOOT_CONFIG_PATH:-}" ]]; then
    if detected_path="$(_tempercrate_sb_detect_default_config_path)"; then
        export SECURE_BOOT_CONFIG_PATH="${detected_path}"
        _tempercrate_sb_info "Auto-detected SECURE_BOOT_CONFIG_PATH=${SECURE_BOOT_CONFIG_PATH}"
    else
        export TEMPERCRATE_SB_ENABLE="0"
        _tempercrate_sb_warn "Unable to auto-detect tempercrate-secure-boot repository. Secure Boot is disabled."
        _tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_ENABLE"
        export BB_ENV_PASSTHROUGH_ADDITIONS
        return 0
    fi
else
    _tempercrate_sb_info "Secure Boot configuration detected: ${SECURE_BOOT_CONFIG_PATH}"
fi

TEMPERCRATE_SB_CONFIG_DIR="${SECURE_BOOT_CONFIG_PATH}/config"
TEMPERCRATE_SB_CONFIG_FILE="${TEMPERCRATE_SB_CONFIG_DIR}/tempercrate-secureboot.conf"
TEMPERCRATE_SB_KEYS_ROOT="${SECURE_BOOT_CONFIG_PATH}/keys"

if [[ ! -d "${SECURE_BOOT_CONFIG_PATH}" ]]; then
    export TEMPERCRATE_SB_ENABLE="0"
    _tempercrate_sb_warn "Secure Boot repository not found at ${SECURE_BOOT_CONFIG_PATH}. Secure Boot is disabled."
    _tempercrate_sb_add_passthrough_var "SECURE_BOOT_CONFIG_PATH"
    _tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_ENABLE"
    export BB_ENV_PASSTHROUGH_ADDITIONS
    return 0
fi

if [[ ! -d "${TEMPERCRATE_SB_CONFIG_DIR}" ]] || [[ ! -f "${TEMPERCRATE_SB_CONFIG_FILE}" ]]; then
    export TEMPERCRATE_SB_ENABLE="0"
    _tempercrate_sb_warn "Secure Boot configuration file not found at ${TEMPERCRATE_SB_CONFIG_FILE}. Secure Boot is disabled."
    _tempercrate_sb_add_passthrough_var "SECURE_BOOT_CONFIG_PATH"
    _tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_ENABLE"
    export BB_ENV_PASSTHROUGH_ADDITIONS
    return 0
fi

# shellcheck disable=SC1090
source "${TEMPERCRATE_SB_CONFIG_FILE}"

export TEMPERCRATE_SB_ENABLE="${TEMPERCRATE_SB_ENABLE:-0}"
export TEMPERCRATE_SB_VERBOSE_TFA="${TEMPERCRATE_SB_VERBOSE_TFA:-0}"

_tempercrate_sb_add_passthrough_var "SECURE_BOOT_CONFIG_PATH"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_ENABLE"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_VERBOSE_TFA"

if [[ "${TEMPERCRATE_SB_ENABLE}" != "1" ]]; then
    unset TEMPERCRATE_SB_KEY_SUBDIR
    unset TEMPERCRATE_SB_KEY_DIR
    unset TEMPERCRATE_SB_SIGN_TOOL
    unset TEMPERCRATE_SB_SIGN_KEY_PASS
    unset TEMPERCRATE_SB_SIGN_KEY_FILE
    unset TEMPERCRATE_SB_SIGN_KEY
    unset TEMPERCRATE_SB_ROOT_KEY_FILE
    unset TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE
    unset TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE
    unset TEMPERCRATE_SB_TOS_FW_KEY_FILE
    unset TEMPERCRATE_SB_NT_FW_KEY_FILE
    unset TEMPERCRATE_SB_SOC_FW_KEY_FILE
    unset TEMPERCRATE_SB_SCP_FW_KEY_FILE
    unset TEMPERCRATE_SB_ROOT_KEY
    unset TEMPERCRATE_SB_TRUSTED_WORLD_KEY
    unset TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY
    unset TEMPERCRATE_SB_TOS_FW_KEY
    unset TEMPERCRATE_SB_NT_FW_KEY
    unset TEMPERCRATE_SB_SOC_FW_KEY
    unset TEMPERCRATE_SB_SCP_FW_KEY

    export BB_ENV_PASSTHROUGH_ADDITIONS
    _tempercrate_sb_info "Secure Boot is DISABLED."

    unset TEMPERCRATE_SB_CONFIG_DIR
    unset TEMPERCRATE_SB_CONFIG_FILE
    unset TEMPERCRATE_SB_KEYS_ROOT
    return 0
fi

_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_KEY_SUBDIR" "${TEMPERCRATE_SB_KEY_SUBDIR:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1
_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_SIGN_KEY_PASS" "${TEMPERCRATE_SB_SIGN_KEY_PASS:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1
_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_SIGN_KEY_FILE" "${TEMPERCRATE_SB_SIGN_KEY_FILE:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1

_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_ROOT_KEY_FILE" "${TEMPERCRATE_SB_ROOT_KEY_FILE:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1
_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE" "${TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1
_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE" "${TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1
_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_TOS_FW_KEY_FILE" "${TEMPERCRATE_SB_TOS_FW_KEY_FILE:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1
_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_NT_FW_KEY_FILE" "${TEMPERCRATE_SB_NT_FW_KEY_FILE:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1
_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_SOC_FW_KEY_FILE" "${TEMPERCRATE_SB_SOC_FW_KEY_FILE:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1
_tempercrate_sb_require_nonempty "TEMPERCRATE_SB_SCP_FW_KEY_FILE" "${TEMPERCRATE_SB_SCP_FW_KEY_FILE:-}" "${TEMPERCRATE_SB_CONFIG_FILE}" || return 1

export TEMPERCRATE_SB_KEY_DIR="${TEMPERCRATE_SB_KEYS_ROOT}/${TEMPERCRATE_SB_KEY_SUBDIR}"

_tempercrate_sb_require_dir "${TEMPERCRATE_SB_KEYS_ROOT}" || return 1
_tempercrate_sb_require_dir "${TEMPERCRATE_SB_KEY_DIR}" || return 1
_tempercrate_sb_require_dir "${TEMPERCRATE_SB_KEY_DIR}/rootset" || return 1
_tempercrate_sb_require_dir "${TEMPERCRATE_SB_KEY_DIR}/cot" || return 1

export TEMPERCRATE_SB_SIGN_KEY="${TEMPERCRATE_SB_KEY_DIR}/${TEMPERCRATE_SB_SIGN_KEY_FILE}"

export TEMPERCRATE_SB_ROOT_KEY="${TEMPERCRATE_SB_KEY_DIR}/${TEMPERCRATE_SB_ROOT_KEY_FILE}"
export TEMPERCRATE_SB_TRUSTED_WORLD_KEY="${TEMPERCRATE_SB_KEY_DIR}/${TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE}"
export TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY="${TEMPERCRATE_SB_KEY_DIR}/${TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE}"
export TEMPERCRATE_SB_TOS_FW_KEY="${TEMPERCRATE_SB_KEY_DIR}/${TEMPERCRATE_SB_TOS_FW_KEY_FILE}"
export TEMPERCRATE_SB_NT_FW_KEY="${TEMPERCRATE_SB_KEY_DIR}/${TEMPERCRATE_SB_NT_FW_KEY_FILE}"
export TEMPERCRATE_SB_SOC_FW_KEY="${TEMPERCRATE_SB_KEY_DIR}/${TEMPERCRATE_SB_SOC_FW_KEY_FILE}"
export TEMPERCRATE_SB_SCP_FW_KEY="${TEMPERCRATE_SB_KEY_DIR}/${TEMPERCRATE_SB_SCP_FW_KEY_FILE}"

_tempercrate_sb_require_file "${TEMPERCRATE_SB_SIGN_KEY}" || return 1
_tempercrate_sb_require_file "${TEMPERCRATE_SB_ROOT_KEY}" || return 1
_tempercrate_sb_require_file "${TEMPERCRATE_SB_TRUSTED_WORLD_KEY}" || return 1
_tempercrate_sb_require_file "${TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY}" || return 1
_tempercrate_sb_require_file "${TEMPERCRATE_SB_TOS_FW_KEY}" || return 1
_tempercrate_sb_require_file "${TEMPERCRATE_SB_NT_FW_KEY}" || return 1
_tempercrate_sb_require_file "${TEMPERCRATE_SB_SOC_FW_KEY}" || return 1
_tempercrate_sb_require_file "${TEMPERCRATE_SB_SCP_FW_KEY}" || return 1

if [[ -z "${TEMPERCRATE_SB_SIGN_TOOL:-}" ]]; then
    TEMPERCRATE_SB_SIGN_TOOL="$(command -v STM32_SigningTool_CLI || true)"
fi

[[ -n "${TEMPERCRATE_SB_SIGN_TOOL:-}" ]] || {
    _tempercrate_sb_err "TEMPERCRATE_SB_SIGN_TOOL is empty and STM32_SigningTool_CLI was not found in PATH"
    return 1
}

_tempercrate_sb_require_file "${TEMPERCRATE_SB_SIGN_TOOL}" || return 1
export TEMPERCRATE_SB_SIGN_TOOL

_tempercrate_sb_require_file "${TEMPERCRATE_SB_KEY_DIR}/rootset/publicKey00.pem" || return 1
_tempercrate_sb_require_file "${TEMPERCRATE_SB_KEY_DIR}/rootset/publicKeysHashHashes.bin" || return 1

_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_KEY_SUBDIR"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_KEY_DIR"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_SIGN_TOOL"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_SIGN_KEY_PASS"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_SIGN_KEY_FILE"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_SIGN_KEY"

_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_ROOT_KEY_FILE"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_TRUSTED_WORLD_KEY_FILE"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY_FILE"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_TOS_FW_KEY_FILE"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_NT_FW_KEY_FILE"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_SOC_FW_KEY_FILE"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_SCP_FW_KEY_FILE"

_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_ROOT_KEY"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_TRUSTED_WORLD_KEY"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_TOS_FW_KEY"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_NT_FW_KEY"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_SOC_FW_KEY"
_tempercrate_sb_add_passthrough_var "TEMPERCRATE_SB_SCP_FW_KEY"

export BB_ENV_PASSTHROUGH_ADDITIONS

_tempercrate_sb_info "Secure Boot is ENABLED."
_tempercrate_sb_info "SECURE_BOOT_CONFIG_PATH=${SECURE_BOOT_CONFIG_PATH}"
_tempercrate_sb_info "TEMPERCRATE_SB_SIGN_KEY=${TEMPERCRATE_SB_SIGN_KEY}"
_tempercrate_sb_info "TEMPERCRATE_SB_ROOT_KEY=${TEMPERCRATE_SB_ROOT_KEY}"

unset TEMPERCRATE_SB_CONFIG_DIR
unset TEMPERCRATE_SB_CONFIG_FILE
unset TEMPERCRATE_SB_KEYS_ROOT

return 0