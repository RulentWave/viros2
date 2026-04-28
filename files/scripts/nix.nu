#!/usr/bin/env nu

const NIXMOUNT = "[Unit]
Description=Bind mount /var/lib/nix on /nix
RequiresMountsFor=/var/lib/nix
ConditionPathIsDirectory=/var/lib/nix
DefaultDependencies=no
Before=local-fs.target
After=var.mount

[Mount]
What=/var/lib/nix
Where=/nix
Type=none
Options=bind

[Install]
WantedBy=local-fs.target
"

try { mkdir /nix } catch { |e|
  print $"Could not create /nix directory: ($e.msg)"
  return $e
}

try {
  mkdir /var/lib/nix
} catch { |e|
  print $"Could not create /var/lib/nix directory: ($e.msg)"
  return $e
}

# try {
#   mount --bind /var/lib/nix /nix
# } catch { |e|
#   print $"Could not bind /var/lib/nix to /nix: ($e.msg)"
#   return $e
# }

dnf -y install nix

try {
  rsync -a /nix /var/lib/nix
} catch {|e|
  print $"Failed to copy files from /nix to /var/lib/nix using rsync: ($e.msg)"
  return $e
}
try {
  $NIXMOUNT | save /usr/lib/systemd/system/nix.mount
} catch {|e|
  print $"Could not save nix.mount to /usr/lib/systemd/system: ($e.msg)"
  return $e
}
