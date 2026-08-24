#!/usr/bin/env bash
# Runs inside the live-ISO chroot after packages are installed.
set -uo pipefail

# Everything here addresses differences in Arch Linux ARM's kernel packaging.
# On any other architecture this script is a no-op.
if [[ $(uname -m) != aarch64 ]]; then
  exit 0
fi

# Omarchy forces the thunderbolt module; ALARM's aarch64 kernel does not build
# it, and mkinitcpio treats an unresolvable MODULES entry as an error.
if [[ -f /etc/mkinitcpio.conf.d/thunderbolt_module.conf ]]; then
  sed -i 's/^MODULES+=(thunderbolt)/#MODULES+=(thunderbolt)  # not built for aarch64/' \
    /etc/mkinitcpio.conf.d/thunderbolt_module.conf
fi

# ALARM's linux-aarch64 installs /boot/Image rather than /boot/vmlinuz-<name>.
# Give the preset the filename it expects.
if [[ -e /boot/Image && ! -e /boot/vmlinuz-linux-aarch64 ]]; then
  cp -a /boot/Image /boot/vmlinuz-linux-aarch64
fi

# Drop presets whose kernel image is absent: `mkinitcpio -P` aborts on them.
for preset in /etc/mkinitcpio.d/*.preset; do
  [[ -e $preset ]] || continue
  kname="$(basename "$preset" .preset)"
  if [[ $kname != linux-aarch64 && ! -e /boot/vmlinuz-$kname ]]; then
    echo "customize_airootfs: dropping $kname.preset (no kernel image)"
    rm -f "$preset"
  fi
done

# The equivalent of x86's linux-t2.preset: archiso_config makes mkinitcpio read
# archiso.conf as its configuration, bypassing /etc/mkinitcpio.conf.d entirely.
# That is what stops omarchy_hooks.conf -- which describes an *installed*
# system -- from replacing the archiso hooks in the *live* initramfs.
cat > /etc/mkinitcpio.d/linux-aarch64.preset <<'PRESET'
# Live-ISO preset for Arch Linux ARM's linux-aarch64.
PRESETS=('archiso')

ALL_kver='/boot/vmlinuz-linux-aarch64'
archiso_config='/etc/mkinitcpio.conf.d/archiso.conf'

archiso_image="/boot/initramfs-linux-aarch64.img"
PRESET

echo "customize_airootfs: building the live initramfs from archiso.conf"
rm -f /boot/initramfs-linux*.img
mkinitcpio -p linux-aarch64 || echo "customize_airootfs: WARNING mkinitcpio failed"
if compgen -G "/boot/initramfs-*.img" >/dev/null; then
  echo "customize_airootfs: initramfs present"
else
  echo "customize_airootfs: ERROR no initramfs produced"
fi

exit 0
