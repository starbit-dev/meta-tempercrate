#!/usr/bin/env bash
#===============================================================================
#
#          FILE: create_tempercrate_sdcard_image_fixed.sh
#
#         USAGE: ./create_tempercrate_sdcard_image_fixed.sh [--compress] [--force-rootfs] <FlashLayout.tsv>
#
#   DESCRIPTION: Generate a raw SD card image from an STM32 FlashLayout TSV file.
#                This version is a hardened rewrite of the original script:
#                  - robust TSV parsing using tab separators only
#                  - safer shell options and quoting
#                  - correct handling of sparse raw image creation
#                  - correct partition end computation even when optional rows exist
#                  - clearer diagnostics in both normal and DEBUG modes
#                  - stronger validation of offsets, files, and partition sizes
#
# SPDX-License-Identifier: MIT
#        AUTHOR: OpenAI rewrite based on original STMicroelectronics-derived script
#===============================================================================

set -u
set -o pipefail
#DEBUG=1

PRE_REQUISITE_TOOLS=(
    sgdisk
    du
    dd
    awk
    grep
    sed
    basename
    dirname
    xz
)


SDCARD_TOKEN="mmc0"

# Default raw image size in MiB.
DEFAULT_RAW_SIZE=${SDCARD_SIZE:-5120}

# Default forced rootfs partition size in KiB (same semantic as the original script).
DEFAULT_ROOTFS_PARTITION_SIZE=${ROOTFS_SIZE:-753664}

# Padding added after rootfs when auto-growing it.
DEFAULT_PADDING_SIZE=33554432

DEFAULT_SDCARD_PARTUUID="e91c4e10-16e6-4c0e-bd0e-77becf4a3582"
DEFAULT_FIP_TYPEUUID="19d5df83-11b0-457b-be2c-7559c13142a5"
DEFAULT_FIP_A_PARTUUID="4fd84c93-54ef-463f-a7ef-ae25ff887087"
DEFAULT_FIP_B_PARTUUID="09c54952-d5bf-45af-acee-335303766fb3"
DEFAULT_FWU_MDATA_TYPEUUID="8a7a84a0-8387-40f6-ab41-a8b9a5a60d23"
DEFAULT_UBOOT_ENV_TYPEUUID="3de21764-95bd-54bd-a5c3-4abe786f38a8"

WARNING_TEXT=""
_COMPRESS_RAW_IMAGE=0
_FORCE_ROOTFS_SIZE=0

# Device name used only in the human-readable helper file.
DEFAULT_DEVICE=${DEVICE:-mmcblk0}
if [[ "$DEFAULT_DEVICE" == *mmcblk* ]]; then
    DEFAULT_DEVICE_PART="${DEFAULT_DEVICE}p"
else
    DEFAULT_DEVICE_PART="$DEFAULT_DEVICE"
fi

# Global paths.
FLASHLAYOUT_filename=""
FLASHLAYOUT_filename_path=""
FLASHLAYOUT_prefix_image_path=""
FLASHLAYOUT_rawname=""
FLASHLAYOUT_infoname=""

# Parsed FlashLayout rows.
# Every field is stored by row index in a dedicated indexed array.
declare -a FL_SELECTED=()
declare -a FL_PARTID=()
declare -a FL_PARTNAME=()
declare -a FL_PARTTYPE=()
declare -a FL_IP=()
declare -a FL_OFFSET=()
declare -a FL_BIN2FLASH=()
declare -a FL_BIN2BOOT=()
FL_COUNT=0

_REDIRECT="/dev/stdout"
if [[ -z "${DEBUG:-}" ]]; then
    _REDIRECT="/dev/null"
    exec 2>/dev/null
fi

# -----------------------------------
die() {
    echo "$*" >&2
    exit 1
}

info() {
    echo "$*"
}

debug() {
    if [[ -n "${DEBUG:-}" ]]; then
        echo ""
        echo "[DEBUG]: $*"
    fi
}

exec_print() {
    if [[ -n "${DEBUG:-}" ]]; then
        echo ""
        echo "[DEBUG EXEC]: $*"
    fi
}

selection_test() {
    local select="$1"
    shift
    local candidate
    for candidate in "$@"; do
        if [[ "$select" == "$candidate" ]]; then
            return 0
        fi
    done
    return 1
}

