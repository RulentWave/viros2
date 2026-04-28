#!/usr/bin/env nu

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
}
