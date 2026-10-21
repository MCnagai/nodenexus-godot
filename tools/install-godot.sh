#!/usr/bin/env bash
set -euo pipefail
version=4.7.2
root=${1:?Usage: install-godot.sh INSTALL_DIRECTORY}
mkdir -p "$root/bin" "$root/downloads" "$root/data/godot/export_templates/$version.stable"
base="https://github.com/godotengine/godot/releases/download/$version-stable"
cd "$root/downloads"
curl --fail --location --retry 3 "$base/SHA512-SUMS.txt" -o SHA512-SUMS.txt
for artifact in "Godot_v$version-stable_linux.x86_64.zip" "Godot_v$version-stable_export_templates.tpz"; do
  if ! grep -F " $artifact" SHA512-SUMS.txt | sha512sum --check --status; then
    curl --fail --location --retry 3 "$base/$artifact" -o "$artifact"
  fi
  grep -F " $artifact" SHA512-SUMS.txt | sha512sum --check
done
unzip -oq "Godot_v$version-stable_linux.x86_64.zip" -d "$root/bin"
chmod +x "$root/bin/Godot_v$version-stable_linux.x86_64"
ln -sfn "Godot_v$version-stable_linux.x86_64" "$root/bin/godot"
unzip -oq "Godot_v$version-stable_export_templates.tpz" 'templates/web*' -d extracted
cp extracted/templates/web* "$root/data/godot/export_templates/$version.stable/"