tools_check() {
    local tool
    for tool in "${PRE_REQUISITE_TOOLS[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            die "[ERROR]: required tool '$tool' was not found in PATH"
        fi
    done
}

is_programmed_row() {
    local idx="$1"
    [[ "${FL_IP[$idx]}" == "$SDCARD_TOKEN" ]] || return 1
    selection_test "${FL_SELECTED[$idx]}" P E PD DP PE PED
}

is_populated_row() {
    local idx="$1"
    [[ "${FL_IP[$idx]}" == "$SDCARD_TOKEN" ]] || return 1
    selection_test "${FL_SELECTED[$idx]}" P PD DP PE PED
}

hex_to_dec() {
    local value="$1"
    value="${value#0x}"
    value="${value#0X}"
    [[ -n "$value" ]] || die "Internal error: empty hexadecimal value"
    printf '%d\n' "$((16#$value))"
}

bytes_to_lba() {
    local bytes="$1"
    # 512-byte logical sectors.
    printf '%d\n' "$((bytes / 512))"
}

find_next_partition_index() {
    local idx="$1"
    local k
    for ((k = idx + 1; k < FL_COUNT; k++)); do
        if is_programmed_row "$k"; then
            echo "$k"
            return 0
        fi
    done
    echo "-1"
    return 0
}

get_image_size_bytes() {
    local relpath="$1"
    if [[ -z "$relpath" || "$relpath" == "none" ]]; then
        echo 0
        return 0
    fi

    local fullpath="$FLASHLAYOUT_prefix_image_path/$relpath"
    if [[ -e "$fullpath" ]]; then
        du -Lb "$fullpath" | awk '{print $1}'
    else
        echo 0
    fi
}

resolve_image_prefix() {
    local probes=(
        "$FLASHLAYOUT_filename_path"
        "$FLASHLAYOUT_filename_path/.."
        "$FLASHLAYOUT_filename_path/../.."
        "$FLASHLAYOUT_filename_path/../../.."
    )

    local last_image=""
    local i
    for ((i = 0; i < FL_COUNT; i++)); do
        if [[ "${FL_IP[$i]}" == "$SDCARD_TOKEN" ]]; then
            case "${FL_PARTNAME[$i]}" in
                rootfs|rootfs-a)
                    last_image="${FL_BIN2FLASH[$i]}"
                    ;;
            esac
        fi
    done

    if [[ -z "$last_image" ]]; then
        FLASHLAYOUT_prefix_image_path="."
        return 0
    fi

    local probe
    for probe in "${probes[@]}"; do
        if [[ -f "$probe/$last_image" ]]; then
            FLASHLAYOUT_prefix_image_path="$probe"
            return 0
        fi
    done

    die "[ERROR]: could not find image '$last_image' near '$FLASHLAYOUT_filename_path'"
}

