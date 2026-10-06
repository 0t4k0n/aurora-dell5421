#!/usr/bin/bash
set -euo pipefail

cp -a /ctx/system_files/. /
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-chatgpt
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-NordVPN

# All RPM changes belong to the published image, never to a client-side layer.
dnf5 install -y btrfs-assistant snapper nordvpn chatgpt
if rpm -q sunshine >/dev/null 2>&1; then
    dnf5 remove --no-autoremove -y sunshine
fi

# Preserve Aurora's mutable /opt layout; publish the GUI payload under /usr.
test "$(readlink /opt)" = "var/opt"
unlink /opt
mkdir /opt
dnf5 install -y nordvpn-gui
mv /opt/nordvpn-gui /usr/lib/nordvpn-gui
rmdir /opt
ln -s var/opt /opt
ln -sfn /usr/lib/nordvpn-gui/nordvpn-gui /usr/sbin/nordvpn-gui
if [[ -d /var/lib/nordvpn/data ]]; then
    mkdir -p /usr/share/nordvpn
    mv /var/lib/nordvpn/data /usr/share/nordvpn/data
fi
systemctl enable nordvpnd.service

# Sunshine also supplies a preload snippet independently of the boot payload.
rm -f /usr/lib/modules-load.d/60-sunshine.conf

# Keep Aurora's OS name and version; image identity lives in OCI metadata.
/usr/bin/bash /ctx/build-initramfs.sh
install -Dm0644 /ctx/cosign.pub /etc/pki/containers/aurora-dell5421.pub
policy_tmp=$(mktemp)
jq '.transports.docker["ghcr.io/0t4k0n/aurora-dell5421"] = [{"type":"sigstoreSigned","keyPath":"/etc/pki/containers/aurora-dell5421.pub","signedIdentity":{"type":"matchRepository"}}]' /etc/containers/policy.json > "$policy_tmp"
install -m0644 "$policy_tmp" /etc/containers/policy.json
rm -f "$policy_tmp"
for package in btrfs-assistant snapper nordvpn nordvpn-gui chatgpt; do
    rpm -q "$package"
done
! rpm -q sunshine >/dev/null 2>&1
dnf5 clean all
