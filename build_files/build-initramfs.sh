#!/usr/bin/bash
set -Eeuo pipefail
trap 'printf "Initramfs failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

mapfile -t kernels < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
[[ ${#kernels[@]} -eq 1 ]] || { echo 'Expected one image kernel' >&2; exit 1; }
kernel=${kernels[0]}
output=/usr/lib/modules/$kernel/initramfs.img
scratch=$(mktemp -d /tmp/dell-initramfs.XXXXXX)
trap 'rm -rf "$scratch"' EXIT

# Modules from the working Dell initramfs. Preserve Aurora's authentication
# and crypto support; no Alienware-specific exclusions are applied.
modules=(nss-softokn bash systemd fips fips-crypto-policies
    systemd-ask-password systemd-battery-check systemd-cryptsetup systemd-initrd
    systemd-journald systemd-modules-load systemd-pcrphase systemd-sysctl
    systemd-tmpfiles systemd-udevd i18n drm plymouth ostree bootc systemd-sysusers
    btrfs crypt dm fs-lib kernel-modules prefixdevname fido2 pcsc pkcs11 tpm2-tss
    rootfs-block terminfo udev-rules dracut-systemd initqueue usrmount base
    memstrack shell-interpreter shutdown openssl)

# Boot hardware, removable USB storage and console input. Dependencies come
# from this image's kernel, never the GitHub runner. Built-in drivers need no file.
seeds=(i915 nvme dm_crypt btrfs ext4 vfat erofs overlay tpm_tis
    xhci_pci usb_storage uas sd_mod usbhid hid_generic atkbd i8042
    i2c_hid_acpi hid_multitouch intel_lpss_pci pinctrl_tigerlake)
declare -A allowed=()
# Keep all kernel crypto implementations, including algorithms selected by LUKS.
while IFS= read -r path; do
    seeds+=("$(modinfo -F name "$path")")
done < <(find "/usr/lib/modules/$kernel/kernel/crypto" "/usr/lib/modules/$kernel/kernel/arch/x86/crypto" -type f -name '*.ko*')
# Preserve upstream preload requirements instead of causing modules-load errors.
while IFS= read -r driver; do
    [[ -n $driver ]] || continue
    if modinfo -k "$kernel" "$driver" >/dev/null 2>&1; then seeds+=("$driver"); fi
done < <(find /usr/lib/modules-load.d /etc/modules-load.d -type f -name '*.conf' -exec sed -E '/^[[:space:]]*(#|;|$)/d; s/^[[:space:]]+//; s/[[:space:]]+$//' {} +)
for driver in "${seeds[@]}"; do
    modinfo -k "$kernel" "$driver" >/dev/null
    deps=$(modprobe --show-depends -S "$kernel" "$driver")
    while read -r action path _; do
        [[ $action == insmod ]] || continue
        allowed["$(modinfo -F name "$path")"]=1
    done <<< "$deps"
done
mapfile -t drivers < <(printf '%s\n' "${!allowed[@]}" | sort)
omit=()
while IFS= read -r path; do
    name=$(modinfo -F name "$path")
    [[ -v allowed[$name] ]] || omit+=("$name")
done < <(find "/usr/lib/modules/$kernel" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' \))

# Same reproducibility convention as Aurora's official initramfs build.
cp /usr/lib/os-release "$scratch/os-release"
sed -Ei '/^((OSTREE_)?(IMAGE_)?VERSION|PRETTY_NAME|BUILD_ID)=/d' /usr/lib/os-release
DRACUT_NO_XATTR=1 dracut --force --reproducible --kver "$kernel" \
    --no-hostonly --no-hostonly-cmdline --no-hostonly-i18n \
    --modules "${modules[*]}" --drivers "${drivers[*]}" \
    --omit-drivers "${omit[*]}" \
    --install /usr/lib/kbd/keymaps/legacy/i386/qwerty/it.map.gz --strip "$output"
cp "$scratch/os-release" /usr/lib/os-release
lsinitrd "$output" > "$scratch/list"
lsinitrd -m "$output" > "$scratch/modules"
mkdir "$scratch/unpack"
(cd "$scratch/unpack" && lsinitrd --unpack "$output")

for module in "${modules[@]}"; do
    grep -Fxq "$module" "$scratch/modules"
done
for driver in "${seeds[@]}"; do
    path=$(modinfo -k "$kernel" -n "$driver")
    [[ $path == '(builtin)' ]] || grep -Fq "/$(basename "$path")" "$scratch/list"
done
for pattern in 'systemd-cryptsetup' 'libcryptsetup-token-systemd-tpm2.so' \
    'libtss2-esys.so' 'ostree-prepare-root' 'bootc/initramfs-setup' 'GenuineIntel.bin' 'it.map'; do
    grep -Fq "$pattern" "$scratch/list"
done

# Reject host identifiers/configuration, rather than publishing a local initrd.
for path in etc/crypttab etc/block_uuid.map etc/fstab; do
    [[ ! -s "$scratch/unpack/$path" ]] || { echo "Unexpected host file: $path" >&2; exit 1; }
done
if [[ -s "$scratch/unpack/etc/machine-id" ]]; then
    [[ $(< "$scratch/unpack/etc/machine-id") == uninitialized ]]
fi
if [[ -s "$scratch/unpack/etc/hostname" ]]; then
    case $(< "$scratch/unpack/etc/hostname") in localhost|localhost.localdomain) ;; *) exit 1 ;; esac
fi
if [[ -d $scratch/unpack/etc/cmdline.d ]]; then
    if grep -RIEq 'UUID=|rd\.luks\.(uuid|name)=' "$scratch/unpack/etc/cmdline.d"; then
        echo 'Unexpected host kernel arguments' >&2
        exit 1
    fi
fi
while IFS= read -r path; do
    name=$(modinfo -F name "$path")
    [[ -v allowed[$name] ]] || { echo "Unexpected driver: $name" >&2; exit 1; }
done < <(find "$scratch/unpack/usr/lib/modules" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' \))
chmod 0600 "$output"
touch -d '1970-01-01T00:00:00Z' "$output"
du -h "$output"