read_flash_layout() {
    local line
    local idx=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim trailing CR for Windows-formatted files.
        line="${line%$'\r'}"

        # Skip empty lines and comments.
        [[ -n "$line" ]] || continue
        [[ "$line" =~ ^# ]] && continue

        local selected partid partname parttype ip offset bin2flash bin2boot extra
        IFS=$'\t' read -r selected partid partname parttype ip offset bin2flash bin2boot extra <<< "$line"

        # Skip malformed rows silently only if they are clearly not data rows.
        [[ -n "$selected" && -n "$partname" ]] || continue

        if selection_test "$selected" P E PD DP PE PED; then
            FL_SELECTED[idx]="$selected"
            FL_PARTID[idx]="$partid"
            FL_PARTNAME[idx]="$partname"
            FL_PARTTYPE[idx]="$parttype"
            FL_IP[idx]="$ip"
            FL_OFFSET[idx]="$offset"
            FL_BIN2FLASH[idx]="${bin2flash:-}"
            FL_BIN2BOOT[idx]="${bin2boot:-}"
            debug "READ[$idx]: $selected $partid $partname $parttype $ip $offset ${bin2flash:-}"
            ((idx++))
        fi
    done < "$FLASHLAYOUT_filename"

    FL_COUNT=$idx
    [[ $FL_COUNT -gt 0 ]] || die "[ERROR]: no programmable rows found in '$FLASHLAYOUT_filename'"
    debug "Parsed programmable rows: $FL_COUNT"
}

calculate_number_of_partition() {
    local count=0
    local i
    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            ((count++))
        fi
    done
    echo "$count"
}

move_partition_offset() {
    local start_index="$1"
    local new_offset_b="$2"
    local k

    for ((k = start_index; k < FL_COUNT; k++)); do
        if ! is_programmed_row "$k"; then
            continue
        fi

        local next_idx
        next_idx=$(find_next_partition_index "$k")
        local current_offset_b
        current_offset_b=$(hex_to_dec "${FL_OFFSET[$k]}")

        local part_size_b=0
        if [[ "$next_idx" != "-1" ]]; then
            local next_offset_b
            next_offset_b=$(hex_to_dec "${FL_OFFSET[$next_idx]}")
            part_size_b=$((next_offset_b - current_offset_b))
            ((part_size_b >= 0)) || die "Internal error: negative partition size while moving offsets"
        fi

        debug "${FL_PARTNAME[$k]}: Change Offset from ${FL_OFFSET[$k]} to $(printf '0x%x' "$new_offset_b")"
        FL_OFFSET[$k]="$(printf '0x%x' "$new_offset_b")"

        if [[ "$next_idx" != "-1" ]]; then
            new_offset_b=$((new_offset_b + part_size_b))
        fi
    done
}

generate_empty_raw_image() {
    info "Create Raw empty image: '$FLASHLAYOUT_rawname' of ${DEFAULT_RAW_SIZE}MB"
    exec_print "dd if=/dev/zero of='$FLASHLAYOUT_rawname' bs=1M count=0 seek=${DEFAULT_RAW_SIZE}"
    dd if=/dev/zero of="$FLASHLAYOUT_rawname" bs=1M count=0 seek="$DEFAULT_RAW_SIZE" &>"$_REDIRECT" \
        || die "DD: failed to create empty raw image '$FLASHLAYOUT_rawname'"
}

generate_gpt_partition_table_from_flash_layout() {
    local part_no=1
    local visible_index=0
    local number_of_partition
    number_of_partition=$(calculate_number_of_partition)

    local display_info=""
    local index_of_rootfs=-1

    exec_print "sgdisk -og -a 1 '$FLASHLAYOUT_rawname'"
    sgdisk -og -a 1 "$FLASHLAYOUT_rawname" &>"$_REDIRECT" \
        || die "SGDISK: failed to create GPT on '$FLASHLAYOUT_rawname'"

    info "Create partition table:"

    local i
    for ((i = 0; i < FL_COUNT; i++)); do
        if ! is_programmed_row "$i"; then
            continue
        fi

        local partName="${FL_PARTNAME[$i]}"
        local partType="${FL_PARTTYPE[$i]}"
        local bin2flash="${FL_BIN2FLASH[$i]}"
        local offset_b
        offset_b=$(hex_to_dec "${FL_OFFSET[$i]}")
        local start_lba
        start_lba=$(bytes_to_lba "$offset_b")

        local image_size
        image_size=$(get_image_size_bytes "$bin2flash")
        local image_size_in_mb=$((image_size / 1024 / 1024))

        local extrafs_param=""
        case "$partName" in
            boot|bootfs|boot-a)
                extrafs_param="-A ${part_no}:set:2"
                ;;
            rootfs|rootfs-a)
                extrafs_param="-u ${part_no}:${DEFAULT_SDCARD_PARTUUID}"
                display_info+=" ${part_no}"
                ;;
            fip-a*)
                extrafs_param="-u ${part_no}:${DEFAULT_FIP_A_PARTUUID}"
                display_info+=" ${part_no}"
                ;;
            fip-b*)
                extrafs_param="-u ${part_no}:${DEFAULT_FIP_B_PARTUUID}"
                display_info+=" ${part_no}"
                ;;
        esac

        local next_idx
        next_idx=$(find_next_partition_index "$i")

        local end_lba=""
        local partition_size=0
        local free_size=0
        local next_offset_b=0

        if [[ "$next_idx" != "-1" ]]; then
            next_offset_b=$(hex_to_dec "${FL_OFFSET[$next_idx]}")

            if [[ "$partName" == "rootfs" || "$partName" == "rootfs-a" ]]; then
                if [[ $_FORCE_ROOTFS_SIZE -eq 1 ]]; then
                    next_offset_b=$((offset_b + 1024 * DEFAULT_ROOTFS_PARTITION_SIZE))
                    move_partition_offset "$next_idx" "$next_offset_b"
                fi
                index_of_rootfs=$i
            fi

            if [[ $index_of_rootfs -ge 0 && $i -gt $index_of_rootfs ]]; then
                if (( next_offset_b + image_size > DEFAULT_RAW_SIZE * 1024 * 1024 )); then
                    die "[ERROR]: the rootfs and/or following partitions do not fit in ${DEFAULT_RAW_SIZE} MB"
                fi
            fi

            end_lba=$(bytes_to_lba "$next_offset_b")
            end_lba=$((end_lba - 1))
            (( end_lba >= start_lba )) || die "[ERROR]: invalid partition bounds for '$partName' (start LBA ${start_lba}, end LBA ${end_lba})"
            partition_size=$((next_offset_b - offset_b))
            free_size=$((partition_size - image_size))
        else
            # Last partition: let GPT consume the remaining space.
            end_lba=0
            partition_size=0
            free_size=0
        fi

        debug "PART[$i] name=$partName start_b=$offset_b start_lba=$start_lba next_idx=$next_idx next_b=$next_offset_b end_lba=$end_lba image_size=$image_size partition_size=$partition_size free_size=$free_size"

        if (( free_size < 0 )); then
            if [[ "$partName" == "rootfs" || "$partName" == "rootfs-a" ]] && [[ $_FORCE_ROOTFS_SIZE -eq 1 ]]; then
                info "[WARNING]: image '$bin2flash' is larger than '$partName', trying to move following partitions"
                local grown_next_offset_b=$((offset_b + image_size + DEFAULT_PADDING_SIZE))
                if [[ "$next_idx" == "-1" ]]; then
                    die "[ERROR]: cannot auto-grow the last partition '$partName'"
                fi
                move_partition_offset "$next_idx" "$grown_next_offset_b"
                if (( grown_next_offset_b > DEFAULT_RAW_SIZE * 1024 * 1024 )); then
                    die "[ERROR]: rootfs growth would exceed raw image size (${DEFAULT_RAW_SIZE} MB)"
                fi
                next_offset_b=$grown_next_offset_b
                end_lba=$(bytes_to_lba "$next_offset_b")
                end_lba=$((end_lba - 1))
            else
                die "[ERROR]: image too big for partition '$partName' ($image_size_in_mb MB)"
            fi
        fi

        if [[ "$next_idx" == "-1" ]]; then
            local temp_end_offset_b=$((offset_b + image_size))
            if (( temp_end_offset_b > DEFAULT_RAW_SIZE * 1024 * 1024 )); then
                die "[ERROR]: last partition '$partName' does not fit in ${DEFAULT_RAW_SIZE} MB"
            fi
        fi

        local gpt_code=""
        case "$partType" in
            Binary)
                gpt_code="8301"
                ;;
            FIP)
                gpt_code="$DEFAULT_FIP_TYPEUUID"
                ;;
            FWU_MDATA)
                gpt_code="$DEFAULT_FWU_MDATA_TYPEUUID"
                ;;
            System|FileSystem)
                gpt_code="8300"
                ;;
            ESP)
                gpt_code="ef00"
                ;;
            ENV)
                gpt_code="$DEFAULT_UBOOT_ENV_TYPEUUID"
                ;;
            *)
                die "[ERROR]: invalid partition type '$partType' for '$partName'"
                ;;
        esac

        local sgdisk_cmd=(sgdisk -a 1 -n "${part_no}:${start_lba}:${end_lba}" -c "${part_no}:${partName}" -t "${part_no}:${gpt_code}")
        if [[ -n "$extrafs_param" ]]; then
            # shellcheck disable=SC2206
            local extra_parts=( $extrafs_param )
            sgdisk_cmd+=("${extra_parts[@]}")
        fi
        sgdisk_cmd+=("$FLASHLAYOUT_rawname")

        printf "part %d: %8s ..." "$part_no" "$partName"
        exec_print "${sgdisk_cmd[*]}"
        "${sgdisk_cmd[@]}" &>"$_REDIRECT" || die "SGDISK: failed to create GPT partition '$partName'"

        local created_size created_unit
        created_size=$(sgdisk -p "$FLASHLAYOUT_rawname" | awk -v name="$partName" '$0 ~ name && $0 !~ "-"name && $0 !~ /First usable/ {print $4; exit}')
        created_unit=$(sgdisk -p "$FLASHLAYOUT_rawname" | awk -v name="$partName" '$0 ~ name && $0 !~ "-"name && $0 !~ /First usable/ {print $5; exit}')
        printf "\r[CREATED] part %02d: %10s [partition size %s %s]\n" "$part_no" "$partName" "${created_size:-?}" "${created_unit:-?}"

        ((part_no++))
        ((visible_index++))
    done

    echo
    info "Partition table from '$FLASHLAYOUT_rawname'"
    exec_print "sgdisk -p '$FLASHLAYOUT_rawname'"
    sgdisk -p "$FLASHLAYOUT_rawname" &>"$_REDIRECT"

    local info_idx
    for info_idx in $display_info; do
        echo
        exec_print "sgdisk '$FLASHLAYOUT_rawname' -i $info_idx"
        sgdisk "$FLASHLAYOUT_rawname" -i "$info_idx"
    done
    echo
}

