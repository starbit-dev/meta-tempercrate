#!/bin/sh

PATH=/sbin:/bin:/usr/sbin:/usr/bin

resize_enabled() {
    return 0
}

resize_run() {
    ln -s /proc/mounts /etc/mtab

    if [ -n "$ROOTFS_DIR" ]; then
        if [ ! -e "$ROOTFS_DIR/etc/.resized" ]; then
            # check command line to know storage device used
            if [ -n "$bootparam_root" ]; then
                debug "No e2fs compatible filesystem has been mounted, mounting $bootparam_root..."

                if [ "`echo ${bootparam_root} | cut -c1-5`" = "UUID=" ]; then
                    root_uuid=`echo $bootparam_root | cut -c6-`
                    bootparam_root="/dev/disk/by-uuid/$root_uuid"
                elif [ "`echo ${bootparam_root} | cut -c1-9`" = "PARTUUID=" ]; then
                    root_partuuid=`echo $bootparam_root | cut -c10-`
                    bootparam_root="/dev/disk/by-partuuid/$root_partuuid"
                elif [ "`echo ${bootparam_root} | cut -c1-10`" = "PARTLABEL=" ]; then
                    root_partlabel=`echo $bootparam_root | cut -c11-`
                    bootparam_root="/dev/disk/by-partlabel/$root_partlabel"
                elif [ "`echo ${bootparam_root} | cut -c1-6`" = "LABEL=" ]; then
                    root_label=`echo $bootparam_root | cut -c7-`
                    bootparam_root="/dev/disk/by-label/$root_label"
                fi

                if [ -e "$bootparam_root" ]; then
                    bootparam_root_device=$(busybox readlink "$bootparam_root" -f)
                    j=$(echo "$bootparam_root_device" | sed "s|/dev/mmcblk\([0-2]\)p.*|\1|")

                    USERFS_EXPANDED=0
                    USERFS_DEVICE=""

                    for i in 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
                        DEVICE="/dev/mmcblk"$j"p"$i
                        if [ -e "$DEVICE" ]; then
                            label=$(/sbin/e2label "$DEVICE" 2> /dev/null)
                            if [ $? -eq 0 ]; then
                                case $label in
                                user*)
                                    echo "CHECK USERFS [$DEVICE]"

                                    PART="$DEVICE"
                                    PARTNUM="$(echo "$PART" | sed -n 's/.*p\([0-9]\+\)$/\1/p')"
                                    DISK="$(echo "$PART" | sed -n 's/^\(.*\)p[0-9]\+$/\1/p')"

                                    if [ -n "$PARTNUM" ] && [ -n "$DISK" ]; then
                                        echo "EXPAND USERFS PARTITION [$PART]"
                                        echo "<6>EXPAND USERFS PARTITION [$PART]" > /dev/kmsg || true

                                        /sbin/sgdisk -e "$DISK" || true
                                        /sbin/partprobe "$DISK" || true
                                        /sbin/udevadm settle || true
                                        sleep 2

                                        /usr/sbin/parted -s "$DISK" resizepart "$PARTNUM" 100%
                                        /sbin/partprobe "$DISK" || true
                                        /sbin/udevadm settle || true
                                        sleep 2
                                    fi

                                    FS_BLOCKS=$(dumpe2fs -h "$DEVICE" 2>/dev/null | awk '/Block count:/ {print $3}')
                                    PART_SIZE=$(blockdev --getsize64 "$DEVICE" 2>/dev/null)
                                    PART_BLOCKS=$((PART_SIZE / 1024))

                                    if [ -z "$FS_BLOCKS" ] || [ -z "$PART_SIZE" ] || [ "$PART_SIZE" -le 0 ]; then
                                        echo "USERFS size detection failed, forcing resize [$DEVICE]"
                                        DO_RESIZE=1
                                    elif [ "$FS_BLOCKS" -lt "$PART_BLOCKS" ]; then
                                        DO_RESIZE=1
                                    else
                                        DO_RESIZE=0
                                    fi

                                    if [ "$DO_RESIZE" -eq 1 ]; then
                                        echo "RESIZE USERFS [$DEVICE]"
                                        /sbin/e2fsck -f -y "$DEVICE" || true
                                        /sbin/resize2fs "$DEVICE"

                                        USERFS_EXPANDED=1
                                        USERFS_DEVICE="$DEVICE"
                                    else
                                        echo "USERFS already full size, skipping resize [$DEVICE]"
                                    fi
                                    ;;
                                root*)
                                    echo "RESIZE ROOTFS [$DEVICE]"
                                    /sbin/resize2fs "$DEVICE"
                                    ;;
                                vendor*)
                                    echo "RESIZE VENDORFS [$DEVICE]"
                                    /sbin/e2fsck -f -y -c -C 0 "$DEVICE" && /sbin/resize2fs "$DEVICE"
                                    ;;
                                boot*)
                                    echo "RESIZE BOOTFS [$DEVICE]"
                                    /sbin/e2fsck -f -y -c -C 0 "$DEVICE" && /sbin/resize2fs "$DEVICE"
                                    ;;
                                *)
                                    ;;
                                esac
                            fi
                        fi
                    done

                    if [ "$USERFS_EXPANDED" = "1" ]; then
                        touch "$ROOTFS_DIR/etc/.userfs-expanded"
                        {
                            echo "userfs expanded successfully"
                            echo "device=$USERFS_DEVICE"
                            date
                        } > "$ROOTFS_DIR/etc/userfs-expanded.log"
                    fi

                    touch "$ROOTFS_DIR/etc/.resized"
                fi
            fi
        fi
    fi
}