populate_gpt_partition_table_from_flash_layout() {
    local i
    local part_no=1

    info "Populate raw image with image content:"

    for ((i = 0; i < FL_COUNT; i++)); do
        if ! is_programmed_row "$i"; then
            continue
        fi

        local partName="${FL_PARTNAME[$i]}"
        local bin2flash="${FL_BIN2FLASH[$i]}"
        local offset_b
        offset_b=$(hex_to_dec "${FL_OFFSET[$i]}")

        if is_populated_row "$i"; then
            if [[ -n "$bin2flash" && "$bin2flash" != "none" && -e "$FLASHLAYOUT_prefix_image_path/$bin2flash" ]]; then
                printf "part %02d: %10s, image: %s ..." "$part_no" "$partName" "$bin2flash"
                exec_print "dd if='$FLASHLAYOUT_prefix_image_path/$bin2flash' of='$FLASHLAYOUT_rawname' conv=fdatasync,notrunc seek=1 bs=$offset_b"
                dd if="$FLASHLAYOUT_prefix_image_path/$bin2flash" of="$FLASHLAYOUT_rawname" \
                    conv=fdatasync,notrunc seek=1 bs="$offset_b" &>"$_REDIRECT" \
                    || die "DD: failed while writing '$bin2flash' into '$partName'"
                printf "\r[ FILLED ] part %02d: %10s, image: %s \n" "$part_no" "$partName" "$bin2flash"
            else
                if [[ "$(basename -- "$bin2flash")" != "none" && -n "$bin2flash" ]]; then
                    printf "\r[UNFILLED] part %02d: %10s, image: %s (not present) \n" "$part_no" "$partName" "$bin2flash"
                    echo "   [WARNING]: file '$FLASHLAYOUT_prefix_image_path/$bin2flash' is not present."
                    echo "   [WARNING]: partition '$partName' was left empty."
                    WARNING_TEXT+="[WARNING]: partition '$partName' was left empty (missing file '$FLASHLAYOUT_prefix_image_path/$bin2flash')#"
                else
                    printf "\r[UNFILLED] part %02d: %10s, image: none \n" "$part_no" "$partName"
                fi
            fi
        else
            printf "\r[UNFILLED] part %02d: %10s \n" "$part_no" "$partName"
        fi

        ((part_no++))
    done
}

print_schema_on_infofile() {
    local i
    local j=1

    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            echo -n "==============" >> "$FLASHLAYOUT_infoname"
        fi
    done
    echo "=" >> "$FLASHLAYOUT_infoname"

    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            echo -n "=             " >> "$FLASHLAYOUT_infoname"
        fi
    done
    echo "=" >> "$FLASHLAYOUT_infoname"

    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            printf "=  %09s  " "${FL_PARTNAME[$i]}" >> "$FLASHLAYOUT_infoname"
        fi
    done
    echo "=" >> "$FLASHLAYOUT_infoname"

    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            echo -n "=             " >> "$FLASHLAYOUT_infoname"
        fi
    done
    echo "=" >> "$FLASHLAYOUT_infoname"

    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            printf "= %09s%-2d " "${DEFAULT_DEVICE_PART}" "$j" >> "$FLASHLAYOUT_infoname"
            ((j++))
        fi
    done
    echo "=" >> "$FLASHLAYOUT_infoname"

    j=1
    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            printf "=      (%-2d)   " "$j" >> "$FLASHLAYOUT_infoname"
            ((j++))
        fi
    done
    echo "=" >> "$FLASHLAYOUT_infoname"

    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            echo -n "=             " >> "$FLASHLAYOUT_infoname"
        fi
    done
    echo "=" >> "$FLASHLAYOUT_infoname"

    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            echo -n "==============" >> "$FLASHLAYOUT_infoname"
        fi
    done
    echo "=" >> "$FLASHLAYOUT_infoname"

    j=1
    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            {
                echo "($j):"
                echo "    Device: /dev/${DEFAULT_DEVICE_PART}$j"
                echo "    Label:  ${FL_PARTNAME[$i]}"
                if [[ -n "${FL_BIN2FLASH[$i]}" ]]; then
                    echo "    Image:  ${FL_BIN2FLASH[$i]}"
                else
                    echo "    Image:"
                fi
            } >> "$FLASHLAYOUT_infoname"
            ((j++))
        fi
    done
}

print_populate_on_infofile() {
    local i
    local j=1
    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            echo "- Populate partition ${FL_PARTNAME[$i]} (/dev/${DEFAULT_DEVICE_PART}$j)" >> "$FLASHLAYOUT_infoname"
            if [[ -n "${FL_BIN2FLASH[$i]}" && "${FL_BIN2FLASH[$i]}" != "none" ]]; then
                echo "    dd if=${FL_BIN2FLASH[$i]} of=/dev/${DEFAULT_DEVICE_PART}$j bs=1M conv=fdatasync status=progress" >> "$FLASHLAYOUT_infoname"
            else
                echo "    dd if=<raw image of ${FL_PARTNAME[$i]}> of=/dev/${DEFAULT_DEVICE_PART}$j bs=1M conv=fdatasync status=progress" >> "$FLASHLAYOUT_infoname"
            fi
            echo >> "$FLASHLAYOUT_infoname"
            ((j++))
        fi
    done
}

print_mount_on_infofile() {
    local i
    local j=1
    for ((i = 0; i < FL_COUNT; i++)); do
        if is_programmed_row "$i"; then
            if selection_test "${FL_PARTTYPE[$i]}" System FileSystem; then
                echo "- Mount manually partition ${FL_PARTNAME[$i]} (/dev/${DEFAULT_DEVICE_PART}$j)" >> "$FLASHLAYOUT_infoname"
                echo "    udiskctl mount -b /dev/disk/by-partlabel/${FL_PARTNAME[$i]}" >> "$FLASHLAYOUT_infoname"
                echo >> "$FLASHLAYOUT_infoname"
            fi
            ((j++))
        fi
    done
}

create_info() {
    cat > "$FLASHLAYOUT_infoname" <<EOF_INFO
This file describes how to update manually the SD card partitions:
1. SD card partition scheme
2. How to populate each partition
3. How to mount each partition manually
4. How to update the kernel and device tree

1. SD card partition scheme:
---------------------------
EOF_INFO

    print_schema_on_infofile

    cat >> "$FLASHLAYOUT_infoname" <<EOF_INFO

2. How to populate each partition
---------------------------------
EOF_INFO

    print_populate_on_infofile

    cat >> "$FLASHLAYOUT_infoname" <<EOF_INFO

3. How to mount each partition manually
---------------------------------------
EOF_INFO

    print_mount_on_infofile

    cat >> "$FLASHLAYOUT_infoname" <<EOF_INFO

4. How to update the kernel and device tree
-------------------------------------------
The kernel and device tree are stored in the boot partition.
To update them manually:
- insert the SD card into your PC
- copy the kernel image to bootfs
    sudo cp uImage /media/\$USER/bootfs/
- copy the device tree to bootfs
    sudo cp stm32mp*.dtb /media/\$USER/bootfs/
- unmount all SD card partitions
    sudo umount /media/\$USER/bootfs/
    sudo umount \`lsblk --list | grep ${DEFAULT_DEVICE} | grep part | gawk '{ print \$7 }' | tr '\\n' ' '\`
EOF_INFO
}

print_warning() {
    if [[ -n "$WARNING_TEXT" ]]; then
        echo
        echo "???????????????????????????????????????????????????????????????????????????"
        local old_ifs="$IFS"
        IFS=$'\n'
        local t
        for t in $(echo "$WARNING_TEXT" | tr '#' '\n'); do
            [[ -n "$t" ]] && echo "$t"
        done
        IFS="$old_ifs"
        echo "[WARNING]: the board may not boot correctly because some files are missing."
        echo "???????????????????????????????????????????????????????????????????????????"
    fi
}

usage() {
    cat <<EOF_USAGE
Help:
    $0 [-h|--help] [--compress] [--force-rootfs] <FlashLayout file>

Options:
    -h, --help       Show this help
    --compress       Compress the generated raw image using xz
    --force-rootfs   Force the predefined rootfs size ($((${DEFAULT_ROOTFS_PARTITION_SIZE} / 1024)) MiB)

Environment variables:
    SDCARD_SIZE=<size in MiB>
        Limit the raw image size.
        Example: SDCARD_SIZE=2048 $0 <flashlayout.tsv>

    DEVICE=<device name>
        Customize helper text for the target block device.
        Example: DEVICE=sdb $0 <flashlayout.tsv>
EOF_USAGE
    exit 1
}

parse_args() {
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            --compress)
                _COMPRESS_RAW_IMAGE=1
                ;;
            --force-rootfs)
                _FORCE_ROOTFS_SIZE=1
                ;;
            -*)
                die "Wrong parameter: $1"
                ;;
            *)
                positional+=("$1")
                ;;
        esac
        shift
    done

    if [[ ${#positional[@]} -ne 1 ]]; then
        echo "[ERROR]: bad number of parameters"
        usage
    fi

    FLASHLAYOUT_filename="${positional[0]}"
}

prepare_paths() {
    FLASHLAYOUT_filename_path=$(dirname "$FLASHLAYOUT_filename")
    local filename_name dirname_name extension
    filename_name=$(basename "$FLASHLAYOUT_filename")
    dirname_name=$(basename "$FLASHLAYOUT_filename_path")
    extension="${FLASHLAYOUT_filename##*.}"

    [[ "$extension" == "tsv" ]] || die "[ERROR]: FlashLayout file must have .tsv extension"
    [[ -f "$FLASHLAYOUT_filename" ]] || die "[ERROR]: FlashLayout file '$FLASHLAYOUT_filename' does not exist"

    if ! grep -qi "$SDCARD_TOKEN" "$FLASHLAYOUT_filename"; then
        die "[WARNING]: the FlashLayout does not contain SDCARD token '$SDCARD_TOKEN': $FLASHLAYOUT_filename"
    fi

    local filename_for_raw_to_use
    if echo "$dirname_name" | grep -q flashlayout; then
        filename_for_raw_to_use="$FLASHLAYOUT_filename_path/$(echo "$dirname_name/$filename_name" | sed -e 's|/|_|g')"
    else
        filename_for_raw_to_use="$FLASHLAYOUT_filename"
    fi

    FLASHLAYOUT_rawname=$(basename "$filename_for_raw_to_use" | sed -e 's/tsv/raw/')
    FLASHLAYOUT_infoname=$(basename "$filename_for_raw_to_use" | sed -e 's/tsv/how_to_update.txt/')
}

main() {
    parse_args "$@"
    tools_check
    prepare_paths
    read_flash_layout
    resolve_image_prefix

    FLASHLAYOUT_rawname="$FLASHLAYOUT_prefix_image_path/$FLASHLAYOUT_rawname"
    FLASHLAYOUT_infoname="$FLASHLAYOUT_prefix_image_path/$FLASHLAYOUT_infoname"

    rm -f "$FLASHLAYOUT_rawname" "$FLASHLAYOUT_infoname"
	

    debug "FlashLayout file:      $FLASHLAYOUT_filename"
    debug "FlashLayout dir path:  $FLASHLAYOUT_filename_path"
    debug "Images dir path:       $FLASHLAYOUT_prefix_image_path"
    debug "Raw image path:        $FLASHLAYOUT_rawname"
    debug "Info file path:        $FLASHLAYOUT_infoname"

    generate_empty_raw_image
    generate_gpt_partition_table_from_flash_layout
    populate_gpt_partition_table_from_flash_layout

    if [[ $_COMPRESS_RAW_IMAGE -eq 1 ]]; then
        info "Compress Raw image"
        rm -f "${FLASHLAYOUT_rawname}.xz"
        xz -z -v "$FLASHLAYOUT_rawname"
    fi

    create_info
    print_warning
}

main "$@"
